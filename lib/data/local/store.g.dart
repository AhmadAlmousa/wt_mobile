// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store.dart';

// ignore_for_file: type=lint
class $StoredPeopleTable extends StoredPeople
    with TableInfo<$StoredPeopleTable, StoredPerson> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredPeopleTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _treeMeta = const VerificationMeta('tree');
  @override
  late final GeneratedColumn<String> tree = GeneratedColumn<String>(
    'tree',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xrefMeta = const VerificationMeta('xref');
  @override
  late final GeneratedColumn<String> xref = GeneratedColumn<String>(
    'xref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameFoldMeta = const VerificationMeta(
    'nameFold',
  );
  @override
  late final GeneratedColumn<String> nameFold = GeneratedColumn<String>(
    'name_fold',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortNameMeta = const VerificationMeta(
    'sortName',
  );
  @override
  late final GeneratedColumn<String> sortName = GeneratedColumn<String>(
    'sort_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _alternateNameMeta = const VerificationMeta(
    'alternateName',
  );
  @override
  late final GeneratedColumn<String> alternateName = GeneratedColumn<String>(
    'alternate_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sexMeta = const VerificationMeta('sex');
  @override
  late final GeneratedColumn<String> sex = GeneratedColumn<String>(
    'sex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deceasedMeta = const VerificationMeta(
    'deceased',
  );
  @override
  late final GeneratedColumn<bool> deceased = GeneratedColumn<bool>(
    'deceased',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deceased" IN (0, 1))',
    ),
  );
  static const VerificationMeta _lifespanMeta = const VerificationMeta(
    'lifespan',
  );
  @override
  late final GeneratedColumn<String> lifespan = GeneratedColumn<String>(
    'lifespan',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthYearMeta = const VerificationMeta(
    'birthYear',
  );
  @override
  late final GeneratedColumn<int> birthYear = GeneratedColumn<int>(
    'birth_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deathYearMeta = const VerificationMeta(
    'deathYear',
  );
  @override
  late final GeneratedColumn<int> deathYear = GeneratedColumn<int>(
    'death_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ageMeta = const VerificationMeta('age');
  @override
  late final GeneratedColumn<int> age = GeneratedColumn<int>(
    'age',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthPlaceMeta = const VerificationMeta(
    'birthPlace',
  );
  @override
  late final GeneratedColumn<String> birthPlace = GeneratedColumn<String>(
    'birth_place',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailUrlMeta = const VerificationMeta(
    'thumbnailUrl',
  );
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
    'thumbnail_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _privateMeta = const VerificationMeta(
    'private',
  );
  @override
  late final GeneratedColumn<bool> private = GeneratedColumn<bool>(
    'private',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("private" IN (0, 1))',
    ),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tree,
    xref,
    name,
    nameFold,
    sortName,
    alternateName,
    sex,
    deceased,
    lifespan,
    birthYear,
    deathYear,
    age,
    birthPlace,
    thumbnailUrl,
    private,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_people';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredPerson> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tree')) {
      context.handle(
        _treeMeta,
        tree.isAcceptableOrUnknown(data['tree']!, _treeMeta),
      );
    } else if (isInserting) {
      context.missing(_treeMeta);
    }
    if (data.containsKey('xref')) {
      context.handle(
        _xrefMeta,
        xref.isAcceptableOrUnknown(data['xref']!, _xrefMeta),
      );
    } else if (isInserting) {
      context.missing(_xrefMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_fold')) {
      context.handle(
        _nameFoldMeta,
        nameFold.isAcceptableOrUnknown(data['name_fold']!, _nameFoldMeta),
      );
    } else if (isInserting) {
      context.missing(_nameFoldMeta);
    }
    if (data.containsKey('sort_name')) {
      context.handle(
        _sortNameMeta,
        sortName.isAcceptableOrUnknown(data['sort_name']!, _sortNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sortNameMeta);
    }
    if (data.containsKey('alternate_name')) {
      context.handle(
        _alternateNameMeta,
        alternateName.isAcceptableOrUnknown(
          data['alternate_name']!,
          _alternateNameMeta,
        ),
      );
    }
    if (data.containsKey('sex')) {
      context.handle(
        _sexMeta,
        sex.isAcceptableOrUnknown(data['sex']!, _sexMeta),
      );
    } else if (isInserting) {
      context.missing(_sexMeta);
    }
    if (data.containsKey('deceased')) {
      context.handle(
        _deceasedMeta,
        deceased.isAcceptableOrUnknown(data['deceased']!, _deceasedMeta),
      );
    } else if (isInserting) {
      context.missing(_deceasedMeta);
    }
    if (data.containsKey('lifespan')) {
      context.handle(
        _lifespanMeta,
        lifespan.isAcceptableOrUnknown(data['lifespan']!, _lifespanMeta),
      );
    }
    if (data.containsKey('birth_year')) {
      context.handle(
        _birthYearMeta,
        birthYear.isAcceptableOrUnknown(data['birth_year']!, _birthYearMeta),
      );
    }
    if (data.containsKey('death_year')) {
      context.handle(
        _deathYearMeta,
        deathYear.isAcceptableOrUnknown(data['death_year']!, _deathYearMeta),
      );
    }
    if (data.containsKey('age')) {
      context.handle(
        _ageMeta,
        age.isAcceptableOrUnknown(data['age']!, _ageMeta),
      );
    }
    if (data.containsKey('birth_place')) {
      context.handle(
        _birthPlaceMeta,
        birthPlace.isAcceptableOrUnknown(data['birth_place']!, _birthPlaceMeta),
      );
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
        _thumbnailUrlMeta,
        thumbnailUrl.isAcceptableOrUnknown(
          data['thumbnail_url']!,
          _thumbnailUrlMeta,
        ),
      );
    }
    if (data.containsKey('private')) {
      context.handle(
        _privateMeta,
        private.isAcceptableOrUnknown(data['private']!, _privateMeta),
      );
    } else if (isInserting) {
      context.missing(_privateMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tree, xref};
  @override
  StoredPerson map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredPerson(
      tree: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree'],
      )!,
      xref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xref'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_fold'],
      )!,
      sortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_name'],
      )!,
      alternateName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alternate_name'],
      ),
      sex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sex'],
      )!,
      deceased: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deceased'],
      )!,
      lifespan: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifespan'],
      ),
      birthYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}birth_year'],
      ),
      deathYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}death_year'],
      ),
      age: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}age'],
      ),
      birthPlace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}birth_place'],
      ),
      thumbnailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_url'],
      ),
      private: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}private'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $StoredPeopleTable createAlias(String alias) {
    return $StoredPeopleTable(attachedDatabase, alias);
  }
}

class StoredPerson extends DataClass implements Insertable<StoredPerson> {
  /// Which tree this record belongs to, by name — the same string that
  /// addresses it on the wire.
  final String tree;
  final String xref;

  /// The rendered name, exactly as the site wrote it.
  final String name;

  /// Both name forms, lower-cased, for a `LIKE`.
  ///
  /// A stored search is the first time this app can look at a whole tree at
  /// once, and it has to find `Abdullah` for somebody recorded as
  /// `عبد الله الموسى` with a romanized second form. Kept as a column rather
  /// than computed per query so the comparison is indexed and the same in
  /// every caller.
  final String nameFold;

  /// What the site sorts by, which is not what it displays.
  ///
  /// Absent from the wire, so it is the display name for now: browsing in
  /// stored order is browsing in the order the *sync* arrived, and the sync
  /// walks xrefs. Named here because a real index wants `n_sort` and the
  /// endpoint would have to state it.
  final String sortName;
  final String? alternateName;

