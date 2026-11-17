import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/discord_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_panel.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../../customization/customization_settings.dart';
import '../../overlay/overlay_service.dart';
import '../../player/player_controller.dart';
import '../../shortcuts/shortcuts_settings_page.dart';

/// The settings screen.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final player = ref.read(playerControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Text(
          t('settings.title'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t('settings.subtitle'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTertiary,
          ),
        ),
        const SizedBox(height: 24),

        _GroupTitle(t('settings.tabs.appearance')),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                title: Text(t('settings.tabs.appearance')),
                trailing: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: const Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: const Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: const Text('Dark'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) controller.setThemeMode(mode);
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(t('settings.tabs.customization')),
                subtitle: Text(settings.accentVariant.id),
                trailing: DropdownButton<AccentVariant>(
                  value: settings.accentVariant,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final variant in AccentVariant.values)
                      DropdownMenuItem(value: variant, child: Text(variant.id)),
                  ],
                  onChanged: (variant) {
                    if (variant != null) controller.setAccent(variant);
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Language'),
                trailing: DropdownButton<String>(
                  value: settings.locale,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'it', child: Text('Italiano')),
                    DropdownMenuItem(value: 'ru', child: Text('Русский')),
                    DropdownMenuItem(value: 'uk', child: Text('Українська')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                    DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                    DropdownMenuItem(value: 'pl', child: Text('Polski')),
                    DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                    DropdownMenuItem(value: 'pt', child: Text('Português')),
                  ],
                  onChanged: (locale) {
                    if (locale != null) controller.setLocale(locale);
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.tabs.playback')),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                value: settings.autoplaySimilar,
                title: Text(t('player.autoplay_radio')),
                onChanged: (value) {
                  controller.setAutoplaySimilar(value);
                  player.setAutoplaySimilar(value);
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(t('player.speed_pitch')),
                subtitle: Text(
                  '${settings.playbackRate.toStringAsFixed(2)}x · '
                  '${settings.pitchSemitones.toStringAsFixed(1)} st',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/player'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.tabs.discord')),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                value: settings.discordEnabled,
                title: Text(t('settings.tabs.discord')),
                subtitle: Text(
                  t(
                    DiscordService.instance.isSupported
                        ? 'settings.discord.desc'
                        : 'settings.discord.unsupported',
                  ),
                ),
                onChanged: DiscordService.instance.isSupported
                    ? (value) => controller.setDiscordEnabled(value)
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.discordShowArtwork,
                title: Text(t('settings.discord.show_artwork')),
                onChanged:
                    settings.discordEnabled &&
                        DiscordService.instance.isSupported
                    ? (value) => controller.setDiscordShowArtwork(value)
                    : null,
              ),
              SwitchListTile(
                value: settings.discordShowArtistImage,
                title: Text(t('settings.discord.show_artist_image')),
                onChanged:
                    settings.discordEnabled &&
                        DiscordService.instance.isSupported
                    ? (value) => controller.setDiscordShowArtistImage(value)
                    : null,
              ),
              SwitchListTile(
                value: settings.discordShowTime,
                title: Text(t('settings.discord.show_time')),
                onChanged:
                    settings.discordEnabled &&
                        DiscordService.instance.isSupported
                    ? (value) => controller.setDiscordShowTime(value)
                    : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.tabs.customization')),
        const CustomizationSettings(),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.tabs.shortcuts')),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.keyboard_rounded),
                title: Text(t('settings.shortcuts.title')),
                subtitle: Text(t('settings.shortcuts.desc')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const ShortcutsSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.overlay.enabled.title')),
        _OverlaySettings(),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.tabs.account')),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(auth.user?.displayLabel ?? t('common.account')),
                subtitle: auth.user?.email == null
                    ? null
                    : Text(auth.user!.email!),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.logout_rounded,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  t('common.sign_out'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () async {
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _GroupTitle(t('settings.tabs.about')),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(t('common.app.name')),
              ),
              const Divider(height: 1),
              const UpdatePanel(),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// The settings of the overlay window.
///
/// The overlay is the mini player that stays above the other windows; it is
/// opened with the system shortcut or with the button of the player.
class _OverlaySettings extends ConsumerWidget {
  const _OverlaySettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final overlay = ref.watch(overlayServiceProvider);

    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            value: overlay.isOpen,
            title: Text(t('settings.overlay.enabled.title')),
            subtitle: Text(t('settings.overlay.enabled.description')),
            onChanged: (value) =>
                ref.read(overlayServiceProvider.notifier).toggle(),
          ),
          ListTile(
            title: Text(t('settings.overlay.position.title')),
            subtitle: Text(t('settings.overlay.position.description')),
            trailing: DropdownButton<String>(
              value: settings.overlayPosition,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 'topLeft',
                  child: Text(t('settings.overlay.position.top_left')),
                ),
                DropdownMenuItem(
                  value: 'topCenter',
                  child: Text(t('settings.overlay.position.top_center')),
                ),
                DropdownMenuItem(
                  value: 'topRight',
                  child: Text(t('settings.overlay.position.top_right')),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                controller.setOverlayPosition(value);
              },
            ),
          ),
          SwitchListTile(
            value: settings.overlayAlwaysOnTop,
            title: Text(t('settings.overlay.always_on_top.title')),
            subtitle: Text(t('settings.overlay.always_on_top.description')),
            onChanged: controller.setOverlayAlwaysOnTop,
          ),
        ],
      ),
    );
  }
}
