/// Filling the store, and keeping it filled.
///
/// One loop serves both jobs, which was the point of the wire's shape: a first
/// sync is `?offset=&limit=` from the top, a daily sync is the same request
/// with `&since=<token>`, and the only difference in this file is which of the
/// two it starts with.
///
/// **What runs where.** Fetching stays on this isolate, because the session —
/// dio, its cookie jar, the rotating webtrees cookie — lives here and is not
/// something to hand across an isolate boundary. Every SQLite statement runs on
/// drift's own background isolate (`NativeDatabase.createInBackground`, see
/// `store.dart`), which is the part that would otherwise stall the screen while
/// 1,463 records are written. A page is decoded here, which costs a few
/// milliseconds for the largest page the server will send.
///
/// **What it will not do.** Nothing here retries or backs off. A page that
/// fails throws, the cursor is already saved, and the next call resumes from
/// it — which is the whole reason the cursor is persisted per page rather than
/// per sync. `sync_eval.md` §11 #5 says eight requests are eight chances to
/// fail; this is the answer to that, and it is deliberately not a retry loop
/// that hides a server in trouble.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../domain/access.dart';
import '../module/module_decode.dart';
import 'records_page.dart';
import 'store.dart';

/// What a store is a copy *of*.
///
/// A store filled for one reader in one language must never be read for
/// anybody else. webtrees privacy is per user and per record — `canShow()`
/// depends on the reader's role, on `HIDE_LIVE_PEOPLE`, on `RESN` tags and on
/// relationship rules — and every human-readable string in the store was
/// rendered in one language by the server. So the stamp is the identity of the
/// copy, and a mismatch is not a filter, it is a different store
/// (`sync_eval.md` §6).
@immutable
final class StoreStamp {
  const StoreStamp({
    required this.tree,
    required this.username,
    required this.role,
    required this.language,
    required this.moduleVersion,
  });

  final String tree;
  final String username;

  /// The role that produced this copy. A member demoted to visitor still holds
  /// what they could see yesterday — nothing can undo that, because the data
  /// was already on the device — but the copy must not be *answered from*
  /// once the role has changed.
  final TreeRole role;

  /// The language every rendered string in the store was written in. A reader
  /// who switches language is owed a new store, not a translated one: the
  /// alternative is reimplementing labels, six calendars and the kinship
  /// tables, which is the one thing this project has never done.
  final String language;

  /// Which module answered. Three times now a payload's *meaning* has changed
  /// without its shape changing, so a store filled by an older module is not
  /// one this app should read.
  final String moduleVersion;

  bool matches(StoredTreeState state) =>
      state.username == username &&
      state.role == role.name &&
      state.language == language &&
      state.moduleVersion == moduleVersion;
}

/// Why a sync stopped, and what it did.
@immutable
final class SyncReport {
  const SyncReport({
    required this.written,
    required this.deleted,
    required this.requests,
    required this.complete,
    required this.startedFresh,
    this.token,
  });

  /// Records written. On a resumed walk this counts only this run's pages.
  final int written;

  final int deleted;
  final int requests;

  /// Whether the store now holds the whole of what the reader may see. False
  /// after a page failed, or after [TreeSync.run]'s page budget ran out.
  final bool complete;

  /// Whether this run threw the previous copy away — a changed stamp, or the
  /// server refusing the stored fingerprint.
  final bool startedFresh;

  final String? token;

  @override
  String toString() =>
      'SyncReport(written: $written, deleted: $deleted, '
      'requests: $requests, complete: $complete, fresh: $startedFresh)';
}

/// Fills one tree's store from one source.
final class TreeSync {
  TreeSync({
    required this.store,
    required this.source,
    required this.stamp,
    this.pageSize = 100,
  });

  final LocalStore store;
  final SyncSource source;
  final StoreStamp stamp;

  /// Records per request. The server caps this at 200 and answers a megabyte
  /// there; 100 is half that and still walks 1,463 people in fifteen
  /// requests, which is a better trade on a phone network than the fewest
  /// possible requests.
  final int pageSize;

  static const String _log = 'webtrees.sync';

  /// Bring the store up to date, or as far as [maxRequests] allows.
  ///
  /// Safe to call again after anything at all: the cursor is saved per page,
  /// so a call that failed halfway resumes rather than restarts.
  Future<SyncReport> run({int maxRequests = 1000}) async {
    final tree = stamp.tree;
    var state = await _state(tree);
    var fresh = false;

    // A copy of somebody else's view, or of another language, or one an older
    // module wrote. Not filtered — replaced.
    if (state != null && !stamp.matches(state)) {
      developer.log('Stamp changed for $tree — dropping the store', name: _log);
      await wipe(tree);
      state = null;
      fresh = true;
    }

    state ??= await _begin(tree);

    final resuming = state.filling || state.token == null;

    final report = resuming
        ? await _walk(state, maxRequests: maxRequests)
        : await _delta(state, maxRequests: maxRequests);

    return SyncReport(
      written: report.written,
      deleted: report.deleted,
      requests: report.requests,
      complete: report.complete,
      startedFresh: fresh || report.startedFresh,
      token: report.token,
    );
  }

