import '../../../shared/widgets/waveify_brand.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/platform/window_service.dart';
import '../auth_controller.dart';
import '../../../shared/widgets/glass.dart';

/// The sign-in / sign-up screen.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isRegistering = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authControllerProvider.notifier);

    if (_isRegistering) {
      await auth.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        username: _usernameController.text.trim(),
        displayName: _displayNameController.text.trim(),
      );
    } else {
      await auth.login(_emailController.text.trim(), _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final auth = ref.watch(authControllerProvider);
    final awaitingConfirmation =
        auth.errorCode == 'EMAIL_CONFIRMATION_REQUIRED';
    final messageColor = awaitingConfirmation
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Scaffold(
      body: AmbientBackground(
        child: Column(
          children: [
            if (WindowService.instance.isDesktop)
              const SizedBox(
                height: 32,
                child: WindowDragArea(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: WindowControls(),
                  ),
                ),
              ),
            Expanded(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: GlassPanel(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const WaveifyWordmark(stacked: true),
                              const SizedBox(height: 20),
                              Text(
                                _isRegistering
                                    ? t('login.auth_title_register')
                                    : t('login.auth_title_login'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isRegistering
                                    ? t('login.auth_subtitle_register')
                                    : t('login.auth_subtitle_login'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 28),

                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  labelText: t('login.label_email'),
                                  hintText: t('login.placeholder_email'),
                                  prefixIcon: const Icon(
                                    Icons.alternate_email_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  final v = value?.trim() ?? '';
                                  if (v.isEmpty) return t('login.label_email');
                                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(v)) {
                                    return t('login.placeholder_email');
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),

                              if (_isRegistering) ...[
                                TextFormField(
                                  controller: _usernameController,
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    labelText: t('login.label_username'),
                                    hintText: t('login.placeholder_username'),
                                    prefixIcon: const Icon(
                                      Icons.alternate_email_rounded,
                                    ),
                                    helperText: t('login.username_hint'),
                                  ),
                                  validator: (value) {
                                    final v = value?.trim() ?? '';
                                    if (v.isEmpty) {
                                      return t('login.label_username');
                                    }
                                    if (!RegExp(r'^[a-z0-9_]{3,30}$')
                                        .hasMatch(v)) {
                                      return t('login.username_hint');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _displayNameController,
                                  decoration: InputDecoration(
                                    labelText: t('login.label_display_name'),
                                    hintText: t(
                                      'login.placeholder_display_name',
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return t('login.label_display_name');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                              ],

                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: t('login.label_password'),
                                  hintText: _isRegistering
                                      ? t('login.placeholder_password_new')
                                      : t('login.placeholder_password'),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  final v = value ?? '';
                                  if (v.isEmpty) {
                                    return t('login.label_password');
                                  }
                                  if (_isRegistering && v.length < 8) {
                                    return t('login.placeholder_password_new');
                                  }
                                  return null;
                                },
                              ),

                              if (_isRegistering) ...[
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _confirmController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: t(
                                      'login.label_confirm_password',
                                    ),
                                    hintText: t('login.placeholder_confirm'),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value != _passwordController.text) {
                                      return t('login.placeholder_confirm');
                                    }
                                    return null;
                                  },
                                ),
                              ],

                              if (auth.error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: messageColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    awaitingConfirmation
                                        ? t('login.confirm_email_pending')
                                        : auth.error!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: messageColor,
                                    ),
                                  ),
                                ),
                              ],

                              ...[
                                const SizedBox(height: 20),
                                FilledButton.tonal(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () => ref
                                            .read(
                                              authControllerProvider.notifier,
                                            )
                                            .enterLocalMode(),
                                  child: Text(t('login.continue_local')),
                                ),
                              ],
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: auth.isLoading ? null : _submit,
                                child: auth.isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _isRegistering
                                            ? t('login.btn_create_account')
                                            : t('login.btn_sign_in'),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: auth.isLoading
                                    ? null
                                    : () => setState(
                                        () => _isRegistering = !_isRegistering,
                                      ),
                                child: Text(
                                  _isRegistering
                                      ? t('login.have_account')
                                      : t('login.no_account_action'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
