import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../data/access_probe.dart';
import '../../data/diagnostics.dart';
import '../../data/local/tree_store.dart';
import '../../data/module/module_api.dart';
import '../../data/session_manager.dart';
import '../../data/settings_store.dart';
import '../../domain/access.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/settings_sheet.dart';
import '../sync/sync_status.dart';

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
    required this.onOnlyTree,
    this.capabilities,
    this.onAccessSummary,
    this.treeStore,
    this.offlineSummary,
    super.key,
  });

  final SessionManager session;
  final SettingsStore settings;

  /// What this site's optional module answered, for the diagnostics screen.
  ///
  /// Only the shell knows it — it probes once per sign-in — and the shell is
  /// not on screen, so it is handed down to the one screen that can show it.
  final ModuleCapabilities? capabilities;
  final VoidCallback onSignedOut;

  /// Opens a tree for browsing. Reading is available to every role, so this is
  /// offered whatever the badges on the card say.
  ///
  /// Carries the tree's own title as well as its name, because the name is
  /// the identifier webtrees routes on — often something like `main` — and
  /// the title is what the family calls it.
  final void Function(String name, String? title) onBrowseTree;

  /// Called when the account can reach exactly one tree.
  ///
  /// A list of one is not a choice, so the app goes straight in. The screen
  /// itself stays reachable — it doubles as the diagnostics view — which is
  /// why this is a separate callback the shell can decline to act on.
  final void Function(String name, String? title) onOnlyTree;

  /// Hands the summary up to the shell, which is the only place that can act
  /// on it.
  ///
  /// It carries the reader's **role in each tree**, which is half of what
  /// stamps a local store (`sync_eval.md` §6): a copy filled for a member must
  /// never be answered for somebody who has since been demoted to a visitor.
  /// This screen is the one place the roles are read, and it runs after every
  /// sign-in, so it is also where a *changed* role is first knowable.
  final void Function(AccessSummary summary)? onAccessSummary;

  /// This device's copy, for the diagnostics screen and for the control that
  /// removes it. Null in tests that do not care.
  final TreeStore? treeStore;

  /// What the store's own stamp says about the reader, when there is no site
  /// to ask.
  ///
  /// Non-null puts this screen in offline mode: it states the account and the
  /// trees this device holds, and does not probe. The row that records whose
  /// copy a store is carries the account and the role, which is exactly what
  /// a probe would have gone to the site for.
  final AccessSummary? offlineSummary;

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
    final offline = widget.offlineSummary;
    if (offline != null) {
      setState(() => _summary = Future.value(offline));
      return;
    }

    setState(() {
      _summary = widget.session
          .withSession(() => AccessProbe(widget.session.client).describe())
          .then((summary) async {
            // The real name is only discoverable here, so this is the one
            // chance to label the connection for next time.
            await widget.session.noteAccountName(summary.account.realName);
            widget.onAccessSummary?.call(summary);
            if (summary.trees.length == 1 && mounted) {
              final only = summary.trees.single;
              widget.onOnlyTree(only.name, only.title);
            }
            return summary;
          });
    });
  }

  /// Deletes this device's copy without signing out.
  ///
  /// Worth its own control rather than only happening at sign-out: a reader
  /// who has thought about what is on their phone should be able to act on it
  /// without also losing their session. `sync_eval.md` §6 is about the app not
  /// keeping more than it should; this is the reader's half of that.
  Future<void> _removeOfflineCopy() async {
    final text = AppText.of(context);
    await widget.treeStore?.destroy();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.syncRemoved)));
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
            onPressed: () => SettingsSheet.show(
              context,
              widget.settings,
              diagnostics: Diagnostics.of(
                widget.session,
                capabilities: widget.capabilities,
                // The third answer. A reader wondering why a figure looks
                // wrong has to be told it came from a copy, and when that
                // copy was taken (`sync_eval.md` §11 #1).
                hasStore: widget.treeStore?.isReadable ?? false,
                syncedAt: widget.treeStore?.syncedAt,
                storedPeople: widget.treeStore?.people ?? 0,
              ),
            ),
          ),
          // Signing out lives in the menu rather than on the bar: this screen
          // is now reached with a back button in the leading slot, and five
          // controls left no room for the title.
          PopupMenuButton<void>(
            tooltip: text.more,
            itemBuilder: (context) => [
              PopupMenuItem<void>(onTap: _signOut, child: Text(text.signOut)),
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
                      onOpen: () => widget.onBrowseTree(tree.name, tree.title),
                    ),
                  if (widget.treeStore case final store?) ...[
                    const SizedBox(height: 28),
                    _OfflineCopy(store: store, onRemove: _removeOfflineCopy),
                  ],
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

/// What is kept on this device, and a way to stop keeping it.
///
/// Shown only once there is something to say. A reader who never left wifi and
/// never thought about it sees one line telling them the tree is readable
/// offline; a reader who wants it gone has the control next to it.
class _OfflineCopy extends StatelessWidget {
  const _OfflineCopy({required this.store, required this.onRemove});

  final TreeStore store;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (store.phase == SyncPhase.unavailable) return const SizedBox.shrink();

      final theme = Theme.of(context);
      final text = AppText.of(context);
      final syncedAt = store.syncedAt;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.syncTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (store.phase) {
                    SyncPhase.ready => text.syncReady,
                    SyncPhase.syncing => text.syncSyncing,
                    SyncPhase.waitingForWifi => text.syncWaitingForWifi,
                    SyncPhase.failed => text.syncFailed,
                    SyncPhase.offered || SyncPhase.unavailable => text.syncWhy,
                  }, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    store.phase == SyncPhase.ready && syncedAt != null
                        ? '${text.diagnosticsStorePeople(store.people)} · '
                              '${text.diagnosticsStoreSynced(relativeTime(syncedAt, text))}'
                        : text.syncWhy,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: store.people > 0 ? onRemove : null,
                      child: Text(text.syncRemove),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
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