  /// Everything, from wherever the last run got to.
  Future<SyncReport> _walk(
    StoredTreeState state, {
    required int maxRequests,
  }) async {
    final tree = state.tree;
    var offset = state.cursor;
    var written = 0;
    var deleted = 0;
    var requests = 0;

    // Rule 1 of the wire: keep the token from the *first* page. Every page
    // states the fingerprint as it is now, so a tree edited mid-walk answers a
    // later page's token that covers changes this walk did not see. Storing
    // the first one leaves those changes above the stored token, where the next
    // delta will find them.
    var first = state.token;
    var last = state.token;

    while (requests < maxRequests) {
      final page = await source.records(tree, offset: offset, limit: pageSize);
      requests++;

      if (page.resync) {
        // A full walk sends no `since`, so this should not happen. If a server
        // ever says it anyway, the only honest reading is "your copy is not a
        // prefix of mine".
        developer.log('Asked to start again mid-walk on $tree', name: _log);
        await wipe(tree);
        final restarted = await _walk(
          await _begin(tree),
          maxRequests: maxRequests - requests,
        );
        return SyncReport(
          written: written + restarted.written,
          deleted: deleted + restarted.deleted,
          requests: requests + restarted.requests,
          complete: restarted.complete,
          startedFresh: true,
          token: restarted.token,
        );
      }

      first ??= page.token;
      last = page.token;

      await _apply(tree, page);
      written += page.people.length;
      deleted += page.deleted.length;

      // Rule 2: advance by the limit asked for, never by the number of
      // records received. Privacy is applied after a page of rows is taken,
      // so a short page is not the last page — `hasMore` is.
      offset += pageSize;

      await _saveProgress(
        tree,
        cursor: offset,
        token: first,
        filling: page.hasMore,
        page: page,
      );

      if (!page.hasMore) {
        // The tree changed while it was being read. The store is a complete
        // copy of *something*, and one delta from the first fingerprint makes
        // it a complete copy of now.
        if (last != first) {
          developer.log(
            '$tree changed during the walk — running a delta',
            name: _log,
          );
          final caught = await _delta(
            (await _state(tree))!,
            maxRequests: maxRequests - requests,
          );
          return SyncReport(
            written: written + caught.written,
            deleted: deleted + caught.deleted,
            requests: requests + caught.requests,
            complete: caught.complete,
            startedFresh: false,
            token: caught.token,
          );
        }

        return SyncReport(
          written: written,
          deleted: deleted,
          requests: requests,
          complete: true,
          startedFresh: false,
          token: first,
        );
      }
    }

    return SyncReport(
      written: written,
      deleted: deleted,
      requests: requests,
      complete: false,
      startedFresh: false,
      token: first,
    );
  }

  /// Only what changed since the stored fingerprint.
  Future<SyncReport> _delta(
    StoredTreeState state, {
    required int maxRequests,
  }) async {
    final tree = state.tree;
    final since = state.token;

    if (since == null) {
      return _walk(state, maxRequests: maxRequests);
    }

    var offset = 0;
    var written = 0;
    var deleted = 0;
    var requests = 0;
    String? first;

    while (requests < maxRequests) {
      final page = await source.records(
        tree,
        offset: offset,
        limit: pageSize,
        since: since,
      );
      requests++;

      if (page.resync) {
        developer.log(
          '$tree cannot describe a path from $since — '
          'starting again',
          name: _log,
        );
        await wipe(tree);
        final again = await _walk(
          await _begin(tree),
          maxRequests: maxRequests - requests,
        );
        return SyncReport(
          written: written + again.written,
          deleted: deleted + again.deleted,
          requests: requests + again.requests,
          complete: again.complete,
          startedFresh: true,
          token: again.token,
        );
      }

      first ??= page.token;

      await _apply(tree, page);
      written += page.people.length;
      deleted += page.deleted.length;
      offset += pageSize;

      if (!page.hasMore) {
        // The first page's fingerprint again, for the same reason as the walk:
        // anything that changed while the delta was being read stays above it.
        await _saveProgress(
          tree,
          cursor: 0,
          token: first,
          filling: false,
          page: page,
        );

        return SyncReport(
          written: written,
          deleted: deleted,
          requests: requests,
          complete: true,
          startedFresh: false,
          token: first,
        );
      }
    }

    // Out of budget mid-delta. Deliberately *not* saving the new fingerprint:
    // a token stored now would claim changes this run has not applied.
    return SyncReport(
      written: written,
      deleted: deleted,
      requests: requests,
      complete: false,
      startedFresh: false,
      token: since,
    );
  }

