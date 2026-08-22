import 'package:flutter/material.dart';

import '../../data/credential_store.dart';
import '../../data/session_manager.dart';
import '../shared/message_panel.dart';

/// Asks which webtrees site to use, and identifies it.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    required this.session,
    required this.onConnected,
    required this.onSignedIn,
    super.key,
  });

  final SessionManager session;

  /// Called once the site has been identified and is ready for sign-in.
  final VoidCallback onConnected;

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
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _connect(String address) async {
    if (await widget.session.connect(address) && mounted) {
      widget.onConnected();
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

    return Scaffold(
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
                      Icon(
                        Icons.account_tree_outlined,
                        size: 56,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Connect to your family tree',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the address of your webtrees site.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      Form(
                        key: _form,
                        child: TextFormField(
                          controller: _address,
                          enabled: !session.isBusy,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          decoration: const InputDecoration(
                            labelText: 'Site address',
                            hintText: 'tree.example.com',
                            prefixIcon: Icon(Icons.language),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'An address is needed, for example '
                                    'tree.example.com'
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
                            ? const _ButtonSpinner(label: 'Connecting…')
                            : const Text('Connect'),
                      ),
                      if (session.error != null) ...[
                        const SizedBox(height: 20),
                        MessagePanel.error(session.error!.message),
                      ],
                      if (_saved.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        _SavedConnections(
                          connections: _saved,
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
    required this.enabled,
    required this.onSelected,
  });

  final List<SavedConnection> connections;
  final bool enabled;
  final ValueChanged<SavedConnection> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'RECENT',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final saved in connections)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              enabled: enabled,
              leading: const Icon(Icons.history),
              title: Text(saved.base.host),
              subtitle: Text(
                saved.displayName == null
                    ? saved.username
                    : '${saved.displayName} · ${saved.username}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: enabled ? () => onSelected(saved) : null,
            ),
          ),
      ],
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
