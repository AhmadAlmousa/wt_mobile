import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../data/access_probe.dart';
import '../../data/session_manager.dart';
import '../../data/settings_store.dart';
import '../../domain/access.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/settings_sheet.dart';

/// Shows who is signed in, which trees they can reach, and what they may do.
///
/// This is the first screen that proves the whole stack works end to end, and
/// it doubles as the diagnostics view when something looks wrong.
class AccessScreen extends StatefulWidget {
  const AccessScreen({
    required this.session,
    required this.settings,
    required this.onSignedOut,
    required this.onBrowseTree,
    super.key,
  });

  final SessionManager session;
  final SettingsStore settings;
  final VoidCallback onSignedOut;

  /// Opens a tree for browsing. Reading is available to every role, so this is
  /// offered whatever the badges on the card say.
  final void Function(String tree) onBrowseTree;

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  Future<AccessSummary>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _summary = widget.session
          .withSession(() => AccessProbe(widget.session.client).describe())
          .then((summary) async {
            // The real name is only discoverable here, so this is the one
            // chance to label the connection for next time.
            await widget.session.noteAccountName(summary.account.realName);
            return summary;
          });
    });
  }

  Future<void> _signOut() async {
    await widget.session.signOut();
    if (mounted) widget.onSignedOut();
  }

  Future<void> _forgetSite() async {
    await widget.session.forgetThisSite();
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final instance = widget.session.instance;
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(text.yourAccess),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.checkAgain,
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: text.settings,
            onPressed: () => SettingsSheet.show(context, widget.settings),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: text.signOut,
            onPressed: _signOut,
          ),
          PopupMenuButton<void>(
            tooltip: text.more,
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: _forgetSite,
                child: Text(text.forgetThisSite),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _load(),
          child: FutureBuilder<AccessSummary>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final error = snapshot.error;
              if (error != null) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    MessagePanel.error(
                      error is WebtreesError
                          ? error.localized(text)
                          : text.accessReadFailed,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: Text(text.tryAgain)),
                  ],
                );
              }

              final summary = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AccountCard(
                    account: summary.account,
                    host: instance?.url.base.host ?? '',
                    version: instance?.version ?? '',
                    isAdministrator: summary.isAdministrator,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    text.familyTrees,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final tree in summary.trees)
                    _TreeCard(
                      tree: tree,
                      onOpen: () => widget.onBrowseTree(tree.name),
                    ),
                  for (final warning in summary.warnings) ...[
                    const SizedBox(height: 12),
                    MessagePanel.warning(warning.localized(text)),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.host,
    required this.version,
    required this.isAdministrator,
  });

  final Account account;
  final String host;
  final String version;
  final bool isAdministrator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                _initials(account.displayName),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.email ?? account.username,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    version.isEmpty ? host : text.hostAndVersion(host, version),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (isAdministrator) ...[
                    const SizedBox(height: 10),
                    _RoleChip(
                      label: text.siteAdministrator,
                      icon: Icons.shield_outlined,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words.first.characters.first + words.last.characters.first)
        .toUpperCase();
  }
}

class _TreeCard extends StatelessWidget {
  const _TreeCard({required this.tree, required this.onOpen});

  final TreeAccess tree;

  /// Opens the tree for browsing. Every role can read, so this is offered
  /// whatever the badges below it say.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
                    ),
                    child: Icon(
                      Icons.park_outlined,
                      size: 22,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tree.title ?? tree.name,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  // Mirrors with the layout, unlike a hardcoded chevron_right.
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _describe(tree.role, text),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RoleChip(
                    label: _roleName(tree.role, text),
                    icon: Icons.badge_outlined,
                    emphasised: true,
                  ),
                  if (tree.role.canEdit)
                    _RoleChip(label: text.canEdit, icon: Icons.edit_outlined),
                  if (tree.role.canModerate)
                    _RoleChip(
                      label: text.canApproveChanges,
                      icon: Icons.task_alt,
                    ),
                  if (tree.role.canManage)
                    _RoleChip(
                      label: text.canManage,
                      icon: Icons.settings_outlined,
                    ),
                  if (tree.myXref != null)
                    _RoleChip(
                      label: text.linkedTo(tree.myXref!),
                      icon: Icons.person_pin_circle_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _roleName(TreeRole role, AppText text) => switch (role) {
    TreeRole.administrator => text.roleAdministrator,
    TreeRole.manager => text.roleManager,
    TreeRole.moderator => text.roleModerator,
    TreeRole.editor => text.roleEditor,
    TreeRole.member => text.roleMember,
    TreeRole.memberOrVisitor => text.roleReadOnly,
  };

  static String _describe(TreeRole role, AppText text) => switch (role) {
    TreeRole.administrator => text.describeAdministrator,
    TreeRole.manager => text.describeManager,
    TreeRole.moderator => text.describeModerator,
    TreeRole.editor => text.describeEditor,
    TreeRole.member => text.describeMember,
    // Being unable to tell Member from Visitor is a genuine limit of reading a
    // stock webtrees site, so the interface says so rather than guessing.
    TreeRole.memberOrVisitor => text.describeMemberOrVisitor,
  };
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.icon,
    this.emphasised = false,
  });

  final String label;
  final IconData icon;

  /// Marks the chip naming the role itself, which outranks the capability
  /// chips beside it.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = emphasised
        ? colors.secondaryContainer
        : colors.surfaceContainerHighest;
    final foreground = emphasised
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        // A stadium chip is the Expressive shape for a status pill.
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
