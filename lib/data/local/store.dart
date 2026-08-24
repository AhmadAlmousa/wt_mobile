/// The tree, on the device.
///
/// `sync_eval.md` argues the whole shape and two of its conclusions are the
/// reason this file looks the way it does.
///
/// **The client owns the database.** Not a `.sqlite` the server builds and the
/// app downloads: that puts a multi-megabyte build inside one PHP request on
/// somebody else's shared host, and it fails at install time, which is the
/// worst moment. So the store is filled from paged record requests, which is
/// resumable, needs no server-side state, and makes the first sync and the
/// daily delta one code path.
///
/// **A record is stored as the module sent it.** [StoredPeople.payload] holds
/// the endpoint's own JSON verbatim, and every other column is derived from it
/// for the sake of a `WHERE`. That is deliberate: the store can then never
/// disagree with the server about what a record *says*, because it is not a
/// second model of one — it is the same bytes, indexed. The same discipline as
/// `RecordComposer` on the server, where `/individual` and `/records` compose
/// from one place.
///
/// What is *not* here, and will not be: anything the app would have to compute
/// itself to answer. A relationship's wording is a large piece of webtrees
/// nobody should port twice, and statistics as the site publishes them are the
/// site's arithmetic — both stay online (`sync_eval.md` §5).
library;

import 'package:drift/drift.dart';

part 'store.g.dart';

/// One person, as the module answered them.
@DataClassName('StoredPerson')
class StoredPeople extends Table {
  /// Which tree this record belongs to, by name — the same string that
  /// addresses it on the wire.
  TextColumn get tree => text()();

  TextColumn get xref => text()();

  /// The rendered name, exactly as the site wrote it.
  TextColumn get name => text()();

  /// Both name forms, lower-cased, for a `LIKE`.
  ///
  /// A stored search is the first time this app can look at a whole tree at
  /// once, and it has to find `Abdullah` for somebody recorded as
  /// `عبد الله الموسى` with a romanized second form. Kept as a column rather
  /// than computed per query so the comparison is indexed and the same in
  /// every caller.
  TextColumn get nameFold => text()();

  /// What the site sorts by, which is not what it displays.
  ///
  /// Absent from the wire, so it is the display name for now: browsing in
  /// stored order is browsing in the order the *sync* arrived, and the sync
  /// walks xrefs. Named here because a real index wants `n_sort` and the
  /// endpoint would have to state it.
  TextColumn get sortName => text()();

  TextColumn get alternateName => text().nullable()();

  /// `male`, `female` or `unknown` — the enum's name, not a letter.
  TextColumn get sex => text()();

  BoolColumn get deceased => boolean()();

  TextColumn get lifespan => text().nullable()();

  /// Years **as the site counts them**: 1318 for a Hijri record, 1901 for a
  /// Gregorian one. Never converted, because the floor cannot convert either
  /// and two transports that disagreed about a year would be worse than one
  /// that says what it printed.
  IntColumn get birthYear => integer().nullable()();
  IntColumn get deathYear => integer().nullable()();

  /// Age in days-derived years, which is the one figure that survives a Hijri
  /// birth and a Gregorian death. Only ever stated by the module.
  IntColumn get age => integer().nullable()();

  TextColumn get birthPlace => text().nullable()();

  /// A signed thumbnail URL. Still not an authorization token: the bytes must
  /// be fetched through the session, so a stored URL is an address and not a
  /// picture (Phase 10e stores the bytes).
  TextColumn get thumbnailUrl => text().nullable()();

  /// Whether the site answered this record as private — a name and nothing
  /// else. Stored because it is what the site said, and because a store that
  /// dropped these rows would make "absent" and "hidden" the same thing.
  BoolColumn get private => boolean()();

  /// The module's own JSON for this record, verbatim.
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {tree, xref};
}

/// Who is in which family, which is what a chart is a walk over.
///
/// Derived from the `families` blocks of each stored record rather than
/// fetched: the module already states, per person, every family they belong to
/// and how. Two rows per membership are not needed — a family reached from
/// either side finds the other — so one row per (family, person) with the
/// role is enough to walk in both directions.
@DataClassName('StoredMembership')
class StoredMemberships extends Table {
  TextColumn get tree => text()();

