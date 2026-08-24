/// What the reader is told about their offline copy.
///
/// Deliberately quiet. `sync_eval.md` §11 #1 asks for two things and only two:
/// that a reader can always find out **where a figure came from** and **how
/// old it is**. Everything beyond that is noise on a screen whose job is to
/// find a person.
///
/// So the rules this file follows:
///
/// - **A download that is going fine says nothing.** It happens on wifi, in
///   the background, on first use. A progress bar for a thing nobody asked to
///   watch is an interruption.
/// - **A download that is waiting says so, once.** It is waiting on the
///   reader's network, and it is the only state where they might want to
///   overrule it — so it offers that and nothing else.
/// - **A copy that is being read from is stated where it matters**, which is
///   next to the results it produced, not in a banner over them.
library;

import 'package:flutter/material.dart';

import '../../data/local/tree_store.dart';
import '../../data/session_manager.dart';
import '../../l10n/app_localizations.dart';

/// Says the app is reading this device's copy, and what that costs.
///
/// Shown wherever a reader might otherwise think something is broken. It is a
/// *state*, not an error: nothing failed, there is simply no site to ask, and
/// the sentence under it names the three things that need one so nobody hunts
/// for a chart that will not come.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.session, this.onReconnect, super.key});

  final SessionManager session;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (!session.isOffline) return const SizedBox.shrink();

      final theme = Theme.of(context);
      final text = AppText.of(context);

      return Material(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.offlineBanner,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    Text(
                      text.offlineBannerWhy,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onReconnect != null)
                TextButton(
                  onPressed: onReconnect,
                  child: Text(text.offlineRetry),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A one-line notice above the search results, or nothing at all.
class SyncStatus extends StatelessWidget {
  const SyncStatus({required this.store, this.onRemove, super.key});

  final TreeStore store;

  /// Offered only where there is room for it — the account screen. Null here
  /// means the notice is informational.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final text = AppText.of(context);

      return switch (store.phase) {
        // Nothing to say: no copy is possible, or one is quietly filling, or
        // one is finished and being used. The reader learns the last of those
        // from the freshness line under the results and from diagnostics.
        SyncPhase.unavailable ||
        SyncPhase.offered ||
        SyncPhase.ready => const SizedBox.shrink(),

        SyncPhase.syncing => const _Filling(),

        SyncPhase.waitingForWifi => _Notice(
          icon: Icons.wifi_outlined,
          title: text.syncWaitingForWifi,
          detail: text.syncWaitingForWifiWhy,
          action: text.syncNow,
          onAction: () => store.catchUp(force: true),
        ),

        SyncPhase.failed => _Notice(
          icon: Icons.cloud_off_outlined,
          title: text.syncFailed,
          detail: text.syncFailedWhy,
          action: text.syncRetry,
          onAction: () => store.catchUp(force: true),
        ),
      };
    },
  );
}

/// A hairline, because a first sync is thirty seconds and the reader did not
/// ask to watch it.
class _Filling extends StatelessWidget {
  const _Filling();

  @override
  Widget build(BuildContext context) =>
      const LinearProgressIndicator(minHeight: 2);
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

/// "Read from this device, updated an hour ago."
///
/// The other half of §11 #1, and the half that actually answers *"is it stale
/// or is it wrong?"* — shown under a list the store produced, in the smallest
/// type on the screen, because it is an answer to a question most readers will
/// never ask and some will need badly.
class SyncFreshness extends StatelessWidget {
  const SyncFreshness({required this.store, super.key});

  final TreeStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final syncedAt = store.syncedAt;
      if (!store.isReadable || syncedAt == null) return const SizedBox.shrink();

      final theme = Theme.of(context);
      final text = AppText.of(context);

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          text.syncFromStoreNotice(relativeTime(syncedAt, text)),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
}

/// How long ago, in the coarsest unit that is still true.
///
/// Coarse on purpose: the reader is deciding whether to trust a figure, and
/// "an hour ago" answers that where a timestamp makes them do the arithmetic.
/// Nothing finer than a minute, and nothing older than a day is worth counting
/// in days beyond a few — but the sync runs on every load, so a copy older
/// than that means the app has not been opened, which is exactly when saying
/// so matters most.
String relativeTime(DateTime when, AppText text, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(when);

  if (elapsed.inMinutes < 1) return text.syncJustNow;
  if (elapsed.inMinutes < 60) return text.syncMinutesAgo(elapsed.inMinutes);
  if (elapsed.inHours < 24) return text.syncHoursAgo(elapsed.inHours);
  return text.syncDaysAgo(elapsed.inDays);
}
