import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/updater_service.dart';
import '../../../core/providers/app_providers.dart';

/// A quiet notice for updates discovered by the periodic startup check.
class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updater = UpdaterService.instance;
    final t = ref.watch(translatorProvider);
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        if (updater.state != UpdateState.available &&
            updater.state != UpdateState.downloaded) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('settings.updater.available_version', {
                    'version': updater.version ?? '',
                  }),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => context.go('/settings'),
                child: Text(t('settings.updater.install')),
              ),
            ],
          ),
        );
      },
    );
  }
}
