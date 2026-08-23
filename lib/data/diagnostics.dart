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
  const CapabilitySource(this.capability, {required this.fromModule});

  /// The feature name the module advertises, e.g. `individual`.
  final String capability;

  /// Whether the module is answering this one. False means the site's own
  /// pages are, which is the floor and never goes away.
  final bool fromModule;
}

/// What the app knows about this site, this account and itself.
@immutable
final class Diagnostics {
  const Diagnostics({
    required this.stage,
    required this.instance,
    required this.username,
    required this.capabilities,
    this.appVersion = kAppVersion,
    this.userAgent = kUserAgent,
  });

  /// Reads the current state of a session.
  factory Diagnostics.of(
    SessionManager session, {
    ModuleCapabilities? capabilities,
  }) => Diagnostics(
    stage: session.stage,
    instance: session.instance,
    username: session.connection?.username,
    capabilities: capabilities ?? ModuleCapabilities.none,
  );

  final ConnectionStage stage;

  /// Null before a site has been identified, which is a state worth showing:
  /// it is exactly when somebody most wants a diagnostics screen.
  final WebtreesInstance? instance;

  final String? username;

  final ModuleCapabilities capabilities;
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
      CapabilitySource(capability, fromModule: capabilities.has(capability)),
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
      'reading: ${sources.map((source) => '${source.capability}='
          '${source.fromModule ? 'module' : 'pages'}').join(' ')}',
      for (final finding in findings) 'finding: ${finding.diagnostic}',
    ];

    return lines.join('\n');
  }
}
