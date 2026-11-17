import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/updater_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../player/player_controller.dart';

/// Listens throughout download and hands installation explicitly to the user.
class UpdatePanel extends ConsumerWidget {
  const UpdatePanel({super.key, this.service});
  final UpdaterService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updater = service ?? UpdaterService.instance;
    final t = ref.watch(translatorProvider);
    Future<void> install() async {
      try {
        await ref.read(playerControllerProvider.notifier).prepareForUpdate();
        await updater.install();
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('settings.updater.error')} $error')),
        );
      }
    }

    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final message = switch (updater.state) {
          UpdateState.idle => null,
          UpdateState.checking => t('settings.updater.checking'),
          UpdateState.available =>
            updater.version == null
                ? t('settings.updater.available')
                : t('settings.updater.available_version', {
                    'version': updater.version!,
                  }),
          UpdateState.upToDate => t('settings.updater.up_to_date'),
          UpdateState.downloading =>
            '${t('settings.updater.downloading')} ${(updater.progress * 100).floor()}%',
          UpdateState.downloaded => t('settings.updater.ready'),
          UpdateState.installing => t('settings.updater.installing'),
          UpdateState.error =>
            '${t('settings.updater.error')} ${updater.error ?? ''}',
          UpdateState.unsupported => t('settings.updater.unsupported'),
        };
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t('common.app.name')} ${updater.currentVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (message != null) Text(message),
              if (updater.notes?.isNotEmpty == true &&
                  [
                    UpdateState.available,
                    UpdateState.downloaded,
                  ].contains(updater.state))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(updater.notes!),
                ),
              if (updater.state == UpdateState.downloading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(value: updater.progress),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.system_update_alt_rounded),
                    label: Text(t('settings.updater.check')),
                    onPressed: updater.busy
                        ? null
                        : () {
                            updater.check();
                          },
                  ),
                  if (updater.state == UpdateState.available)
                    FilledButton(
                      onPressed: () {
                        updater.isAndroid ? install() : updater.download();
                      },
                      child: Text(
                        t(
                          updater.isAndroid
                              ? 'settings.updater.install'
                              : 'settings.updater.download',
                        ),
                      ),
                    ),
                  if (updater.state == UpdateState.downloaded)
                    FilledButton(
                      onPressed: () {
                        install();
                      },
                      child: Text(t('settings.updater.restart_install')),
                    ),
                  if (updater.state == UpdateState.unsupported)
                    TextButton(
                      onPressed: updater.openReleasePage,
                      child: Text(t('settings.updater.releases')),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
