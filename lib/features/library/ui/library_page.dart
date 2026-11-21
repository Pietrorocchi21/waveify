import '../../../core/cloud/cloud_config.dart';

import 'package:waveify/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/glass.dart';
import '../../player/player_controller.dart';
import '../library_controller.dart';
import '../device_library.dart';

/// The user's library: liked songs, playlists and saved collections.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: CloudConfig.isConfigured ? 6 : 5,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryControllerProvider.notifier)
        ..loadLikedTracks()
        ..loadPlaylists()
        ..loadSavedCollections();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final library = ref.watch(libraryControllerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceXxl,
            DesignTokens.spaceXxxl,
            DesignTokens.spaceXxl,
            DesignTokens.spaceMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('library.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.textDisplaySmall.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const ImportAudioButton(),
                ],
              ),
              const SizedBox(height: DesignTokens.spaceLg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GlassButton(
                    onPressed: () => _createPlaylist(context, t),
                    variant: GlassButtonVariant.primary,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 18),
                        const SizedBox(width: DesignTokens.spaceXs),
                        Flexible(child: Text(t('library.create_playlist'))),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  GlassButton(
                    onPressed: () => context.push('/import'),
                    variant: GlassButtonVariant.secondary,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download_rounded, size: 16),
                        const SizedBox(width: DesignTokens.spaceXs),
                        Flexible(child: Text(t('import.title'))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        _GlassTabBar(
          controller: _tabs,
          tabs: [
            _GlassTab(text: t('library.on_device')),
            if (CloudConfig.isConfigured) _GlassTab(text: t('library.cloud')),
            _GlassTab(text: t('library.liked_songs')),
            _GlassTab(text: t('library.tab_playlists')),
            _GlassTab(text: t('library.tab_albums')),
            _GlassTab(text: t('library.tab_artists')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const DeviceTracksTab(),
              if (CloudConfig.isConfigured) const CloudTracksTab(),
              _LikedSongsTab(library: library, ref: ref),
              _PlaylistsTab(library: library),
              _SavedTab(
                collections: library.savedAlbums,
                emptyIcon: Icons.album_outlined,
                emptyTitle: t('library.no_albums_title'),
                emptyDescription: t('library.no_albums_desc'),
                onOpen: (id) => context.push(
                  '/collection?type=album&id=${Uri.encodeComponent(id)}',
                ),
              ),
              _SavedTab(
                collections: library.savedArtists,
                emptyIcon: Icons.person_outline_rounded,
                emptyTitle: t('library.no_artists_title'),
                emptyDescription: t('library.no_artists_desc'),
                onOpen: (id) =>
                    context.push('/artist?id=${Uri.encodeComponent(id)}'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createPlaylist(BuildContext context, dynamic t) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme(context).colorScheme.surfaceContainer,
        title: Text(
          t('library.create_playlist'),
          style: theme(context).textTheme.titleMedium,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('playlist.untitled_playlist'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('common.create')),
          ),
        ],
      ),
    );

    if (created == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(libraryControllerProvider.notifier)
          .createPlaylist(title: controller.text.trim());
    }
    controller.dispose();
  }
}

class _GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassTabBar({required this.controller, required this.tabs});

  final TabController controller;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      opacity: DesignTokens.glassOpacityStrong,
      blur: DesignTokens.glassBlurStrong,
      dim: DesignTokens.glassDimStrong,
      borderRadius: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceMd,
        vertical: DesignTokens.spaceSm,
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: tabs,
        indicator: const BoxDecoration(),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _GlassTab extends StatelessWidget {
  const _GlassTab({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Tab(text: text);
  }
}

class _LikedSongsTab extends ConsumerWidget {
  const _LikedSongsTab({required this.library, required this.ref});

  final LibraryState library;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final controller = ref.read(playerControllerProvider.notifier);

    if (library.isLoadingLiked && library.likedTracks.isEmpty) {
      return const LoadingState();
    }
    if (library.likedTracks.isEmpty) {
      return EmptyState(
        icon: Icons.favorite_border_rounded,
        title: t('library.liked_songs'),
        description: t('library.no_albums_desc'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DesignTokens.spaceXxl),
      separatorBuilder: (context, index) =>
          const SizedBox(height: DesignTokens.spaceMd),
      itemCount: library.likedTracks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlassButton(
                onPressed: () => controller.playTrack(
                  library.likedTracks.first,
                  queue: library.likedTracks,
                  context: 'library:liked',
                ),
                variant: GlassButtonVariant.primary,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded, size: 18),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Flexible(child: Text(t('common.play_all'))),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              GlassButton(
                onPressed: () => controller.playShuffled(
                  library.likedTracks,
                  context: 'library:liked',
                ),
                variant: GlassButtonVariant.secondary,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shuffle_rounded, size: 18),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Flexible(child: Text(t('common.shuffle'))),
                  ],
                ),
              ),
            ],
          );
        }
        final track = library.likedTracks[index - 1];
        return _GlassTrackRow(
          track: track,
          queue: library.likedTracks,
          context_: 'library:liked',
          index: index - 1,
        );
      },
    );
  }
}

