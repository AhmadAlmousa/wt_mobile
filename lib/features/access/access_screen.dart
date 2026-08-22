import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/access_probe.dart';
import '../../data/session_manager.dart';
import '../../domain/access.dart';
import '../shared/message_panel.dart';

/// Shows who is signed in, which trees they can reach, and what they may do.
///
/// This is the first screen that proves the whole stack works end to end, and
/// it doubles as the diagnostics view when something looks wrong.
class AccessScreen extends StatefulWidget {
  const AccessScreen({
    required this.session,
    required this.onSignedOut,
    super.key,
  });

  final SessionManager session;
  final VoidCallback onSignedOut;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your access'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check again',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
          PopupMenuButton<void>(
            tooltip: 'More',
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: _forgetSite,
                child: const Text('Forget this site'),
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
                          ? error.message
                          : 'Something went wrong reading your access.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
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
                  const SizedBox(height: 24),
                  Text(
                    'FAMILY TREES',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final tree in summary.trees) _TreeCard(tree: tree),
                  for (final warning in summary.warnings) ...[
                    const SizedBox(height: 12),
                    MessagePanel.warning(warning),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                _initials(account.displayName),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.displayName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    account.email ?? account.username,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    version.isEmpty ? host : '$host · webtrees $version',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isAdministrator) ...[
                    const SizedBox(height: 8),
                    const _RoleChip(
                      label: 'Site administrator',
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
  const _TreeCard({required this.tree});

  final TreeAccess tree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.park_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tree.title ?? tree.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _describe(tree.role),
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
                  label: _roleName(tree.role),
                  icon: Icons.badge_outlined,
                ),
                if (tree.role.canEdit)
                  const _RoleChip(label: 'Can edit', icon: Icons.edit_outlined),
                if (tree.role.canModerate)
                  const _RoleChip(
                    label: 'Can approve changes',
                    icon: Icons.task_alt,
                  ),
                if (tree.role.canManage)
                  const _RoleChip(
                    label: 'Can manage',
                    icon: Icons.settings_outlined,
                  ),
                if (tree.myXref != null)
                  _RoleChip(
                    label: 'Linked to ${tree.myXref}',
                    icon: Icons.person_pin_circle_outlined,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _roleName(TreeRole role) => switch (role) {
    TreeRole.administrator => 'Administrator',
    TreeRole.manager => 'Manager',
    TreeRole.moderator => 'Moderator',
    TreeRole.editor => 'Editor',
    TreeRole.member => 'Member',
    TreeRole.memberOrVisitor => 'Read-only',
  };

  static String _describe(TreeRole role) => switch (role) {
    TreeRole.administrator =>
      'You administer this site, so you manage every tree in it.',
    TreeRole.manager => 'You can change this tree and its settings.',
    TreeRole.moderator =>
      'You can edit records and approve changes other people submit.',
    TreeRole.editor =>
      'You can edit records. Your changes wait for a moderator to approve them.',
    TreeRole.member => 'You can view this tree, including living relatives.',
    // Being unable to tell Member from Visitor is a genuine limit of reading a
    // stock webtrees site, so the interface says so rather than guessing.
    TreeRole.memberOrVisitor =>
      'You can view this tree. It is public, so the app cannot tell whether '
          'you are signed in as a member or seeing it as any visitor would.',
  };
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