  /// `male`, `female` or `unknown` — the enum's name, not a letter.
  final String sex;
  final bool deceased;
  final String? lifespan;

  /// Years **as the site counts them**: 1318 for a Hijri record, 1901 for a
  /// Gregorian one. Never converted, because the floor cannot convert either
  /// and two transports that disagreed about a year would be worse than one
  /// that says what it printed.
  final int? birthYear;
  final int? deathYear;

  /// Age in days-derived years, which is the one figure that survives a Hijri
  /// birth and a Gregorian death. Only ever stated by the module.
  final int? age;
  final String? birthPlace;

  /// A signed thumbnail URL. Still not an authorization token: the bytes must
  /// be fetched through the session, so a stored URL is an address and not a
  /// picture (Phase 10e stores the bytes).
  final String? thumbnailUrl;

  /// Whether the site answered this record as private — a name and nothing
  /// else. Stored because it is what the site said, and because a store that
  /// dropped these rows would make "absent" and "hidden" the same thing.
  final bool private;

  /// The module's own JSON for this record, verbatim.
  final String payload;
  const StoredPerson({
    required this.tree,
    required this.xref,
    required this.name,
    required this.nameFold,
    required this.sortName,
    this.alternateName,
    required this.sex,
    required this.deceased,
    this.lifespan,
    this.birthYear,
    this.deathYear,
    this.age,
    this.birthPlace,
    this.thumbnailUrl,
    required this.private,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tree'] = Variable<String>(tree);
    map['xref'] = Variable<String>(xref);
    map['name'] = Variable<String>(name);
    map['name_fold'] = Variable<String>(nameFold);
    map['sort_name'] = Variable<String>(sortName);
    if (!nullToAbsent || alternateName != null) {
      map['alternate_name'] = Variable<String>(alternateName);
    }
    map['sex'] = Variable<String>(sex);
    map['deceased'] = Variable<bool>(deceased);
    if (!nullToAbsent || lifespan != null) {
      map['lifespan'] = Variable<String>(lifespan);
    }
    if (!nullToAbsent || birthYear != null) {
      map['birth_year'] = Variable<int>(birthYear);
    }
    if (!nullToAbsent || deathYear != null) {
      map['death_year'] = Variable<int>(deathYear);
    }
    if (!nullToAbsent || age != null) {
      map['age'] = Variable<int>(age);
    }
    if (!nullToAbsent || birthPlace != null) {
      map['birth_place'] = Variable<String>(birthPlace);
    }
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['private'] = Variable<bool>(private);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  StoredPeopleCompanion toCompanion(bool nullToAbsent) {
    return StoredPeopleCompanion(
      tree: Value(tree),
      xref: Value(xref),
      name: Value(name),
      nameFold: Value(nameFold),
      sortName: Value(sortName),
      alternateName: alternateName == null && nullToAbsent
          ? const Value.absent()
          : Value(alternateName),
      sex: Value(sex),
      deceased: Value(deceased),
      lifespan: lifespan == null && nullToAbsent
          ? const Value.absent()
          : Value(lifespan),
      birthYear: birthYear == null && nullToAbsent
          ? const Value.absent()
          : Value(birthYear),
      deathYear: deathYear == null && nullToAbsent
          ? const Value.absent()
          : Value(deathYear),
      age: age == null && nullToAbsent ? const Value.absent() : Value(age),
      birthPlace: birthPlace == null && nullToAbsent
          ? const Value.absent()
          : Value(birthPlace),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      private: Value(private),
      payload: Value(payload),
    );
  }

  factory StoredPerson.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredPerson(
      tree: serializer.fromJson<String>(json['tree']),
      xref: serializer.fromJson<String>(json['xref']),
      name: serializer.fromJson<String>(json['name']),
      nameFold: serializer.fromJson<String>(json['nameFold']),
      sortName: serializer.fromJson<String>(json['sortName']),
      alternateName: serializer.fromJson<String?>(json['alternateName']),
      sex: serializer.fromJson<String>(json['sex']),
      deceased: serializer.fromJson<bool>(json['deceased']),
      lifespan: serializer.fromJson<String?>(json['lifespan']),
      birthYear: serializer.fromJson<int?>(json['birthYear']),
      deathYear: serializer.fromJson<int?>(json['deathYear']),
      age: serializer.fromJson<int?>(json['age']),
      birthPlace: serializer.fromJson<String?>(json['birthPlace']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      private: serializer.fromJson<bool>(json['private']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tree': serializer.toJson<String>(tree),
      'xref': serializer.toJson<String>(xref),
      'name': serializer.toJson<String>(name),
      'nameFold': serializer.toJson<String>(nameFold),
      'sortName': serializer.toJson<String>(sortName),
      'alternateName': serializer.toJson<String?>(alternateName),
      'sex': serializer.toJson<String>(sex),
      'deceased': serializer.toJson<bool>(deceased),
      'lifespan': serializer.toJson<String?>(lifespan),
      'birthYear': serializer.toJson<int?>(birthYear),
      'deathYear': serializer.toJson<int?>(deathYear),
      'age': serializer.toJson<int?>(age),
      'birthPlace': serializer.toJson<String?>(birthPlace),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'private': serializer.toJson<bool>(private),
      'payload': serializer.toJson<String>(payload),
    };
  }

  StoredPerson copyWith({
    String? tree,
    String? xref,
    String? name,
    String? nameFold,
    String? sortName,
    Value<String?> alternateName = const Value.absent(),
    String? sex,
    bool? deceased,
    Value<String?> lifespan = const Value.absent(),
    Value<int?> birthYear = const Value.absent(),
    Value<int?> deathYear = const Value.absent(),
    Value<int?> age = const Value.absent(),
    Value<String?> birthPlace = const Value.absent(),
    Value<String?> thumbnailUrl = const Value.absent(),
    bool? private,
    String? payload,
  }) => StoredPerson(
    tree: tree ?? this.tree,
    xref: xref ?? this.xref,
    name: name ?? this.name,
    nameFold: nameFold ?? this.nameFold,
    sortName: sortName ?? this.sortName,
    alternateName: alternateName.present
        ? alternateName.value
        : this.alternateName,
    sex: sex ?? this.sex,
    deceased: deceased ?? this.deceased,
    lifespan: lifespan.present ? lifespan.value : this.lifespan,
    birthYear: birthYear.present ? birthYear.value : this.birthYear,
    deathYear: deathYear.present ? deathYear.value : this.deathYear,
    age: age.present ? age.value : this.age,
    birthPlace: birthPlace.present ? birthPlace.value : this.birthPlace,
    thumbnailUrl: thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
    private: private ?? this.private,
    payload: payload ?? this.payload,
  );
  StoredPerson copyWithCompanion(StoredPeopleCompanion data) {
    return StoredPerson(
      tree: data.tree.present ? data.tree.value : this.tree,
      xref: data.xref.present ? data.xref.value : this.xref,
      name: data.name.present ? data.name.value : this.name,
      nameFold: data.nameFold.present ? data.nameFold.value : this.nameFold,
      sortName: data.sortName.present ? data.sortName.value : this.sortName,
      alternateName: data.alternateName.present
          ? data.alternateName.value
          : this.alternateName,
      sex: data.sex.present ? data.sex.value : this.sex,
      deceased: data.deceased.present ? data.deceased.value : this.deceased,
      lifespan: data.lifespan.present ? data.lifespan.value : this.lifespan,
      birthYear: data.birthYear.present ? data.birthYear.value : this.birthYear,
      deathYear: data.deathYear.present ? data.deathYear.value : this.deathYear,
      age: data.age.present ? data.age.value : this.age,
      birthPlace: data.birthPlace.present
          ? data.birthPlace.value
          : this.birthPlace,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      private: data.private.present ? data.private.value : this.private,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredPerson(')
          ..write('tree: $tree, ')
          ..write('xref: $xref, ')
          ..write('name: $name, ')
          ..write('nameFold: $nameFold, ')
          ..write('sortName: $sortName, ')
          ..write('alternateName: $alternateName, ')
          ..write('sex: $sex, ')
          ..write('deceased: $deceased, ')
          ..write('lifespan: $lifespan, ')
          ..write('birthYear: $birthYear, ')
          ..write('deathYear: $deathYear, ')
          ..write('age: $age, ')
          ..write('birthPlace: $birthPlace, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('private: $private, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tree,
    xref,
    name,
    nameFold,
    sortName,
    alternateName,
    sex,
    deceased,
    lifespan,
    birthYear,
    deathYear,
    age,
    birthPlace,
    thumbnailUrl,
    private,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredPerson &&
          other.tree == this.tree &&
          other.xref == this.xref &&
          other.name == this.name &&
          other.nameFold == this.nameFold &&
          other.sortName == this.sortName &&
          other.alternateName == this.alternateName &&
          other.sex == this.sex &&
          other.deceased == this.deceased &&
          other.lifespan == this.lifespan &&
          other.birthYear == this.birthYear &&
          other.deathYear == this.deathYear &&
          other.age == this.age &&
          other.birthPlace == this.birthPlace &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.private == this.private &&
          other.payload == this.payload);
}

class StoredPeopleCompanion extends UpdateCompanion<StoredPerson> {
  final Value<String> tree;
  final Value<String> xref;
  final Value<String> name;
  final Value<String> nameFold;
  final Value<String> sortName;
  final Value<String?> alternateName;
  final Value<String> sex;
  final Value<bool> deceased;
  final Value<String?> lifespan;
  final Value<int?> birthYear;
  final Value<int?> deathYear;
  final Value<int?> age;
  final Value<String?> birthPlace;
  final Value<String?> thumbnailUrl;
  final Value<bool> private;
  final Value<String> payload;
  final Value<int> rowid;
  const StoredPeopleCompanion({
    this.tree = const Value.absent(),
    this.xref = const Value.absent(),
    this.name = const Value.absent(),
    this.nameFold = const Value.absent(),
    this.sortName = const Value.absent(),
    this.alternateName = const Value.absent(),
    this.sex = const Value.absent(),
    this.deceased = const Value.absent(),
    this.lifespan = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.deathYear = const Value.absent(),
    this.age = const Value.absent(),
    this.birthPlace = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.private = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredPeopleCompanion.insert({
    required String tree,
    required String xref,
    required String name,
    required String nameFold,
    required String sortName,
    this.alternateName = const Value.absent(),
    required String sex,
    required bool deceased,
    this.lifespan = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.deathYear = const Value.absent(),
    this.age = const Value.absent(),
    this.birthPlace = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    required bool private,
    required String payload,
    this.rowid = const Value.absent(),
  }) : tree = Value(tree),
       xref = Value(xref),
       name = Value(name),
       nameFold = Value(nameFold),
       sortName = Value(sortName),
       sex = Value(sex),
       deceased = Value(deceased),
       private = Value(private),
       payload = Value(payload);
  static Insertable<StoredPerson> custom({
    Expression<String>? tree,
    Expression<String>? xref,
    Expression<String>? name,
    Expression<String>? nameFold,
    Expression<String>? sortName,
    Expression<String>? alternateName,
    Expression<String>? sex,
    Expression<bool>? deceased,
    Expression<String>? lifespan,
    Expression<int>? birthYear,
    Expression<int>? deathYear,
    Expression<int>? age,
    Expression<String>? birthPlace,
    Expression<String>? thumbnailUrl,
    Expression<bool>? private,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tree != null) 'tree': tree,
      if (xref != null) 'xref': xref,
      if (name != null) 'name': name,
      if (nameFold != null) 'name_fold': nameFold,
      if (sortName != null) 'sort_name': sortName,
      if (alternateName != null) 'alternate_name': alternateName,
      if (sex != null) 'sex': sex,
      if (deceased != null) 'deceased': deceased,
      if (lifespan != null) 'lifespan': lifespan,
      if (birthYear != null) 'birth_year': birthYear,
      if (deathYear != null) 'death_year': deathYear,
      if (age != null) 'age': age,
      if (birthPlace != null) 'birth_place': birthPlace,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (private != null) 'private': private,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredPeopleCompanion copyWith({
    Value<String>? tree,
    Value<String>? xref,
    Value<String>? name,
    Value<String>? nameFold,
    Value<String>? sortName,
    Value<String?>? alternateName,
    Value<String>? sex,
    Value<bool>? deceased,
    Value<String?>? lifespan,
    Value<int?>? birthYear,
    Value<int?>? deathYear,
    Value<int?>? age,
    Value<String?>? birthPlace,
    Value<String?>? thumbnailUrl,
    Value<bool>? private,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return StoredPeopleCompanion(
      tree: tree ?? this.tree,
      xref: xref ?? this.xref,
      name: name ?? this.name,
      nameFold: nameFold ?? this.nameFold,
      sortName: sortName ?? this.sortName,
      alternateName: alternateName ?? this.alternateName,
      sex: sex ?? this.sex,
      deceased: deceased ?? this.deceased,
      lifespan: lifespan ?? this.lifespan,
      birthYear: birthYear ?? this.birthYear,
      deathYear: deathYear ?? this.deathYear,
      age: age ?? this.age,
      birthPlace: birthPlace ?? this.birthPlace,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      private: private ?? this.private,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tree.present) {
      map['tree'] = Variable<String>(tree.value);
    }
    if (xref.present) {
      map['xref'] = Variable<String>(xref.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameFold.present) {
      map['name_fold'] = Variable<String>(nameFold.value);
    }
    if (sortName.present) {
      map['sort_name'] = Variable<String>(sortName.value);
    }
    if (alternateName.present) {
      map['alternate_name'] = Variable<String>(alternateName.value);
    }
    if (sex.present) {
      map['sex'] = Variable<String>(sex.value);
    }
    if (deceased.present) {
      map['deceased'] = Variable<bool>(deceased.value);
    }
    if (lifespan.present) {
      map['lifespan'] = Variable<String>(lifespan.value);
    }
    if (birthYear.present) {
      map['birth_year'] = Variable<int>(birthYear.value);
    }
    if (deathYear.present) {
      map['death_year'] = Variable<int>(deathYear.value);
    }
    if (age.present) {
      map['age'] = Variable<int>(age.value);
    }
    if (birthPlace.present) {
      map['birth_place'] = Variable<String>(birthPlace.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (private.present) {
      map['private'] = Variable<bool>(private.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredPeopleCompanion(')
          ..write('tree: $tree, ')
          ..write('xref: $xref, ')
          ..write('name: $name, ')
          ..write('nameFold: $nameFold, ')
          ..write('sortName: $sortName, ')
          ..write('alternateName: $alternateName, ')
          ..write('sex: $sex, ')
          ..write('deceased: $deceased, ')
          ..write('lifespan: $lifespan, ')
          ..write('birthYear: $birthYear, ')
          ..write('deathYear: $deathYear, ')
          ..write('age: $age, ')
          ..write('birthPlace: $birthPlace, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('private: $private, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredMembershipsTable extends StoredMemberships
    with TableInfo<$StoredMembershipsTable, StoredMembership> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredMembershipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _treeMeta = const VerificationMeta('tree');
  @override
  late final GeneratedColumn<String> tree = GeneratedColumn<String>(
    'tree',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _familyXrefMeta = const VerificationMeta(
    'familyXref',
  );
  @override
  late final GeneratedColumn<String> familyXref = GeneratedColumn<String>(
    'family_xref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personXrefMeta = const VerificationMeta(
    'personXref',
  );
  @override
  late final GeneratedColumn<String> personXref = GeneratedColumn<String>(
    'person_xref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statedByMeta = const VerificationMeta(
    'statedBy',
  );
  @override
  late final GeneratedColumn<String> statedBy = GeneratedColumn<String>(
    'stated_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tree,
    familyXref,
    personXref,
    role,
    statedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_memberships';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredMembership> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tree')) {
      context.handle(
        _treeMeta,
        tree.isAcceptableOrUnknown(data['tree']!, _treeMeta),
      );
    } else if (isInserting) {
      context.missing(_treeMeta);
    }
    if (data.containsKey('family_xref')) {
      context.handle(
        _familyXrefMeta,
        familyXref.isAcceptableOrUnknown(data['family_xref']!, _familyXrefMeta),
      );
    } else if (isInserting) {
      context.missing(_familyXrefMeta);
    }
    if (data.containsKey('person_xref')) {
      context.handle(
        _personXrefMeta,
        personXref.isAcceptableOrUnknown(data['person_xref']!, _personXrefMeta),
      );
    } else if (isInserting) {
      context.missing(_personXrefMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('stated_by')) {
      context.handle(
        _statedByMeta,
        statedBy.isAcceptableOrUnknown(data['stated_by']!, _statedByMeta),
      );
    } else if (isInserting) {
      context.missing(_statedByMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    tree,
    familyXref,
    personXref,
    statedBy,
  };
  @override
  StoredMembership map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMembership(
      tree: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree'],
      )!,
      familyXref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}family_xref'],
      )!,
      personXref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_xref'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      statedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stated_by'],
      )!,
    );
  }

  @override
  $StoredMembershipsTable createAlias(String alias) {
    return $StoredMembershipsTable(attachedDatabase, alias);
  }
}

class StoredMembership extends DataClass
    implements Insertable<StoredMembership> {
  final String tree;
  final String familyXref;
  final String personXref;

  /// `spouse` or `child`. The module states which; HTML has to guess it from
  /// the position of a marriage row, which is the ambiguity `PROJECT.md` §7
  /// bug 50 came from.
  final String role;

  /// Which person's record this membership was read from.
  ///
  /// A family is stated by every member, so the same membership arrives many
  /// times and any of them is as good as another. Kept because a delta
  /// re-sends one person at a time: the rows *that person* stated are the
  /// rows that may be replaced, and everybody else's statements must survive.
  final String statedBy;
  const StoredMembership({
    required this.tree,
    required this.familyXref,
    required this.personXref,
    required this.role,
    required this.statedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tree'] = Variable<String>(tree);
    map['family_xref'] = Variable<String>(familyXref);
    map['person_xref'] = Variable<String>(personXref);
    map['role'] = Variable<String>(role);
    map['stated_by'] = Variable<String>(statedBy);
    return map;
  }

  StoredMembershipsCompanion toCompanion(bool nullToAbsent) {
    return StoredMembershipsCompanion(
      tree: Value(tree),
      familyXref: Value(familyXref),
      personXref: Value(personXref),
      role: Value(role),
      statedBy: Value(statedBy),
    );
  }

  factory StoredMembership.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMembership(
      tree: serializer.fromJson<String>(json['tree']),
      familyXref: serializer.fromJson<String>(json['familyXref']),
      personXref: serializer.fromJson<String>(json['personXref']),
      role: serializer.fromJson<String>(json['role']),
      statedBy: serializer.fromJson<String>(json['statedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tree': serializer.toJson<String>(tree),
      'familyXref': serializer.toJson<String>(familyXref),
      'personXref': serializer.toJson<String>(personXref),
      'role': serializer.toJson<String>(role),
      'statedBy': serializer.toJson<String>(statedBy),
    };
  }

  StoredMembership copyWith({
    String? tree,
    String? familyXref,
    String? personXref,
    String? role,
    String? statedBy,
  }) => StoredMembership(
    tree: tree ?? this.tree,
    familyXref: familyXref ?? this.familyXref,
    personXref: personXref ?? this.personXref,
    role: role ?? this.role,
    statedBy: statedBy ?? this.statedBy,
  );
  StoredMembership copyWithCompanion(StoredMembershipsCompanion data) {
    return StoredMembership(
      tree: data.tree.present ? data.tree.value : this.tree,
      familyXref: data.familyXref.present
          ? data.familyXref.value
          : this.familyXref,
      personXref: data.personXref.present
          ? data.personXref.value
          : this.personXref,
      role: data.role.present ? data.role.value : this.role,
      statedBy: data.statedBy.present ? data.statedBy.value : this.statedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredMembership(')
          ..write('tree: $tree, ')
          ..write('familyXref: $familyXref, ')
          ..write('personXref: $personXref, ')
          ..write('role: $role, ')
          ..write('statedBy: $statedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tree, familyXref, personXref, role, statedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredMembership &&
          other.tree == this.tree &&
          other.familyXref == this.familyXref &&
          other.personXref == this.personXref &&
          other.role == this.role &&
          other.statedBy == this.statedBy);
}

class StoredMembershipsCompanion extends UpdateCompanion<StoredMembership> {
  final Value<String> tree;
  final Value<String> familyXref;
  final Value<String> personXref;
  final Value<String> role;
  final Value<String> statedBy;
  final Value<int> rowid;
  const StoredMembershipsCompanion({
    this.tree = const Value.absent(),
    this.familyXref = const Value.absent(),
    this.personXref = const Value.absent(),
    this.role = const Value.absent(),
    this.statedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredMembershipsCompanion.insert({
    required String tree,
    required String familyXref,
    required String personXref,
    required String role,
    required String statedBy,
    this.rowid = const Value.absent(),
  }) : tree = Value(tree),
       familyXref = Value(familyXref),
       personXref = Value(personXref),
       role = Value(role),
       statedBy = Value(statedBy);
  static Insertable<StoredMembership> custom({
    Expression<String>? tree,
    Expression<String>? familyXref,
    Expression<String>? personXref,
    Expression<String>? role,
    Expression<String>? statedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tree != null) 'tree': tree,
      if (familyXref != null) 'family_xref': familyXref,
      if (personXref != null) 'person_xref': personXref,
      if (role != null) 'role': role,
      if (statedBy != null) 'stated_by': statedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredMembershipsCompanion copyWith({
    Value<String>? tree,
    Value<String>? familyXref,
    Value<String>? personXref,
    Value<String>? role,
    Value<String>? statedBy,
    Value<int>? rowid,
  }) {
    return StoredMembershipsCompanion(
      tree: tree ?? this.tree,
      familyXref: familyXref ?? this.familyXref,
      personXref: personXref ?? this.personXref,
      role: role ?? this.role,
      statedBy: statedBy ?? this.statedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tree.present) {
      map['tree'] = Variable<String>(tree.value);
    }
    if (familyXref.present) {
      map['family_xref'] = Variable<String>(familyXref.value);
    }
    if (personXref.present) {
      map['person_xref'] = Variable<String>(personXref.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (statedBy.present) {
      map['stated_by'] = Variable<String>(statedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredMembershipsCompanion(')
          ..write('tree: $tree, ')
          ..write('familyXref: $familyXref, ')
          ..write('personXref: $personXref, ')
          ..write('role: $role, ')
          ..write('statedBy: $statedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTreeStatesTable extends StoredTreeStates
    with TableInfo<$StoredTreeStatesTable, StoredTreeState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTreeStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _treeMeta = const VerificationMeta('tree');
  @override
  late final GeneratedColumn<String> tree = GeneratedColumn<String>(
    'tree',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
    'token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fillingMeta = const VerificationMeta(
    'filling',
  );
  @override
  late final GeneratedColumn<bool> filling = GeneratedColumn<bool>(
    'filling',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("filling" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sectionsMeta = const VerificationMeta(
    'sections',
  );
  @override
  late final GeneratedColumn<String> sections = GeneratedColumn<String>(
    'sections',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _chartClassesMeta = const VerificationMeta(
    'chartClasses',
  );
  @override
  late final GeneratedColumn<String> chartClasses = GeneratedColumn<String>(
    'chart_classes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moduleVersionMeta = const VerificationMeta(
    'moduleVersion',
  );
  @override
  late final GeneratedColumn<String> moduleVersion = GeneratedColumn<String>(
    'module_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tree,
    token,
    cursor,
    filling,
    sections,
    chartClasses,
    syncedAt,
    username,
    role,
    language,
    moduleVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_tree_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredTreeState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tree')) {
      context.handle(
        _treeMeta,
        tree.isAcceptableOrUnknown(data['tree']!, _treeMeta),
      );
    } else if (isInserting) {
      context.missing(_treeMeta);
    }
    if (data.containsKey('token')) {
      context.handle(
        _tokenMeta,
        token.isAcceptableOrUnknown(data['token']!, _tokenMeta),
      );
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    if (data.containsKey('filling')) {
      context.handle(
        _fillingMeta,
        filling.isAcceptableOrUnknown(data['filling']!, _fillingMeta),
      );
    }
    if (data.containsKey('sections')) {
      context.handle(
        _sectionsMeta,
        sections.isAcceptableOrUnknown(data['sections']!, _sectionsMeta),
      );
    }
    if (data.containsKey('chart_classes')) {
      context.handle(
        _chartClassesMeta,
        chartClasses.isAcceptableOrUnknown(
          data['chart_classes']!,
          _chartClassesMeta,
        ),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    } else if (isInserting) {
      context.missing(_languageMeta);
    }
    if (data.containsKey('module_version')) {
      context.handle(
        _moduleVersionMeta,
        moduleVersion.isAcceptableOrUnknown(
          data['module_version']!,
          _moduleVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_moduleVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tree};
  @override
  StoredTreeState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredTreeState(
      tree: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree'],
      )!,
      token: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token'],
      ),
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor'],
      )!,
      filling: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}filling'],
      )!,
      sections: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sections'],
      )!,
      chartClasses: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chart_classes'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      moduleVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}module_version'],
      )!,
    );
  }

  @override
  $StoredTreeStatesTable createAlias(String alias) {
    return $StoredTreeStatesTable(attachedDatabase, alias);
  }
}

class StoredTreeState extends DataClass implements Insertable<StoredTreeState> {
  final String tree;

  /// The fingerprint the server last stated. Opaque: stored, sent back as
  /// `since`, compared for equality, never read into.
  final String? token;

  /// Where a full walk got to, in rows of the server's own ordering.
  final int cursor;

  /// Whether a full walk is still in progress. A store mid-walk holds part of
  /// a tree, which is fine to add to and not fine to *read* as though it were
  /// the tree.
  final bool filling;

  /// Which tabs this site runs, and which charts it offers, as JSON arrays.
  ///
  /// Page-level on the wire and tree-level here for the same reason: they
  /// describe the tree and the reader rather than any person, so a store keeps
  /// one copy instead of 1,463. A record read back out of the store is given
  /// these, which is what makes it identical to the one the endpoint answers.
  final String sections;
  final String chartClasses;

  /// When the last page was written. Shown to the reader: a figure from last
  /// night is not wrong, but a reader wondering about it has to be told.
  final DateTime? syncedAt;

  /// The account this copy was filled for.
  final String username;

  /// Their role in this tree. A demoted member still holds what they could
  /// see yesterday; nothing can undo that, but a changed role must not be
  /// answered from the old copy.
  final String role;

  /// The language every rendered string in here was written in.
  final String language;

  /// Which module answered. A payload's meaning has changed without its shape
  /// changing before — three times — so a store filled by an older module is
  /// not a store this app should read.
  final String moduleVersion;
  const StoredTreeState({
    required this.tree,
    this.token,
    required this.cursor,
    required this.filling,
    required this.sections,
    required this.chartClasses,
    this.syncedAt,
    required this.username,
    required this.role,
    required this.language,
    required this.moduleVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tree'] = Variable<String>(tree);
    if (!nullToAbsent || token != null) {
      map['token'] = Variable<String>(token);
    }
    map['cursor'] = Variable<int>(cursor);
    map['filling'] = Variable<bool>(filling);
    map['sections'] = Variable<String>(sections);
    map['chart_classes'] = Variable<String>(chartClasses);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    map['username'] = Variable<String>(username);
    map['role'] = Variable<String>(role);
    map['language'] = Variable<String>(language);
    map['module_version'] = Variable<String>(moduleVersion);
    return map;
  }

  StoredTreeStatesCompanion toCompanion(bool nullToAbsent) {
    return StoredTreeStatesCompanion(
      tree: Value(tree),
      token: token == null && nullToAbsent
          ? const Value.absent()
          : Value(token),
      cursor: Value(cursor),
      filling: Value(filling),
      sections: Value(sections),
      chartClasses: Value(chartClasses),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      username: Value(username),
      role: Value(role),
      language: Value(language),
      moduleVersion: Value(moduleVersion),
    );
  }

  factory StoredTreeState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredTreeState(
      tree: serializer.fromJson<String>(json['tree']),
      token: serializer.fromJson<String?>(json['token']),
      cursor: serializer.fromJson<int>(json['cursor']),
      filling: serializer.fromJson<bool>(json['filling']),
      sections: serializer.fromJson<String>(json['sections']),
      chartClasses: serializer.fromJson<String>(json['chartClasses']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      username: serializer.fromJson<String>(json['username']),
      role: serializer.fromJson<String>(json['role']),
      language: serializer.fromJson<String>(json['language']),
      moduleVersion: serializer.fromJson<String>(json['moduleVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tree': serializer.toJson<String>(tree),
      'token': serializer.toJson<String?>(token),
      'cursor': serializer.toJson<int>(cursor),
      'filling': serializer.toJson<bool>(filling),
      'sections': serializer.toJson<String>(sections),
      'chartClasses': serializer.toJson<String>(chartClasses),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'username': serializer.toJson<String>(username),
      'role': serializer.toJson<String>(role),
      'language': serializer.toJson<String>(language),
      'moduleVersion': serializer.toJson<String>(moduleVersion),
    };
  }

  StoredTreeState copyWith({
    String? tree,
    Value<String?> token = const Value.absent(),
    int? cursor,
    bool? filling,
    String? sections,
    String? chartClasses,
    Value<DateTime?> syncedAt = const Value.absent(),
    String? username,
    String? role,
    String? language,
    String? moduleVersion,
  }) => StoredTreeState(
    tree: tree ?? this.tree,
    token: token.present ? token.value : this.token,
    cursor: cursor ?? this.cursor,
    filling: filling ?? this.filling,
    sections: sections ?? this.sections,
    chartClasses: chartClasses ?? this.chartClasses,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    username: username ?? this.username,
    role: role ?? this.role,
    language: language ?? this.language,
    moduleVersion: moduleVersion ?? this.moduleVersion,
  );
  StoredTreeState copyWithCompanion(StoredTreeStatesCompanion data) {
    return StoredTreeState(
      tree: data.tree.present ? data.tree.value : this.tree,
      token: data.token.present ? data.token.value : this.token,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      filling: data.filling.present ? data.filling.value : this.filling,
      sections: data.sections.present ? data.sections.value : this.sections,
      chartClasses: data.chartClasses.present
          ? data.chartClasses.value
          : this.chartClasses,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      username: data.username.present ? data.username.value : this.username,
      role: data.role.present ? data.role.value : this.role,
      language: data.language.present ? data.language.value : this.language,
      moduleVersion: data.moduleVersion.present
          ? data.moduleVersion.value
          : this.moduleVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredTreeState(')
          ..write('tree: $tree, ')
          ..write('token: $token, ')
          ..write('cursor: $cursor, ')
          ..write('filling: $filling, ')
          ..write('sections: $sections, ')
          ..write('chartClasses: $chartClasses, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('username: $username, ')
          ..write('role: $role, ')
          ..write('language: $language, ')
          ..write('moduleVersion: $moduleVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tree,
    token,
    cursor,
    filling,
    sections,
    chartClasses,
    syncedAt,
    username,
    role,
    language,
    moduleVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredTreeState &&
          other.tree == this.tree &&
          other.token == this.token &&
          other.cursor == this.cursor &&
          other.filling == this.filling &&
          other.sections == this.sections &&
          other.chartClasses == this.chartClasses &&
          other.syncedAt == this.syncedAt &&
          other.username == this.username &&
          other.role == this.role &&
          other.language == this.language &&
          other.moduleVersion == this.moduleVersion);
}

class StoredTreeStatesCompanion extends UpdateCompanion<StoredTreeState> {
  final Value<String> tree;
  final Value<String?> token;
  final Value<int> cursor;
  final Value<bool> filling;
  final Value<String> sections;
  final Value<String> chartClasses;
  final Value<DateTime?> syncedAt;
  final Value<String> username;
  final Value<String> role;
  final Value<String> language;
  final Value<String> moduleVersion;
  final Value<int> rowid;
  const StoredTreeStatesCompanion({
    this.tree = const Value.absent(),
    this.token = const Value.absent(),
    this.cursor = const Value.absent(),
    this.filling = const Value.absent(),
    this.sections = const Value.absent(),
    this.chartClasses = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.username = const Value.absent(),
    this.role = const Value.absent(),
    this.language = const Value.absent(),
    this.moduleVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTreeStatesCompanion.insert({
    required String tree,
    this.token = const Value.absent(),
    this.cursor = const Value.absent(),
    this.filling = const Value.absent(),
    this.sections = const Value.absent(),
    this.chartClasses = const Value.absent(),
    this.syncedAt = const Value.absent(),
    required String username,
    required String role,
    required String language,
    required String moduleVersion,
    this.rowid = const Value.absent(),
  }) : tree = Value(tree),
       username = Value(username),
       role = Value(role),
       language = Value(language),
       moduleVersion = Value(moduleVersion);
  static Insertable<StoredTreeState> custom({
    Expression<String>? tree,
    Expression<String>? token,
    Expression<int>? cursor,
    Expression<bool>? filling,
    Expression<String>? sections,
    Expression<String>? chartClasses,
    Expression<DateTime>? syncedAt,
    Expression<String>? username,
    Expression<String>? role,
    Expression<String>? language,
    Expression<String>? moduleVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tree != null) 'tree': tree,
      if (token != null) 'token': token,
      if (cursor != null) 'cursor': cursor,
      if (filling != null) 'filling': filling,
      if (sections != null) 'sections': sections,
      if (chartClasses != null) 'chart_classes': chartClasses,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (username != null) 'username': username,
      if (role != null) 'role': role,
      if (language != null) 'language': language,
      if (moduleVersion != null) 'module_version': moduleVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTreeStatesCompanion copyWith({
    Value<String>? tree,
    Value<String?>? token,
    Value<int>? cursor,
    Value<bool>? filling,
    Value<String>? sections,
    Value<String>? chartClasses,
    Value<DateTime?>? syncedAt,
    Value<String>? username,
    Value<String>? role,
    Value<String>? language,
    Value<String>? moduleVersion,
    Value<int>? rowid,
  }) {
    return StoredTreeStatesCompanion(
      tree: tree ?? this.tree,
      token: token ?? this.token,
      cursor: cursor ?? this.cursor,
      filling: filling ?? this.filling,
      sections: sections ?? this.sections,
      chartClasses: chartClasses ?? this.chartClasses,
      syncedAt: syncedAt ?? this.syncedAt,
      username: username ?? this.username,
      role: role ?? this.role,
      language: language ?? this.language,
      moduleVersion: moduleVersion ?? this.moduleVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tree.present) {
      map['tree'] = Variable<String>(tree.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    if (filling.present) {
      map['filling'] = Variable<bool>(filling.value);
    }
    if (sections.present) {
      map['sections'] = Variable<String>(sections.value);
    }
    if (chartClasses.present) {
      map['chart_classes'] = Variable<String>(chartClasses.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (moduleVersion.present) {
      map['module_version'] = Variable<String>(moduleVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTreeStatesCompanion(')
          ..write('tree: $tree, ')
          ..write('token: $token, ')
          ..write('cursor: $cursor, ')
          ..write('filling: $filling, ')
          ..write('sections: $sections, ')
          ..write('chartClasses: $chartClasses, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('username: $username, ')
          ..write('role: $role, ')
          ..write('language: $language, ')
          ..write('moduleVersion: $moduleVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalStore extends GeneratedDatabase {
  _$LocalStore(QueryExecutor e) : super(e);
  $LocalStoreManager get managers => $LocalStoreManager(this);
  late final $StoredPeopleTable storedPeople = $StoredPeopleTable(this);
  late final $StoredMembershipsTable storedMemberships =
      $StoredMembershipsTable(this);
  late final $StoredTreeStatesTable storedTreeStates = $StoredTreeStatesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storedPeople,
    storedMemberships,
    storedTreeStates,
  ];
}

typedef $$StoredPeopleTableCreateCompanionBuilder =
    StoredPeopleCompanion Function({
      required String tree,
      required String xref,
      required String name,
      required String nameFold,
      required String sortName,
      Value<String?> alternateName,
      required String sex,
      required bool deceased,
      Value<String?> lifespan,
      Value<int?> birthYear,
      Value<int?> deathYear,
      Value<int?> age,
      Value<String?> birthPlace,
      Value<String?> thumbnailUrl,
      required bool private,
      required String payload,
      Value<int> rowid,
    });
typedef $$StoredPeopleTableUpdateCompanionBuilder =
    StoredPeopleCompanion Function({
      Value<String> tree,
      Value<String> xref,
      Value<String> name,
      Value<String> nameFold,
      Value<String> sortName,
      Value<String?> alternateName,
      Value<String> sex,
      Value<bool> deceased,
      Value<String?> lifespan,
      Value<int?> birthYear,
      Value<int?> deathYear,
      Value<int?> age,
      Value<String?> birthPlace,
      Value<String?> thumbnailUrl,
      Value<bool> private,
      Value<String> payload,
      Value<int> rowid,
    });

class $$StoredPeopleTableFilterComposer
    extends Composer<_$LocalStore, $StoredPeopleTable> {
  $$StoredPeopleTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tree => $composableBuilder(
    column: $table.tree,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get xref => $composableBuilder(
    column: $table.xref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameFold => $composableBuilder(
    column: $table.nameFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortName => $composableBuilder(
    column: $table.sortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alternateName => $composableBuilder(
    column: $table.alternateName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sex => $composableBuilder(
    column: $table.sex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deceased => $composableBuilder(
    column: $table.deceased,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifespan => $composableBuilder(
    column: $table.lifespan,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get birthYear => $composableBuilder(
    column: $table.birthYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deathYear => $composableBuilder(
    column: $table.deathYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get birthPlace => $composableBuilder(
    column: $table.birthPlace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get private => $composableBuilder(
    column: $table.private,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredPeopleTableOrderingComposer
    extends Composer<_$LocalStore, $StoredPeopleTable> {
  $$StoredPeopleTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tree => $composableBuilder(
    column: $table.tree,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get xref => $composableBuilder(
    column: $table.xref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameFold => $composableBuilder(
    column: $table.nameFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortName => $composableBuilder(
    column: $table.sortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alternateName => $composableBuilder(
    column: $table.alternateName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sex => $composableBuilder(
    column: $table.sex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deceased => $composableBuilder(
    column: $table.deceased,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifespan => $composableBuilder(
    column: $table.lifespan,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get birthYear => $composableBuilder(
    column: $table.birthYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deathYear => $composableBuilder(
    column: $table.deathYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get birthPlace => $composableBuilder(
    column: $table.birthPlace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get private => $composableBuilder(
    column: $table.private,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredPeopleTableAnnotationComposer
    extends Composer<_$LocalStore, $StoredPeopleTable> {
  $$StoredPeopleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tree =>
      $composableBuilder(column: $table.tree, builder: (column) => column);

  GeneratedColumn<String> get xref =>
      $composableBuilder(column: $table.xref, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameFold =>
      $composableBuilder(column: $table.nameFold, builder: (column) => column);

  GeneratedColumn<String> get sortName =>
      $composableBuilder(column: $table.sortName, builder: (column) => column);

  GeneratedColumn<String> get alternateName => $composableBuilder(
    column: $table.alternateName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sex =>
      $composableBuilder(column: $table.sex, builder: (column) => column);

  GeneratedColumn<bool> get deceased =>
      $composableBuilder(column: $table.deceased, builder: (column) => column);

  GeneratedColumn<String> get lifespan =>
      $composableBuilder(column: $table.lifespan, builder: (column) => column);

  GeneratedColumn<int> get birthYear =>
      $composableBuilder(column: $table.birthYear, builder: (column) => column);

  GeneratedColumn<int> get deathYear =>
      $composableBuilder(column: $table.deathYear, builder: (column) => column);

  GeneratedColumn<int> get age =>
      $composableBuilder(column: $table.age, builder: (column) => column);

  GeneratedColumn<String> get birthPlace => $composableBuilder(
    column: $table.birthPlace,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get private =>
      $composableBuilder(column: $table.private, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$StoredPeopleTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $StoredPeopleTable,
          StoredPerson,
          $$StoredPeopleTableFilterComposer,
          $$StoredPeopleTableOrderingComposer,
          $$StoredPeopleTableAnnotationComposer,
          $$StoredPeopleTableCreateCompanionBuilder,
          $$StoredPeopleTableUpdateCompanionBuilder,
          (
            StoredPerson,
            BaseReferences<_$LocalStore, $StoredPeopleTable, StoredPerson>,
          ),
          StoredPerson,
          PrefetchHooks Function()
        > {
  $$StoredPeopleTableTableManager(_$LocalStore db, $StoredPeopleTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredPeopleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredPeopleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredPeopleTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tree = const Value.absent(),
                Value<String> xref = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameFold = const Value.absent(),
                Value<String> sortName = const Value.absent(),
                Value<String?> alternateName = const Value.absent(),
                Value<String> sex = const Value.absent(),
                Value<bool> deceased = const Value.absent(),
                Value<String?> lifespan = const Value.absent(),
                Value<int?> birthYear = const Value.absent(),
                Value<int?> deathYear = const Value.absent(),
                Value<int?> age = const Value.absent(),
                Value<String?> birthPlace = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<bool> private = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredPeopleCompanion(
                tree: tree,
                xref: xref,
                name: name,
                nameFold: nameFold,
                sortName: sortName,
                alternateName: alternateName,
                sex: sex,
                deceased: deceased,
                lifespan: lifespan,
                birthYear: birthYear,
                deathYear: deathYear,
                age: age,
                birthPlace: birthPlace,
                thumbnailUrl: thumbnailUrl,
                private: private,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tree,
                required String xref,
                required String name,
                required String nameFold,
                required String sortName,
                Value<String?> alternateName = const Value.absent(),
                required String sex,
                required bool deceased,
                Value<String?> lifespan = const Value.absent(),
                Value<int?> birthYear = const Value.absent(),
                Value<int?> deathYear = const Value.absent(),
                Value<int?> age = const Value.absent(),
                Value<String?> birthPlace = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                required bool private,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => StoredPeopleCompanion.insert(
                tree: tree,
                xref: xref,
                name: name,
                nameFold: nameFold,
                sortName: sortName,
                alternateName: alternateName,
                sex: sex,
                deceased: deceased,
                lifespan: lifespan,
                birthYear: birthYear,
                deathYear: deathYear,
                age: age,
                birthPlace: birthPlace,
                thumbnailUrl: thumbnailUrl,
                private: private,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredPeopleTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $StoredPeopleTable,
      StoredPerson,
      $$StoredPeopleTableFilterComposer,
      $$StoredPeopleTableOrderingComposer,
      $$StoredPeopleTableAnnotationComposer,
      $$StoredPeopleTableCreateCompanionBuilder,
      $$StoredPeopleTableUpdateCompanionBuilder,
      (
        StoredPerson,
        BaseReferences<_$LocalStore, $StoredPeopleTable, StoredPerson>,
      ),
      StoredPerson,
      PrefetchHooks Function()
    >;
typedef $$StoredMembershipsTableCreateCompanionBuilder =
    StoredMembershipsCompanion Function({
      required String tree,
      required String familyXref,
      required String personXref,
      required String role,
      required String statedBy,
      Value<int> rowid,
    });
typedef $$StoredMembershipsTableUpdateCompanionBuilder =
    StoredMembershipsCompanion Function({
      Value<String> tree,
      Value<String> familyXref,
      Value<String> personXref,
      Value<String> role,
      Value<String> statedBy,
      Value<int> rowid,
    });

class $$StoredMembershipsTableFilterComposer
    extends Composer<_$LocalStore, $StoredMembershipsTable> {
  $$StoredMembershipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tree => $composableBuilder(
    column: $table.tree,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get familyXref => $composableBuilder(
    column: $table.familyXref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personXref => $composableBuilder(
    column: $table.personXref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statedBy => $composableBuilder(
    column: $table.statedBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredMembershipsTableOrderingComposer
    extends Composer<_$LocalStore, $StoredMembershipsTable> {
  $$StoredMembershipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tree => $composableBuilder(
    column: $table.tree,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get familyXref => $composableBuilder(
    column: $table.familyXref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personXref => $composableBuilder(
    column: $table.personXref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statedBy => $composableBuilder(
    column: $table.statedBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredMembershipsTableAnnotationComposer
    extends Composer<_$LocalStore, $StoredMembershipsTable> {
  $$StoredMembershipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tree =>
      $composableBuilder(column: $table.tree, builder: (column) => column);

  GeneratedColumn<String> get familyXref => $composableBuilder(
    column: $table.familyXref,
    builder: (column) => column,
  );

  GeneratedColumn<String> get personXref => $composableBuilder(
    column: $table.personXref,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get statedBy =>
      $composableBuilder(column: $table.statedBy, builder: (column) => column);
}

class $$StoredMembershipsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $StoredMembershipsTable,
          StoredMembership,
          $$StoredMembershipsTableFilterComposer,
          $$StoredMembershipsTableOrderingComposer,
          $$StoredMembershipsTableAnnotationComposer,
          $$StoredMembershipsTableCreateCompanionBuilder,
          $$StoredMembershipsTableUpdateCompanionBuilder,
          (
            StoredMembership,
            BaseReferences<
              _$LocalStore,
              $StoredMembershipsTable,
              StoredMembership
            >,
          ),
          StoredMembership,
          PrefetchHooks Function()
        > {
  $$StoredMembershipsTableTableManager(
    _$LocalStore db,
    $StoredMembershipsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredMembershipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredMembershipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredMembershipsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> tree = const Value.absent(),
                Value<String> familyXref = const Value.absent(),
                Value<String> personXref = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> statedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredMembershipsCompanion(
                tree: tree,
                familyXref: familyXref,
                personXref: personXref,
                role: role,
                statedBy: statedBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tree,
                required String familyXref,
                required String personXref,
                required String role,
                required String statedBy,
                Value<int> rowid = const Value.absent(),
              }) => StoredMembershipsCompanion.insert(
                tree: tree,
                familyXref: familyXref,
                personXref: personXref,
                role: role,
                statedBy: statedBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredMembershipsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $StoredMembershipsTable,
      StoredMembership,
      $$StoredMembershipsTableFilterComposer,
      $$StoredMembershipsTableOrderingComposer,
      $$StoredMembershipsTableAnnotationComposer,
      $$StoredMembershipsTableCreateCompanionBuilder,
      $$StoredMembershipsTableUpdateCompanionBuilder,
      (
        StoredMembership,
        BaseReferences<_$LocalStore, $StoredMembershipsTable, StoredMembership>,
      ),
      StoredMembership,
      PrefetchHooks Function()
    >;
typedef $$StoredTreeStatesTableCreateCompanionBuilder =
    StoredTreeStatesCompanion Function({
      required String tree,
      Value<String?> token,
      Value<int> cursor,
      Value<bool> filling,
      Value<String> sections,
      Value<String> chartClasses,
      Value<DateTime?> syncedAt,
      required String username,
      required String role,
      required String language,
      required String moduleVersion,
      Value<int> rowid,
    });
typedef $$StoredTreeStatesTableUpdateCompanionBuilder =
    StoredTreeStatesCompanion Function({
      Value<String> tree,
      Value<String?> token,
      Value<int> cursor,
      Value<bool> filling,
      Value<String> sections,
      Value<String> chartClasses,
      Value<DateTime?> syncedAt,
      Value<String> username,
      Value<String> role,
      Value<String> language,
      Value<String> moduleVersion,
      Value<int> rowid,
    });

class $$StoredTreeStatesTableFilterComposer
    extends Composer<_$LocalStore, $StoredTreeStatesTable> {
  $$StoredTreeStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tree => $composableBuilder(
    column: $table.tree,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get filling => $composableBuilder(
    column: $table.filling,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sections => $composableBuilder(
    column: $table.sections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chartClasses => $composableBuilder(
    column: $table.chartClasses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get moduleVersion => $composableBuilder(
    column: $table.moduleVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTreeStatesTableOrderingComposer
    extends Composer<_$LocalStore, $StoredTreeStatesTable> {
  $$StoredTreeStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tree => $composableBuilder(
    column: $table.tree,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get filling => $composableBuilder(
    column: $table.filling,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sections => $composableBuilder(
    column: $table.sections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chartClasses => $composableBuilder(
    column: $table.chartClasses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get moduleVersion => $composableBuilder(
    column: $table.moduleVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTreeStatesTableAnnotationComposer
    extends Composer<_$LocalStore, $StoredTreeStatesTable> {
  $$StoredTreeStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tree =>
      $composableBuilder(column: $table.tree, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<bool> get filling =>
      $composableBuilder(column: $table.filling, builder: (column) => column);

  GeneratedColumn<String> get sections =>
      $composableBuilder(column: $table.sections, builder: (column) => column);

  GeneratedColumn<String> get chartClasses => $composableBuilder(
    column: $table.chartClasses,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get moduleVersion => $composableBuilder(
    column: $table.moduleVersion,
    builder: (column) => column,
  );
}

class $$StoredTreeStatesTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $StoredTreeStatesTable,
          StoredTreeState,
          $$StoredTreeStatesTableFilterComposer,
          $$StoredTreeStatesTableOrderingComposer,
          $$StoredTreeStatesTableAnnotationComposer,
          $$StoredTreeStatesTableCreateCompanionBuilder,
          $$StoredTreeStatesTableUpdateCompanionBuilder,
          (
            StoredTreeState,
            BaseReferences<
              _$LocalStore,
              $StoredTreeStatesTable,
              StoredTreeState
            >,
          ),
          StoredTreeState,
          PrefetchHooks Function()
        > {
  $$StoredTreeStatesTableTableManager(
    _$LocalStore db,
    $StoredTreeStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTreeStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTreeStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredTreeStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tree = const Value.absent(),
                Value<String?> token = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<bool> filling = const Value.absent(),
                Value<String> sections = const Value.absent(),
                Value<String> chartClasses = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> moduleVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTreeStatesCompanion(
                tree: tree,
                token: token,
                cursor: cursor,
                filling: filling,
                sections: sections,
                chartClasses: chartClasses,
                syncedAt: syncedAt,
                username: username,
                role: role,
                language: language,
                moduleVersion: moduleVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tree,
                Value<String?> token = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<bool> filling = const Value.absent(),
                Value<String> sections = const Value.absent(),
                Value<String> chartClasses = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                required String username,
                required String role,
                required String language,
                required String moduleVersion,
                Value<int> rowid = const Value.absent(),
              }) => StoredTreeStatesCompanion.insert(
                tree: tree,
                token: token,
                cursor: cursor,
                filling: filling,
                sections: sections,
                chartClasses: chartClasses,
                syncedAt: syncedAt,
                username: username,
                role: role,
                language: language,
                moduleVersion: moduleVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTreeStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $StoredTreeStatesTable,
      StoredTreeState,
      $$StoredTreeStatesTableFilterComposer,
      $$StoredTreeStatesTableOrderingComposer,
      $$StoredTreeStatesTableAnnotationComposer,
      $$StoredTreeStatesTableCreateCompanionBuilder,
      $$StoredTreeStatesTableUpdateCompanionBuilder,
      (
        StoredTreeState,
        BaseReferences<_$LocalStore, $StoredTreeStatesTable, StoredTreeState>,
      ),
      StoredTreeState,
      PrefetchHooks Function()
    >;

class $LocalStoreManager {
  final _$LocalStore _db;
  $LocalStoreManager(this._db);
  $$StoredPeopleTableTableManager get storedPeople =>
      $$StoredPeopleTableTableManager(_db, _db.storedPeople);
  $$StoredMembershipsTableTableManager get storedMemberships =>
      $$StoredMembershipsTableTableManager(_db, _db.storedMemberships);
  $$StoredTreeStatesTableTableManager get storedTreeStates =>
      $$StoredTreeStatesTableTableManager(_db, _db.storedTreeStates);
}