class _GlassTrackRow extends ConsumerWidget {
  const _GlassTrackRow({
    required this.track,
    required this.queue,
    required this.context_,
    required this.index,
  });

  final Track track;
  final List<Track> queue;
  final String context_;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(playerControllerProvider.notifier);

    return GlassCard(
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      onTap: () => controller.playTrack(
        track,
        queue: queue,
        context: context_,
        index: index,
      ),
      child: Row(
        children: [
          GlassCover(
            url: track.coverUrl,
            size: 48,
            borderRadius: DesignTokens.radiusSm,
            showGlow: true,
            accentColor: theme.colorScheme.primary,
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textBodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXxs),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textBodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          GlassIconButton(
            icon: Icons.play_arrow_rounded,
            onPressed: () => controller.playTrack(
              track,
              queue: queue,
              context: context_,
              index: index,
            ),
            size: 36,
            iconSize: 20,
            variant: GlassButtonVariant.secondary,
          ),
        ],
      ),
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab({required this.library});

  final LibraryState library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);

    if (library.isLoadingPlaylists && library.playlists.isEmpty) {
      return const LoadingState();
    }
    if (library.playlists.isEmpty) {
      return EmptyState(
        icon: Icons.queue_music_rounded,
        title: t('library.no_playlists_title'),
        description: t('library.no_playlists_desc'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DesignTokens.spaceXxl),
      separatorBuilder: (context, index) =>
          const SizedBox(height: DesignTokens.spaceMd),
      itemCount: library.playlists.length,
      itemBuilder: (context, index) {
        final playlist = library.playlists[index];
        return _GlassPlaylistItem(
          playlist: playlist,
          onDelete: () => ref
              .read(libraryControllerProvider.notifier)
              .deletePlaylist(playlist.id),
          onOpen: () => context.push(
            '/library/playlist?id=${Uri.encodeComponent(playlist.id)}',
          ),
        );
      },
    );
  }
}

class _GlassPlaylistItem extends ConsumerWidget {
  const _GlassPlaylistItem({
    required this.playlist,
    required this.onDelete,
    required this.onOpen,
  });

  final UserPlaylist playlist;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      onTap: onOpen,
      child: Row(
        children: [
          GlassCover(
            url: '',
            size: 48,
            borderRadius: DesignTokens.radiusSm,
            showGlow: true,
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playlist.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textBodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (playlist.description != null &&
                    playlist.description!.isNotEmpty) ...[
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Text(
                    playlist.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.textBodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'delete', child: Text(t('common.delete'))),
            ],
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab({
    required this.collections,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.onOpen,
  });

  final List<SavedCollection> collections;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyDescription;
  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collections.isEmpty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        description: emptyDescription,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DesignTokens.spaceXxl),
      separatorBuilder: (context, index) =>
          const SizedBox(height: DesignTokens.spaceMd),
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final item = collections[index];
        return GlassCard(
          padding: const EdgeInsets.all(DesignTokens.spaceMd),
          onTap: () => onOpen(item.id),
          child: Row(
            children: [
              GlassCover(
                url: item.coverUrl,
                size: 44,
                borderRadius: DesignTokens.radiusMd,
                showGlow: true,
              ),
              const SizedBox(width: DesignTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.textBodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spaceXxs),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.textBodySmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