  /// Write one page: the records it carries, and the ones it says are gone.
  Future<void> _apply(String tree, RecordsPage page) async {
    await store.transaction(() async {
      for (final person in page.people) {
        final xref = stringOf(person['xref']);
        if (xref == null) continue;

        final reference = personFrom(person);

        await store
            .into(store.storedPeople)
            .insertOnConflictUpdate(
              StoredPeopleCompanion.insert(
                tree: tree,
                xref: xref,
                name: reference.name,
                nameFold: _fold(reference.name, reference.alternateName),
                sortName: reference.name,
                alternateName: Value(reference.alternateName),
                sex: reference.sex.name,
                deceased: reference.isDeceased,
                lifespan: Value(reference.lifespan),
                birthYear: Value(reference.birthYear),
                deathYear: Value(reference.deathYear),
                age: Value(reference.age),
                birthPlace: Value(reference.birthPlace),
                thumbnailUrl: Value(reference.thumbnailUrl),
                private: person['private'] == true,
                payload: payloadOf(person),
              ),
            );

        // This person's statement about who is in which family, replacing
        // whatever they said last time and leaving everybody else's statements
        // alone.
        await (store.delete(store.storedMemberships)..where(
              (row) => row.tree.equals(tree) & row.statedBy.equals(xref),
            ))
            .go();

        for (final family in listOf(person['families'])) {
          if (family is! Map<String, Object?>) continue;
          final familyXref = stringOf(family['xref']);
          if (familyXref == null) continue;

          for (final entry in const [
            ('spouses', 'spouse'),
            ('children', 'child'),
          ]) {
            for (final member in listOf(family[entry.$1])) {
              if (member is! Map<String, Object?>) continue;
              final memberXref = stringOf(member['xref']);
              if (memberXref == null) continue;

              await store
                  .into(store.storedMemberships)
                  .insertOnConflictUpdate(
                    StoredMembershipsCompanion.insert(
                      tree: tree,
                      familyXref: familyXref,
                      personXref: memberXref,
                      role: entry.$2,
                      statedBy: xref,
                    ),
                  );
            }
          }
        }
      }

      for (final xref in page.deleted) {
        await (store.delete(
          store.storedPeople,
        )..where((row) => row.tree.equals(tree) & row.xref.equals(xref))).go();
        await (store.delete(store.storedMemberships)..where(
              (row) => row.tree.equals(tree) & row.statedBy.equals(xref),
            ))
            .go();
      }
    });
  }

  Future<void> _saveProgress(
    String tree, {
    required int cursor,
    required String? token,
    required bool filling,
    required RecordsPage page,
  }) =>
      (store.update(
        store.storedTreeStates,
      )..where((row) => row.tree.equals(tree))).write(
        StoredTreeStatesCompanion(
          cursor: Value(cursor),
          token: Value(token),
          filling: Value(filling),
          syncedAt: Value(DateTime.now()),
          // Only ever from a page that actually stated them: a delta with
          // nothing in it still states the tree's sections, but a server that
          // sent none should not be allowed to erase what is known.
          sections: page.sections.isEmpty
              ? const Value<String>.absent()
              : Value(jsonEncode(page.sections)),
          chartClasses: page.chartClasses.isEmpty
              ? const Value<String>.absent()
              : Value(jsonEncode(page.chartClasses)),
        ),
      );

  Future<StoredTreeState?> _state(String tree) => (store.select(
    store.storedTreeStates,
  )..where((row) => row.tree.equals(tree))).getSingleOrNull();

  Future<StoredTreeState> _begin(String tree) async {
    await store
        .into(store.storedTreeStates)
        .insertOnConflictUpdate(
          StoredTreeStatesCompanion.insert(
            tree: tree,
            token: const Value(null),
            cursor: const Value(0),
            filling: const Value(true),
            syncedAt: const Value(null),
            sections: const Value('[]'),
            chartClasses: const Value('[]'),
            username: stamp.username,
            role: stamp.role.name,
            language: stamp.language,
            moduleVersion: stamp.moduleVersion,
          ),
        );

    return (await _state(tree))!;
  }

  /// Throw this tree's copy away.
  ///
  /// Called on a changed stamp, on a fingerprint the server refuses — and, by
  /// the app, on sign-out. `sync_eval.md` §6 #2: the store makes yesterday's
  /// permissions durable, so the answer is to not keep them.
  Future<void> wipe(String tree) => store.transaction(() async {
    await (store.delete(
      store.storedPeople,
    )..where((row) => row.tree.equals(tree))).go();
    await (store.delete(
      store.storedMemberships,
    )..where((row) => row.tree.equals(tree))).go();
    await (store.delete(
      store.storedTreeStates,
    )..where((row) => row.tree.equals(tree))).go();
  });

  /// Both name forms, lower-cased, which is what a stored search compares.
  static String _fold(String name, String? alternate) =>
      alternate == null || alternate.isEmpty
      ? name.toLowerCase()
      : '${name.toLowerCase()}\n${alternate.toLowerCase()}';
}
