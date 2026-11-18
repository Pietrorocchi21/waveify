import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';

import 'customization_controller.dart';

/// The customization of the interface: the wallpaper and the decoration of
/// the blocks.
class CustomizationSettings extends ConsumerWidget {
  const CustomizationSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final customization = ref.watch(customizationControllerProvider);
    final controller = ref.read(customizationControllerProvider.notifier);

    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (Platform.isWindows)
            SwitchListTile(
              value: ref.watch(settingsProvider.select((s) => s.videoBackdrop)),
              title: Text(t('settings.customization.video_backdrop')),
              subtitle: Text(t('settings.customization.video_backdrop_desc')),
              onChanged: (value) {
                final settings = ref.read(settingsProvider);
                ref
                    .read(settingsProvider.notifier)
                    .update(settings.copyWith(videoBackdrop: value));
              },
            ),
          ListTile(
            leading: const Icon(Icons.wallpaper_rounded),
            title: Text(t('settings.customization.wallpaper')),
            subtitle: Text(
              customization.hasWallpaper
                  ? t('settings.customization.wallpaper_set')
                  : t('settings.customization.wallpaper_none'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (customization.hasWallpaper)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: controller.clearWallpaper,
                  ),
                IconButton(
                  icon: const Icon(Icons.image_search_rounded, size: 18),
                  onPressed: controller.pickWallpaper,
                ),
              ],
            ),
          ),
          if (customization.hasWallpaper) ...[
            const Divider(height: 1),
            _SliderRow(
              label: t('settings.customization.blur'),
              value: customization.wallpaperBlur,
              min: 0,
              max: 40,
              onChanged: (value) => controller.setWallpaper(blur: value),
            ),
            const Divider(height: 1),
            _SliderRow(
              label: t('settings.customization.dim'),
              value: customization.wallpaperDim,
              min: 0,
              max: 85,
              onChanged: (value) => controller.setWallpaper(dim: value),
            ),
          ],
          const Divider(height: 1),
          _BlockRow(block: CustomizationBlock.sidebar),
          const Divider(height: 1),
          _BlockRow(block: CustomizationBlock.contentView),
          const Divider(height: 1),
          _BlockRow(block: CustomizationBlock.miniplayer),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('settings.customization.glass_preset'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTertiary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => controller.setBlock(
                    CustomizationBlock.sidebar,
                    opacity: BlockCustomization.glass.opacity,
                    blur: BlockCustomization.glass.blur,
                    dim: BlockCustomization.glass.dim,
                  ),
                  icon: const Icon(Icons.blur_on_rounded, size: 16),
                  label: Text(t('settings.customization.apply_to_all')),
                ),
                TextButton(
                  onPressed: controller.resetAll,
                  child: Text(t('settings.reset_defaults')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The decoration of one block.
class _BlockRow extends ConsumerWidget {
  const _BlockRow({required this.block});

  final CustomizationBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final customization = ref.watch(customizationControllerProvider);
    final controller = ref.read(customizationControllerProvider.notifier);
    final config = customization.blockFor(block);

    final label = switch (block) {
      CustomizationBlock.sidebar => t('settings.customization.sidebar'),
      CustomizationBlock.contentView => t('settings.customization.content'),
      CustomizationBlock.miniplayer => t('settings.customization.miniplayer'),
    };

    return ExpansionTile(
      title: Text(label),
      subtitle: Text(
        '${t('settings.customization.opacity')}: ${config.opacity} · '
        '${t('settings.customization.blur')}: ${config.blur}',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).textTertiary),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _SliderRow(
          label: t('settings.customization.opacity'),
          value: config.opacity,
          min: 25,
          max: 100,
          onChanged: (value) => controller.setBlock(block, opacity: value),
        ),
        _SliderRow(
          label: t('settings.customization.blur'),
          value: config.blur,
          min: 0,
          max: 40,
          onChanged: (value) => controller.setBlock(block, blur: value),
        ),
        _SliderRow(
          label: t('settings.customization.dim'),
          value: config.dim,
          min: 0,
          max: 85,
          onChanged: (value) => controller.setBlock(block, dim: value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => controller.applyToAll(block),
                child: Text(t('settings.customization.apply_to_all')),
              ),
              TextButton(
                onPressed: () => controller.resetBlock(block),
                child: Text(t('settings.reset_defaults')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled slider.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value',
              onChanged: (next) => onChanged(next.round()),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
