import 'package:flutter/material.dart';

import '../../data/session_manager.dart';
import '../../domain/instance.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';

/// Collects a username and password for the connected site.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.session,
    required this.onSignedIn,
    required this.onChangeSite,
    super.key,
  });

  final SessionManager session;
  final VoidCallback onSignedIn;
  final VoidCallback onChangeSite;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  bool _obscured = true;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _username.text = widget.session.connection?.username ?? '';
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    final ok = await widget.session.signIn(
      _username.text.trim(),
      _password.text,
      remember: _remember,
    );
    if (ok && mounted) widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(text.signIn),
        leading: BackButton(onPressed: widget.onChangeSite),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) {
            final session = widget.session;
            final instance = session.instance;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (instance != null) _SiteCard(instance: instance),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _username,
                          enabled: !session.isBusy,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: text.usernameOrEmail,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? text.usernameRequired
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !session.isBusy,
                          obscureText: _obscured,
                          textInputAction: TextInputAction.go,
                          decoration: InputDecoration(
                            labelText: text.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscured
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              tooltip: _obscured
                                  ? text.showPassword
                                  : text.hidePassword,
                              onPressed: () =>
                                  setState(() => _obscured = !_obscured),
                            ),
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? text.passwordRequired
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 8),
                        _RememberToggle(
                          value: _remember,
                          // Without a keystore the password cannot be kept, so
                          // the control is disabled and says why rather than
                          // silently failing to remember.
                          canRemember: session.canRemember,
                          isGated: session.isGated,
                          enabled: !session.isBusy,
                          onChanged: (value) =>
                              setState(() => _remember = value),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: session.isBusy ? null : _submit,
                          child: session.isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(text.signIn),
                        ),
                        if (session.error != null) ...[
                          const SizedBox(height: 20),
                          MessagePanel.error(session.error!.localized(text)),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          text.passwordScopeNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
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

/// Confirms which site the credentials will be sent to.
class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.instance});

  final WebtreesInstance instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final insecure = instance.url.base.scheme != 'https';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              insecure ? Icons.lock_open_outlined : Icons.lock_outline,
              color: insecure ? theme.colorScheme.error : null,
            ),
            title: Text(
              instance.url.base.host,
              textDirection: TextDirection.ltr,
            ),
            subtitle: Text(
              instance.version.isEmpty
                  ? text.webtrees
                  : text.webtreesVersion(instance.version),
            ),
          ),
        ),
        if (insecure) ...[
          const SizedBox(height: 12),
          MessagePanel.warning(text.insecureSiteWarning),
        ],
        if (instance.health == ServerHealth.degraded) ...[
          const SizedBox(height: 12),
          MessagePanel.warning(text.degradedServerWarning),
        ],
        for (final warning in instance.warnings) ...[
          const SizedBox(height: 12),
          MessagePanel.warning(warning.localized(text)),
        ],
      ],
    );
  }
}

/// The "stay signed in" control, which explains itself when unavailable.
class _RememberToggle extends StatelessWidget {
  const _RememberToggle({
    required this.value,
    required this.canRemember,
    required this.isGated,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool canRemember;

  /// Whether unlocking the stored password actually demands a fingerprint,
  /// face or device passcode.
  final bool isGated;

  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// States exactly what the device will and will not do, because the
  /// protection differs by platform and overstating it would be a lie the user
  /// cannot check.
  String _explanation(AppText text) {
    if (!canRemember) return text.rememberUnavailable;
    if (!isGated) return text.rememberUngated;
    return text.rememberGated;
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return SwitchListTile.adaptive(
      value: canRemember && value,
      onChanged: (canRemember && enabled) ? onChanged : null,
      contentPadding: EdgeInsets.zero,
      title: Text(text.staySignedIn),
      subtitle: Text(_explanation(text)),
    );
  }
}
