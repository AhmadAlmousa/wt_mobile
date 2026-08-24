import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/credential_store.dart';
import '../../data/diagnostics.dart';
import '../../data/session_manager.dart';
import '../../data/settings_store.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/settings_sheet.dart';

/// Asks which webtrees site to use, and identifies it.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    required this.session,
    required this.settings,
    required this.onConnected,
    required this.onReadOffline,
    required this.onSignedIn,
    super.key,
  });

  final SessionManager session;
  final SettingsStore settings;

  /// Called once the site has been identified and is ready for sign-in.
  final VoidCallback onConnected;

  /// Opens this device's copy instead, when the address cannot be reached.
  ///
  /// The last of the three doors into the app (§7 bug 56): a reader who never
  /// saved a password lands *here* rather than on the sign-in form, so without
  /// this one they would still be looking at a screen they cannot get past
  /// while a complete copy sits on the device.
  final Future<bool> Function() onReadOffline;

  /// Called when a stored password signed the user straight back in.
  final VoidCallback onSignedIn;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _address = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  List<SavedConnection> _saved = const [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final saved = await widget.session.savedConnections();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      // The address of the site used last, ready to go. Someone who has been
      // here before is almost always coming back to the same site, and this
      // screen is only reached at all when it could not be opened outright.
      if (_address.text.isEmpty && saved.isNotEmpty) {
        _address.text = saved.first.base.toString();
      }
    });
  }

  Future<void> _connect(String address) async {
    if (await widget.session.connect(address) && mounted) {
      widget.onConnected();
      return;
    }
    // Nothing answered. If this device holds a copy, that is what it is for.
    if (mounted && widget.session.failedForLackOfNetwork) {
      await widget.onReadOffline();
    }
  }

  /// Reopens a site used before, signing in outright when its password was
  /// kept and falling back to the sign-in form when it was not.
  Future<void> _reopen(SavedConnection saved) async {
    _address.text = saved.base.toString();

    if (await widget.session.hasStoredPassword(saved)) {
      if (await widget.session.resume(saved)) {
        if (mounted) widget.onSignedIn();
        return;
      }
      // Declined the unlock, or the password had stopped working. Either way
      // the sign-in form is the way forward, so fall through to it.
      if (!mounted) return;
      if (widget.session.isSignedIn) return;
      if (widget.session.instance != null) {
        widget.onConnected();
        return;
      }
    }

    await _connect(_address.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        // Offered before sign-in on purpose: someone who reads Arabic should
        // not have to work through an English form to find the switch.
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: text.settings,
            onPressed: () => SettingsSheet.show(
              context,
              widget.settings,
              // Before sign-in there is no module answer yet, and that is
              // exactly when somebody most wants to see what the app made of
              // the address they typed.
              diagnostics: Diagnostics.of(widget.session),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) {
            final session = widget.session;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Emblem(),
                      const SizedBox(height: 24),
                      Text(
                        text.connectTitle,
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        text.connectSubtitle,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      Form(
                        key: _form,
                        child: TextFormField(
                          controller: _address,
                          enabled: !session.isBusy,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          decoration: InputDecoration(
                            labelText: text.siteAddress,
                            hintText: text.siteAddressHint,
                            prefixIcon: const Icon(Icons.language),
                            // The address is always Latin, whichever way the
                            // rest of the interface reads.
                            hintTextDirection: TextDirection.ltr,
                          ),
                          textDirection: TextDirection.ltr,
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? text.siteAddressRequired
                              : null,
                          onFieldSubmitted: (value) {
                            if (_form.currentState!.validate()) {
                              _connect(value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: session.isBusy
                            ? null
                            : () {
                                if (_form.currentState!.validate()) {
                                  _connect(_address.text);
                                }
                              },
                        child: session.isBusy
                            ? _ButtonSpinner(label: text.connecting)
                            : Text(text.connect),
                      ),
                      if (session.error != null) ...[
                        const SizedBox(height: 20),
                        MessagePanel.error(session.error!.localized(text)),
                      ],
                      if (_saved.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        _SavedConnections(
                          connections: _saved,
                          label: text.recentSites,
                          enabled: !session.isBusy,
                          onSelected: _reopen,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Recently used sites, offered as a shortcut.
class _SavedConnections extends StatelessWidget {
  const _SavedConnections({
    required this.connections,
    required this.label,
    required this.enabled,
    required this.onSelected,
  });

  final List<SavedConnection> connections;
  final String label;
  final bool enabled;
  final ValueChanged<SavedConnection> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 10),
        for (final saved in connections)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              enabled: enabled,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.tertiaryContainer,
                foregroundColor: theme.colorScheme.onTertiaryContainer,
                child: const Icon(Icons.history, size: 20),
              ),
              // The host is Latin even in an Arabic interface, but the row
              // itself still mirrors, so only the text is pinned.
              title: Text(saved.base.host, textDirection: TextDirection.ltr),
              subtitle: Text(
                saved.displayName == null
                    ? saved.username
                    : '${saved.displayName} · ${saved.username}',
              ),
              // Mirrors with the layout, so it points "onward" in both
              // directions rather than always to the right.
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: enabled ? () => onSelected(saved) : null,
            ),
          ),
      ],
    );
  }
}

/// The app's mark: a rounded, layered badge in the Expressive idiom.
class _Emblem extends StatelessWidget {
  const _Emblem();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(AppTheme.shapeExtraExtraLarge),
        ),
        child: Icon(
          Icons.account_tree_outlined,
          size: 44,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Text(label),
    ],
  );
}
