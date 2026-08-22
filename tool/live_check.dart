// Exercises the app's own data layer against a real webtrees instance.
//
// The Phase 0 spike (tool/probe.dart) proved the wire protocol using dart:io.
// This proves the shipping stack — dio, its cookie manager, and the app's
// InstanceProbe and WebtreesSession — behaves identically. The riskiest part
// is cookie handling: webtrees names its cookie by scheme, sets an explicit
// Domain, and rotates the session id inside the sign-in redirect.
//
// Usage:
//   dart run tool/live_check.dart --url tree.almou.sa --user NAME
//   WEBTREES_PASSWORD=... dart run tool/live_check.dart --url ... --user ...
//
// The password is read from WEBTREES_PASSWORD, or from the terminal with echo
// disabled. It is never written to disk.

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/access_probe.dart';
import 'package:webtrees_mobile/data/instance_probe.dart';
import 'package:webtrees_mobile/data/session.dart';
import 'package:webtrees_mobile/data/stock/records_repository.dart';
import 'package:webtrees_mobile/domain/dates.dart';
import 'package:webtrees_mobile/domain/records.dart';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    options[args[i].replaceFirst('--', '')] = args[i + 1];
  }

  final address = options['url'];
  if (address == null) {
    stderr.writeln(
      'Usage: dart run tool/live_check.dart --url HOST '
      '[--user NAME] [--search TERM] [--language TAG]',
    );
    exitCode = 64;
    return;
  }

  final cookies = CookieJar();
  final client = WebtreesClient(
    url: WebtreesUrl(
      base: WebtreesUrl.normalize(address),
      style: UrlStyle.ugly,
    ),
    cookies: cookies,
  );

  var failures = 0;
  void report(String label, Object? value, {bool ok = true}) {
    if (!ok) failures++;
    stdout.writeln('  ${ok ? 'PASS' : 'FAIL'}  $label: $value');
  }

  try {
    stdout.writeln('\n=== Connect ===');
    final instance = await InstanceProbe(client).connect();
    report('address', instance.url.base);
    report('URL style', instance.url.style.name);
    report(
      'version',
      instance.version.isEmpty ? '(unknown)' : instance.version,
    );
    report('health', instance.health.name);
    for (final warning in instance.warnings) {
      stdout.writeln('  WARN  $warning');
    }

    // The cookie jar is the thing most likely to differ from the dart:io
    // spike, so check it explicitly rather than inferring it from later steps.
    final stored = await cookies.loadForRequest(instance.url('/'));
    report(
      'session cookie held',
      stored.isEmpty ? 'NONE' : stored.map((c) => c.name).join(', '),
      ok: stored.isNotEmpty,
    );

    final username = options['user'];
    if (username == null) {
      stdout.writeln('\nNo --user given; stopping after anonymous checks.');
      return;
    }

    final password = _readPassword(username);
    if (password.isEmpty) {
      report('password', 'not supplied', ok: false);
      return;
    }

    stdout.writeln('\n=== Sign in ===');
    final session = WebtreesSession(client);
    final before = (await cookies.loadForRequest(instance.url('/'))).first;

    await session.signIn(username, password);
    report('signed in', 'yes');

    final after = (await cookies.loadForRequest(instance.url('/'))).first;
    report(
      'session id rotated on sign-in',
      after.value == before.value ? 'NO — the cookie did not change' : 'yes',
      ok: after.value != before.value,
    );
    report('session survives a fresh request', await session.isSignedIn());

    // The site writes the dates and the fact labels, in the language held in
    // its own session — which it seeds from the account's preference, not from
    // anything the app sent. Nothing else the app does can change that.
    stdout.writeln('\n=== Language ===');
    final language = options['language'] ?? 'ar';
    await session.useLanguage(language);
    report('server asked to render in', language);

    stdout.writeln('\n=== Access ===');
    final access = await AccessProbe(client).describe();
    report('account', access.account.displayName);
    report('email', access.account.email ?? '(none)');
    report('site administrator', access.isAdministrator ? 'yes' : 'no');
    for (final tree in access.trees) {
      report(
        'tree "${tree.name}"',
        '${tree.title ?? '(no title read)'} · ${tree.role.name}'
            '${tree.myXref == null ? '' : ' · own record ${tree.myXref}'}'
            ' · edit=${tree.role.canEdit}'
            ' moderate=${tree.role.canModerate}'
            ' manage=${tree.role.canManage}',
      );
    }
    for (final warning in access.warnings) {
      stdout.writeln('  WARN  $warning');
    }

    // The parsers are the part most likely to break against a real site:
    // fixtures are transcribed from upstream templates, so only a live tree
    // proves the selectors survive this instance's theme, language and
    // modules.
    stdout.writeln('\n=== Records ===');
    final tree = access.trees.isEmpty ? null : access.trees.first;
    if (tree == null) {
      stdout.writeln('  SKIP  no readable tree');
    } else {
      final records = RecordsRepository(client, version: instance.version);

      final term = options['search'] ?? tree.myXref ?? 'a';
      final found = await records.search(tree.name, term);
      report(
        'search "$term"',
        '${found.people.length} result(s)'
            '${found.hasMore ? ' (more available)' : ''}',
        ok: found.people.isNotEmpty,
      );

      // Prefer the account's own record: it is certain to be visible to this
      // user, which a search hit is not.
      final xref =
          tree.myXref ??
          (found.people.isEmpty ? null : found.people.first.xref);
      if (xref == null) {
        stdout.writeln('  SKIP  nobody to open');
      } else {
        final person = await records.individual(tree.name, xref);
        report('opened', '$xref — ${person.name}');
        report('alternate name', person.alternateName ?? '(none)');

        // A person with no facts is valid data, not a parser failure — this
        // tree has plenty. So an empty record is reported, and the parser is
        // then exercised against someone who does have facts.
        final secondary = person.facts.length - person.primaryFacts.length;
        report(
          'facts',
          '${person.primaryFacts.length} primary, $secondary secondary',
        );
        report(
          'families',
          'parents=${person.parents.length} '
              'siblings=${person.siblings.length} '
              'spouses=${person.spouses.length} '
              'children=${person.children.length}',
          ok: person.families.isNotEmpty,
        );
        for (final warning in person.warnings) {
          stdout.writeln('  WARN  $warning');
        }

        // Facts, and therefore dates, are what the calendar choice acts on —
        // so if this record has none, find someone who does rather than
        // reporting a skip that proves nothing.
        var dateSource = person;
        if (person.facts.isEmpty) {
          IndividualRecord? withFacts;
          for (final candidate in found.people.take(10)) {
            final other = await records.individual(tree.name, candidate.xref);
            if (other.facts.isNotEmpty) {
              withFacts = other;
              break;
            }
          }
          report(
            'facts parsed for someone who has them',
            withFacts == null
                ? 'no one in the first 10 results had any'
                : '${withFacts.xref} — ${withFacts.facts.length} fact(s)',
            ok: withFacts != null,
          );
          if (withFacts != null) dateSource = withFacts;
        }

        // Choosing a calendar means reading which calendar each rendered date
        // is in, and on a stock site the only place that is stated is the
        // `cal` parameter of the calendar links webtrees wraps dates in.
        final dated = dateSource.facts
            .where((fact) => fact.date != null)
            .map((fact) => fact.date!)
            .toList();
        if (dated.isEmpty) {
          stdout.writeln('  SKIP  no dated fact on this record');
        } else {
          final named = dated
              .expand((date) => date.pieces)
              .whereType<DateValue>()
              .where((value) => value.calendar != DateCalendar.unknown);
          report(
            'dates naming their calendar',
            '${named.length} of ${dated.length} dated fact(s) — '
                '${named.map((v) => v.calendar.name).toSet().join(', ')}',
            ok: named.isNotEmpty,
          );

          final sample = dated.firstWhere(
            (date) => date.pieces.whereType<DateValue>().any(
              (value) => value.conversions.isNotEmpty,
            ),
            orElse: () => dated.first,
          );
          report('date, both calendars', sample.display(CalendarView.both));
          report(
            'date, gregorian only',
            sample.display(CalendarView.gregorian),
          );
          report('date, hijri only', sample.display(CalendarView.hijri));
        }

        final photo = person.thumbnailUrl;
        if (photo == null) {
          stdout.writeln('  SKIP  no photo on this record');
        } else {
          final bytes = await records.image(photo);
          report(
            'photo over the session',
            '${bytes.length} bytes',
            ok: bytes.isNotEmpty,
          );
        }
      }
    }

    stdout.writeln('\n=== Sign out ===');
    await session.signOut();
    report(
      'signed out',
      await session.isSignedIn() ? 'still signed in' : 'yes',
      ok: !await session.isSignedIn(),
    );
  } on WebtreesError catch (error) {
    failures++;
    stdout.writeln('\n  FAIL  ${error.runtimeType}: ${error.message}');
  } finally {
    client.close();
  }

  stdout.writeln(
    failures == 0 ? '\nAll checks passed.' : '\n$failures failed.',
  );
  exitCode = failures == 0 ? 0 : 1;
}

String _readPassword(String username) {
  final fromEnvironment = Platform.environment['WEBTREES_PASSWORD'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }

  stdout.write('Password for $username: ');
  if (!stdin.hasTerminal) return stdin.readLineSync() ?? '';

  final echoing = stdin.echoMode;
  stdin.echoMode = false;
  try {
    return stdin.readLineSync() ?? '';
  } finally {
    stdin.echoMode = echoing;
    stdout.writeln();
  }
}
