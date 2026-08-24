/// Everything the app knows about the site it is talking to, in one place.
///
/// The app already discovers all of this — the address style it settled on,
/// the version it read, whether a module answered, which transport is serving
/// each capability — and until now none of it was visible to the person
/// holding the phone. That matters more here than in most apps: this one talks
/// to somebody else's webtrees install, over markup that changes between
/// versions and themes, and the useful bug report is the one that says which
/// version, which style and which transport.
///
/// A snapshot rather than a live view: it is read once when the screen opens,
/// so what a reader copies is what they were looking at.
library;

import 'package:meta/meta.dart';

import '../core/webtrees_client.dart';
import '../domain/instance.dart';
import '../domain/notice.dart';
import 'capabilities.dart';
import 'module/module_api.dart';
import 'session_manager.dart';

/// One thing the app can read, and where it is being read from.
@immutable
final class CapabilitySource {
  const CapabilitySource(this.capability, {required this.readFrom});

  /// The feature name the module advertises, e.g. `individual`.
  final String capability;

  /// Which of the three answers this one. Three rather than two since Phase
  /// 10c: a figure from this device's copy is not wrong, but a reader
  /// wondering about it has to be told where it came from and how old it is
  /// (`sync_eval.md` §11 #1).
  final ReadFrom readFrom;

  /// Whether the module is answering this one.
  ///
  /// Kept because it is the question a bug report asks, and because a store
  /// only ever holds what the module sent — so a stored answer is a module
  /// answer that has been kept.
  bool get fromModule => readFrom != ReadFrom.page;
}

/// What the app knows about this site, this account and itself.
@immutable
final class Diagnostics {
  const Diagnostics({
    required this.stage,
    required this.instance,
    required this.username,
    required this.capabilities,
    this.hasStore = false,
    this.syncedAt,
    this.storedPeople = 0,
    this.appVersion = kAppVersion,
    this.userAgent = kUserAgent,
  });

  /// Reads the current state of a session.
  factory Diagnostics.of(
    SessionManager session, {
    ModuleCapabilities? capabilities,
    bool hasStore = false,
    DateTime? syncedAt,
    int storedPeople = 0,
  }) => Diagnostics(
    stage: session.stage,
    instance: session.instance,
    username: session.connection?.username,
    capabilities: capabilities ?? ModuleCapabilities.none,
    hasStore: hasStore,
    syncedAt: syncedAt,
    storedPeople: storedPeople,
  );

  final ConnectionStage stage;

  /// Null before a site has been identified, which is a state worth showing:
  /// it is exactly when somebody most wants a diagnostics screen.
  final WebtreesInstance? instance;

  final String? username;

  final ModuleCapabilities capabilities;

  /// Whether a complete local copy is being read from right now.
  final bool hasStore;

  /// When that copy was last written to. The single most useful thing on this
  /// screen once a store exists, because it is what turns "is it stale or is
  /// it wrong?" back into two separate questions.
  final DateTime? syncedAt;

  /// How many people the copy holds — a figure a reader can compare against
  /// what the site says the tree contains.
  final int storedPeople;

  final String appVersion;
  final String userAgent;

  /// What the site told the app about itself, and could not.
  List<Notice> get findings => instance?.warnings ?? const [];

  /// Which transport answers each capability, in the order a reader meets
  /// them.
  ///
  /// The single most useful line on the screen, and the one nothing else in
  /// the app states: adoption is per capability, so "the module is installed"
  /// and "this screen is using it" are different questions.
  List<CapabilitySource> get sources => [
    for (final capability in const [
      Capability.access,
      Capability.individuals,
      Capability.individual,
      Capability.ancestors,
      Capability.descendants,
      Capability.relationship,
      Capability.timeline,
      Capability.statistics,
    ])
      CapabilitySource(
        capability,
        // What the composer actually does, not what the module offers: a
        // capability can be advertised and still answered from the page, and
        // it can be advertised, implemented and still answered from a copy
        // taken last night.
        readFrom: Capability.sourceOf(
          capability,
          capabilities,
          hasStore: hasStore,
        ),
      ),
  ];

  /// A plain-text report, for pasting into a bug report.
  ///
  /// Deliberately not translated: it is written for whoever reads the issue,
  /// not for whoever files it. It carries the site address and the account
  /// name — both of which a maintainer needs — and no password, no cookie and
  /// no real name.
  String get report {
    final site = instance;
    final lines = <String>[
      'webtrees_mobile $appVersion',
      'user agent: $userAgent',
      'connection: ${stage.name}',
      if (username != null) 'account: $username',
      if (site == null)
        'site: none connected'
      else ...[
        'site: ${site.url.base}',
        'address style: ${site.url.style.name}',
        'webtrees: ${site.version.isEmpty ? 'unreadable' : site.version}',
        'health: ${site.health.name}',
      ],
      if (!capabilities.isPresent)
        'module: not installed'
      else ...[
        'module: ${capabilities.moduleVersion} (api ${capabilities.apiVersion})',
        'module reports webtrees: ${capabilities.webtreesVersion}',
        'features: ${(capabilities.features.toList()..sort()).join(', ')}',
        'limits: page=${capabilities.maxPageSize} '
            'generations=${capabilities.maxGenerations} '
            'image=${capabilities.maxImage}',
        'languages: ${(capabilities.languages.toList()..sort()).join(', ')}',
      ],
      if (!hasStore)
        'store: none'
      else
        'store: $storedPeople people, synced '
            '${syncedAt?.toIso8601String() ?? 'never'}',
      'reading: ${sources.map((source) => '${source.capability}='
          '${_wordFor(source.readFrom)}').join(' ')}',
      for (final finding in findings) 'finding: ${finding.diagnostic}',
    ];

    return lines.join('\n');
  }

  /// What the report calls each source.
  ///
  /// Spelled out rather than taken from [ReadFrom.name] so the wire format of
  /// a bug report is decided here and not by an enum somebody may rename.
  /// `pages` has been in this report since Phase 5 and people grep for it.
  static String _wordFor(ReadFrom source) => switch (source) {
    ReadFrom.page => 'pages',
    ReadFrom.module => 'module',
    ReadFrom.store => 'store',
  };
}
