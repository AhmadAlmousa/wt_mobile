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
import 'package:webtrees_mobile/data/stock/charts_repository.dart';
import 'package:webtrees_mobile/data/stock/records_repository.dart';
import 'package:webtrees_mobile/domain/charts.dart';
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

      // A common surname matches more people than one page holds. webtrees
      // pages by number, and its own `nextUrl` cannot be followed: it is built
      // without the query, so a client that trusted it would page into
      // nothing.
      if (found.hasMore) {
        final second = await records.search(tree.name, term, page: 2);
        final first = found.people.map((person) => person.xref).toSet();
        report(
          'second page',
          '${second.people.length} more'
              '${second.hasMore ? ' (and more still)' : ''}'
              ' · ${second.people.where((p) => first.contains(p.xref)).length}'
              ' already seen',
          ok: second.people.isNotEmpty,
        );
      } else {
        stdout.writeln('  SKIP  one page of results, nothing to page through');
      }

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

        // Which modules this site runs decides how much of a record the app
        // can show at all, and no two instances agree — so the check reports
        // what was on offer rather than assuming the stock set.
        report('sections offered', person.sections.join(', '));
        report(
          'notes, sources, photos',
          '${person.notes.length} note(s), '
              '${person.sources.length} citation(s), '
              '${person.media.length} media item(s)',
        );

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
        // A marriage belongs to the family rather than to either person, and
        // the relatives tab is the only place a stock site states it.
        final familyFacts = person.families
            .expand((family) => family.facts)
            .toList();
        report(
          'family facts',
          familyFacts.isEmpty
              ? 'none recorded'
              : familyFacts
                    .map((fact) => '${fact.label}: ${fact.value ?? '—'}')
                    .join(' · '),
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

        // The charts a site runs are the app's to discover, not to assume:
        // every one of them is a module an administrator can switch off.
        stdout.writeln('\n=== Charts ===');
        report(
          'charts offered',
          person.charts.keys.map((kind) => kind.name).join(', '),
          ok: person.charts.isNotEmpty,
        );

        final chartRepository = ChartsRepository(
          client,
          version: instance.version,
        );
        // Only the two charts that are actually fetched: an hourglass is
        // stitched from them, and is checked on its own below.
        for (final kind in const [ChartKind.ancestors, ChartKind.descendants]) {
          if (person.charts[kind] == null) {
            stdout.writeln(
              '  SKIP  this site does not run the ${kind.name} chart',
            );
            continue;
          }

          // A chart of one person parses perfectly and proves nothing, so
          // where the first record has no family recorded, try a few more.
          var drawn = person;
          var chart = await chartRepository.chart(
            kind,
            person.charts[kind]!,
            subject: PersonRef(xref: person.xref, name: person.name),
          );
          for (final candidate in found.people.take(8)) {
            if (chart.size > 1) break;
            final other = await records.individual(tree.name, candidate.xref);
            final url = other.charts[kind];
            if (url == null) continue;
            drawn = other;
            chart = await chartRepository.chart(
              kind,
              url,
              subject: PersonRef(xref: other.xref, name: other.name),
            );
          }

          report(
            '${kind.name} chart',
            '${drawn.xref}: ${chart.size} people, '
                '${_generationsIn(chart)} generations',
            ok: chart.size > 1,
          );
        }

        // An hourglass is not a fetch of its own: it is the two charts either
        // side of a person, stitched. Worth checking live all the same,
        // because it is the one chart whose halves have to agree about who
        // is in the middle.
        final up = person.charts[ChartKind.ancestors];
        final down = person.charts[ChartKind.descendants];
        if (up == null || down == null) {
          stdout.writeln(
            '  SKIP  this site does not run both halves of an '
            'hourglass',
          );
        } else {
          final hourglass = await chartRepository.hourglass(
            ancestorsUrl: up,
            descendantsUrl: down,
            subject: PersonRef(xref: person.xref, name: person.name),
          );
          report(
            'hourglass',
            '${hourglass.ancestors?.everyone.length ?? 0} above, '
                '${hourglass.descendants?.everyone.length ?? 0} below',
            ok:
                hourglass.ancestors?.person.xref == person.xref &&
                hourglass.descendants?.person.xref == person.xref,
          );
        }

        // How two people are related is the one thing the app cannot work out
        // for itself: it would mean walking a graph a record at a time.
        final relationshipUrl = person.charts[ChartKind.relationship];
        if (relationshipUrl == null) {
          stdout.writeln(
            '  SKIP  this site does not run the relationships '
            'chart',
          );
        } else {
          // Somebody this person is certainly related to, because the app has
          // just read the family that says so. Two people picked out of a
          // search need not be related at all, and a site that says as much
          // has answered correctly — which makes for a check that proves
          // nothing.
          // Blood first: a site can be set to search only through common
          // ancestors — this one is, with `relationships-1-3` — and under
          // that setting a spouse has no link to find, which would make a
          // check that used one prove nothing.
          final relative = [
            ...person.parents,
            ...person.children,
            ...person.siblings,
          ].firstOrNull;

          if (relative == null) {
            stdout.writeln(
              '  SKIP  no blood relative on this record to compare with',
            );
          } else {
            final paths = await chartRepository.relationship(
              relationshipUrl,
              from: person.xref,
              to: relative.xref,
            );
            report(
              'relationship to ${relative.xref}',
              paths.isEmpty
                  ? 'no link found, though the tree records one'
                  : '${paths.first.description} · '
                        '${paths.first.steps.length} step(s) · '
                        '${paths.length} path(s)',
              ok: paths.isNotEmpty,
            );
          }
        }

        // A timeline says where each event sits against a scale of years,
        // both as positions in its own drawing — the app compares the two and
        // never reads a date out of them.
        final timelineUrl = person.charts[ChartKind.timeline];
        if (timelineUrl == null) {
          stdout.writeln('  SKIP  this site does not run the timeline chart');
        } else {
          var drawn = person;
          var timeline = await chartRepository.timeline(timelineUrl);
          for (final candidate in found.people.take(8)) {
            if (!timeline.isEmpty) break;
            final other = await records.individual(tree.name, candidate.xref);
            final url = other.charts[ChartKind.timeline];
            if (url == null) continue;
            drawn = other;
            timeline = await chartRepository.timeline(url);
          }

          report(
            'timeline',
            '${drawn.xref}: ${timeline.events.length} event(s) between '
                '${timeline.ticks.isEmpty ? '?' : timeline.ticks.first.year} '
                'and '
                '${timeline.ticks.isEmpty ? '?' : timeline.ticks.last.year}',
            ok: !timeline.isEmpty,
          );
        }

        // Statistics belong to the tree rather than to anybody in it, so the
        // link to them is on the tree's own page.
        final treeCharts = await records.treeCharts(tree.name);
        final statisticsUrl = treeCharts[ChartKind.statistics];
        if (statisticsUrl == null) {
          stdout.writeln('  SKIP  this site publishes no statistics');
        } else {
          final statistics = await chartRepository.statistics(statisticsUrl);
          final sections = statistics.parts
              .expand((part) => part.sections)
              .toList();
          final datasets = sections
              .expand((section) => section.datasets)
              .toList();
          report(
            'statistics',
            '${statistics.parts.length} part(s), '
                '${sections.length} section(s), '
                '${datasets.length} chart(s) · '
                '${sections.first.title} ${sections.first.total ?? ''}',
            ok: datasets.isNotEmpty,
          );
        }

        // A signed thumbnail URL is not an access token — webtrees checks
        // this account's permission before it honours the signature — so the
        // one thing worth proving is that an image fetched through the
        // session arrives. Search rows carry a thumbnail for anybody with a
        // highlighted photo, which is the cheapest place to find one.
        final withPhotos = found.people
            .where((candidate) => candidate.thumbnailUrl != null)
            .toList();
        final photo =
            person.thumbnailUrl ?? withPhotos.firstOrNull?.thumbnailUrl;

        report(
          'people with a photo',
          '${withPhotos.length} of ${found.people.length} searched',
        );

        if (photo == null) {
          stdout.writeln('  SKIP  nobody found with a photo to fetch');
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

/// How many generations a chart turned out to hold.
int _generationsIn(ChartData chart) {
  final ancestors = chart.ancestors;
  if (ancestors != null) return ancestors.depth;

  return chart.descendants!.everyone
      .map((node) => node.depth)
      .fold(1, (deepest, depth) => depth > deepest ? depth : deepest);
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
