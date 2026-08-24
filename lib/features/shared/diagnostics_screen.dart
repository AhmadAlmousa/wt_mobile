import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/webtrees_url.dart';
import '../../data/capabilities.dart';
import '../../data/diagnostics.dart';
import '../../data/module/module_api.dart';
import '../../data/session_manager.dart';
import '../../domain/instance.dart';
import '../../l10n/app_localizations.dart';
import 'bidi.dart';
import 'messages.dart';

/// What the app knows about the site it is talking to.
///
/// The app has always discovered all of this and never shown any of it. That
/// is a bigger gap here than in most apps: this one talks to somebody else's
/// webtrees install, over markup that differs by version and theme, and the
/// difference between a useful bug report and a useless one is whether it says
/// which version, which address style and which transport answered.
///
/// It is also the only place the app admits **which transport is serving
/// what.** Adoption is per capability, so "the module is installed" and "this
/// screen is using the module" are different questions, and until now nothing
/// answered the second one.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({required this.diagnostics, super.key});

  final Diagnostics diagnostics;

  static Future<void> show(BuildContext context, Diagnostics diagnostics) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => DiagnosticsScreen(diagnostics: diagnostics),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final site = diagnostics.instance;

    return Scaffold(
      appBar: AppBar(title: Text(text.diagnostics)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Footnote(text.diagnosticsWhy),
            const SizedBox(height: 20),

            _Group(text.diagnosticsSite),
            if (site == null)
              _Row(
                label: text.diagnosticsAddress,
                value: text.diagnosticsNoSite,
              )
            else ...[
              _Row(
                label: text.diagnosticsAddress,
                // An address is Latin and punctuation, and an Arabic screen
                // would otherwise lay its parts out backwards.
                value: ltrRun(site.url.base.toString()),
              ),
              _Row(
                label: text.diagnosticsUrlStyle,
                value: switch (site.url.style) {
                  UrlStyle.pretty => text.diagnosticsUrlPretty,
                  UrlStyle.ugly => text.diagnosticsUrlQuery,
                },
              ),
              _Row(
                label: text.diagnosticsSiteVersion,
                value: site.version.isEmpty
                    ? text.diagnosticsUnreadable
                    : ltrRun(site.version),
              ),
              _Row(
                label: text.diagnosticsHealth,
                value: switch (site.health) {
                  ServerHealth.ok => text.diagnosticsHealthOk,
                  ServerHealth.degraded => text.diagnosticsHealthDegraded,
                },
              ),
            ],

            const SizedBox(height: 24),
            _Group(text.diagnosticsAccount),
            _Row(
              label: text.diagnosticsConnection,
              value: switch (diagnostics.stage) {
                ConnectionStage.disconnected =>
                  text.diagnosticsStageDisconnected,
                ConnectionStage.connecting => text.diagnosticsStageConnecting,
                ConnectionStage.signedOut => text.diagnosticsStageSignedOut,
                ConnectionStage.signingIn => text.diagnosticsStageSigningIn,
                ConnectionStage.signedIn => text.diagnosticsStageSignedIn,
                ConnectionStage.offline => text.diagnosticsStageOffline,
              },
            ),
            if (diagnostics.username != null)
              _Row(
                label: text.diagnosticsSignedInAs,
                value: isolatedRun(diagnostics.username),
              ),

            const SizedBox(height: 24),
            _Module(capabilities: diagnostics.capabilities),

            const SizedBox(height: 24),
            _Group(text.diagnosticsReading),
            _Footnote(text.diagnosticsReadingWhy),
            const SizedBox(height: 8),
            for (final source in diagnostics.sources)
              _Row(
                label: _nameOf(source.capability, text),
                value: switch (source.readFrom) {
                  ReadFrom.store => text.diagnosticsFromStore,
                  ReadFrom.module => text.diagnosticsFromModule,
                  ReadFrom.page => text.diagnosticsFromPages,
                },
                emphasis: source.fromModule,
              ),

            const SizedBox(height: 24),
            _Group(text.diagnosticsStore),
            if (!diagnostics.hasStore)
              _Row(
                label: text.diagnosticsStore,
                value: text.diagnosticsStoreNone,
              )
            else ...[
              _Row(
                label: text.diagnosticsStorePeople(diagnostics.storedPeople),
                value: text.diagnosticsStoreSynced(
                  // The exact instant, not "an hour ago": this screen is read
                  // to file a bug, and the reader of that bug needs an
                  // unambiguous time. The relative form belongs on the screen
                  // the answer appeared on.
                  diagnostics.syncedAt?.toLocal().toString() ?? '—',
                ),
                emphasis: true,
              ),
            ],

            if (diagnostics.findings.isNotEmpty) ...[
              const SizedBox(height: 24),
              _Group(text.diagnosticsFindings),
              for (final finding in diagnostics.findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    finding.localized(text),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],

            const SizedBox(height: 24),
            _Group(text.diagnosticsApp),
            _Row(
              label: text.diagnosticsAppVersion,
              value: ltrRun(diagnostics.appVersion),
            ),
            _Row(
              label: text.diagnosticsUserAgent,
              value: ltrRun(diagnostics.userAgent),
            ),

            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(text.diagnosticsCopy),
              onPressed: () => _copy(context, text),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, AppText text) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: diagnostics.report));
    messenger.showSnackBar(SnackBar(content: Text(text.diagnosticsCopied)));
  }
}

/// What each capability is called, in the reader's language.
///
/// The wire names are the module's, not the reader's: `individuals` is a
/// search and `individual` is a person, and nobody outside this codebase
/// should have to know that.
String _nameOf(String capability, AppText text) => switch (capability) {
  Capability.access => text.yourAccess,
  Capability.individuals => text.diagnosticsSearch,
  Capability.individual => text.person,
  Capability.ancestors => text.chartAncestors,
  Capability.descendants => text.chartDescendants,
  Capability.relationship => text.chartRelationship,
  Capability.timeline => text.chartTimeline,
  Capability.statistics => text.statistics,
  _ => capability,
};

/// What the optional module says it is, or that there is not one.
class _Module extends StatelessWidget {
  const _Module({required this.capabilities});

  final ModuleCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    if (!capabilities.isPresent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Group(text.diagnosticsModule),
          _Footnote(text.diagnosticsModuleAbsent),
        ],
      );
    }

    final languages = capabilities.languages.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(text.diagnosticsModule),
        _Row(
          label: text.diagnosticsModuleVersion,
          value: ltrRun(capabilities.moduleVersion),
        ),
        _Row(
          label: text.diagnosticsApiVersion,
          value: ltrRun('${capabilities.apiVersion}'),
        ),
        if (capabilities.webtreesVersion.isNotEmpty)
          _Row(
            label: text.diagnosticsModuleSaysWebtrees,
            value: ltrRun(capabilities.webtreesVersion),
          ),
        _Row(
          label: text.diagnosticsLimits,
          value: text.diagnosticsLimitsValue(
            capabilities.maxPageSize,
            capabilities.maxGenerations,
            capabilities.maxImage,
          ),
        ),
        if (languages.isNotEmpty)
          _Row(
            label: text.diagnosticsLanguages,
            value: ltrRun(languages.join(', ')),
          ),
      ],
    );
  }
}

/// One label and one value, laid out so a long value wraps under a short
/// label rather than squeezing it.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;

  /// Marks the answer worth noticing — the module answering a capability,
  /// which is the whole reason this screen lists them.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: emphasis ? theme.colorScheme.primary : null,
                fontWeight: emphasis ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
