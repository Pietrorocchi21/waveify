import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';
import 'remote_controller.dart';

/// The control of the other device: what it is playing and the commands.
class RemotePage extends ConsumerStatefulWidget {
  const RemotePage({super.key});

  @override
  ConsumerState<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends ConsumerState<RemotePage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final remote = ref.watch(remoteControllerProvider);
    final controller = ref.read(remoteControllerProvider.notifier);

    if (!remote.isConfigured) {
      return EmptyState(
        icon: Icons.devices_other_rounded,
        title: t('remote.not_configured_title'),
        description: t('remote.not_configured_desc'),
      );
    }

    if (!remote.isAuthenticated) {
      return _SignInForm(
        emailController: _emailController,
        passwordController: _passwordController,
        isConnecting: remote.isConnecting,
        error: remote.error,
        onSubmit: () => controller.connect(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ),
      );
    }

    final other = remote.remote;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('remote.playing_on'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.textTertiary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                other?.trackTitle ?? t('player.nothing_playing'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                other?.trackArtist ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTertiary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                [
                  other?.deviceName ?? '',
                  if (other != null)
                    other.isPlaying
                        ? t('remote.playing')
                        : t('remote.paused'),
                ].join(' • '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    controller.sendCommand(RemoteCommand.previous),
                icon: const Icon(Icons.skip_previous_rounded),
                label: Text(t('player.previous')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => controller.sendCommand(
                  other?.isPlaying == true
                      ? RemoteCommand.pause
                      : RemoteCommand.play,
                ),
                icon: Icon(
                  other?.isPlaying == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  other?.isPlaying == true
                      ? t('common.pause')
                      : t('common.play'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => controller.sendCommand(RemoteCommand.next),
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(t('player.next')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: controller.disconnect,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(t('common.sign_out')),
          ),
        ),
      ],
    );
  }
}

class _SignInForm extends ConsumerWidget {
  const _SignInForm({
    required this.emailController,
    required this.passwordController,
    required this.isConnecting,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isConnecting;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.devices_other_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                t('remote.title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t('remote.desc'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTertiary,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: t('login.label_email'),
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t('login.label_password'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
                onSubmitted: (_) => onSubmit(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: isConnecting ? null : onSubmit,
                child: isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t('remote.connect')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
