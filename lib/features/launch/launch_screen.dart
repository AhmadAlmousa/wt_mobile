import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/session_manager.dart';
import '../../l10n/app_localizations.dart';

/// The first thing the app shows, and usually the only thing it shows before
/// the family tree itself.
///
/// Someone who has already set the app up should not be asked for the address
/// again, nor made to pick their own site out of a list of one. So the launch
/// screen signs them back in to the site they used last and gets out of the
/// way; only when there is nothing to resume does it hand over to the connect
/// screen.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({
    required this.session,
    required this.onNothingToResume,
    required this.onOfflineInstead,
    super.key,
  });

  final SessionManager session;

  /// Called when no stored site could be opened, so the user has to be asked.
  final VoidCallback onNothingToResume;

  /// Called when the site could not be *reached* and this device holds a copy.
  ///
  /// A different outcome from [onNothingToResume] and it has to be, because
  /// they look identical from inside `resume()`: one means "we do not know who
  /// you are", the other means "we know exactly who you are and the train went
  /// into a tunnel". Showing a sign-in form for the second — with `login
  /// failed` on it — is what the first offline test of 0.21.0 ran into.
  ///
  /// Returns whether a copy was actually opened, because only the shell can
  /// answer that: it owns the store.
  final Future<bool> Function() onOfflineInstead;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  @override
  void initState() {
    super.initState();
    _resume();
  }

  Future<void> _resume() async {
    // A success needs no navigation here: the router's redirect sees the
    // session change and moves the app on by itself.
    final resumed = await widget.session.resumeLastUsed();
    if (resumed || !mounted) return;

    // The site was not reachable rather than unwilling. If this device holds
    // a copy, that is not a failure at all — it is the case the copy exists
    // for.
    if (widget.session.failedForLackOfNetwork &&
        await widget.onOfflineInstead()) {
      return;
    }

    if (mounted) widget.onNothingToResume();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(
                  AppTheme.shapeExtraExtraLarge,
                ),
              ),
              child: Icon(
                Icons.account_tree_outlined,
                size: 44,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text(
              AppText.of(context).signingIn,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
