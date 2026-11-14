import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'connectivity_controller.dart';

/// The wall that replaces the app when the connection is broken.
///
/// Port of `src/features/connectivity/ui/ConnectivityWall.tsx`.
class ConnectivityWall extends ConsumerWidget {
  const ConnectivityWall({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final connectivity = ref.watch(connectivityControllerProvider);
    final controller = ref.read(connectivityControllerProvider.notifier);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    connectivity.isServerOutage
                        ? Icons.cloud_off_rounded
                        : Icons.wifi_off_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    connectivity.isServerOutage
                        ? t('connectivity.wall_title_server')
                        : t('connectivity.wall_title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    connectivity.isServerOutage
                        ? t('connectivity.wall_subtitle_server')
                        : t('connectivity.wall_subtitle'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (connectivity.checks.isNotEmpty) ...[
                    Text(
                      t('connectivity.checks_title'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final check in connectivity.checks)
                      _CheckRow(check: check),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: connectivity.isRunning
                              ? null
                              : controller.retry,
                          icon: connectivity.isRunning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            connectivity.isRunning
                                ? t('connectivity.retrying')
                                : t('connectivity.retry'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: controller.dismiss,
                        child: Text(t('common.close')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final ConnectivityCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (check.status) {
      'ok' => (Icons.check_circle_rounded, Colors.green),
      'fail' => (Icons.error_rounded, theme.colorScheme.error),
      _ => (Icons.remove_circle_outline_rounded, theme.textTertiary),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              check.id,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              check.detail ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
          ),
          if (check.latencyMs != null)
            Text(
              '${check.latencyMs} ms',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}