  TextColumn get familyXref => text()();

  TextColumn get personXref => text()();

  /// `spouse` or `child`. The module states which; HTML has to guess it from
  /// the position of a marriage row, which is the ambiguity `PROJECT.md` §7
  /// bug 50 came from.
  TextColumn get role => text()();

  /// Which person's record this membership was read from.
  ///
  /// A family is stated by every member, so the same membership arrives many
  /// times and any of them is as good as another. Kept because a delta
  /// re-sends one person at a time: the rows *that person* stated are the
  /// rows that may be replaced, and everybody else's statements must survive.
  TextColumn get statedBy => text()();

  @override
  Set<Column> get primaryKey => {tree, familyXref, personXref, statedBy};
}

/// What this store is a copy of, and how far it got.
///
/// The stamp half exists because a store is **one user's view of one tree in
/// one language, frozen** (`sync_eval.md` §6). webtrees privacy is per user
/// and per record, so a store filled for a member must never be read for
/// anybody else — and every human-readable string in it was rendered in one
/// language, so a reader who switches language is owed a different store, not
/// a translated one.
///
/// The cursor half is what makes a sync resumable: eight requests are eight
/// chances to fail, and a paged design that starts again from zero is not
/// resumable, it is only short.
@DataClassName('StoredTreeState')
class StoredTreeStates extends Table {
  TextColumn get tree => text()();

  /// The fingerprint the server last stated. Opaque: stored, sent back as
  /// `since`, compared for equality, never read into.
  TextColumn get token => text().nullable()();

  /// Where a full walk got to, in rows of the server's own ordering.
  IntColumn get cursor => integer().withDefault(const Constant(0))();

  /// Whether a full walk is still in progress. A store mid-walk holds part of
  /// a tree, which is fine to add to and not fine to *read* as though it were
  /// the tree.
  BoolColumn get filling => boolean().withDefault(const Constant(true))();

  /// Which tabs this site runs, and which charts it offers, as JSON arrays.
  ///
  /// Page-level on the wire and tree-level here for the same reason: they
  /// describe the tree and the reader rather than any person, so a store keeps
  /// one copy instead of 1,463. A record read back out of the store is given
  /// these, which is what makes it identical to the one the endpoint answers.
  TextColumn get sections => text().withDefault(const Constant('[]'))();
  TextColumn get chartClasses => text().withDefault(const Constant('[]'))();

  /// When the last page was written. Shown to the reader: a figure from last
  /// night is not wrong, but a reader wondering about it has to be told.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  // --- the stamp ---------------------------------------------------------

  /// The account this copy was filled for.
  TextColumn get username => text()();

  /// Their role in this tree. A demoted member still holds what they could
  /// see yesterday; nothing can undo that, but a changed role must not be
  /// answered from the old copy.
  TextColumn get role => text()();

  /// The language every rendered string in here was written in.
  TextColumn get language => text()();

  /// Which module answered. A payload's meaning has changed without its shape
  /// changing before — three times — so a store filled by an older module is
  /// not a store this app should read.
  TextColumn get moduleVersion => text()();

  @override
  Set<Column> get primaryKey => {tree};
}

/// The database itself.
///
/// Deliberately **no Flutter here.** Saying where the file lives needs
/// `path_provider`, which needs Flutter, and a schema that dragged Flutter in
/// would be a schema no plain Dart tool could open — `tool/live_check.dart`
/// fills a real store from a real server to check the sync, and it runs on the
/// Dart VM. So the executor is handed in: the app passes the one from
/// `store_open.dart`, tests pass `NativeDatabase.memory()`.
@DriftDatabase(tables: [StoredPeople, StoredMemberships, StoredTreeStates])
class LocalStore extends _$LocalStore {
  LocalStore(super.executor);

  /// Same thing, named for what a reader of a test needs to know.
  LocalStore.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}
