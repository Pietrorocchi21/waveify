import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/providers/app_providers.dart';

/// The decoration of one of the blocks of the interface.
class BlockCustomization {
  const BlockCustomization({this.opacity = 100, this.blur = 0, this.dim = 0});

  /// The opacity of the block, between 0 and 100.
  final int opacity;

  /// The blur of the background behind the block, between 0 and 40.
  final int blur;

  /// The darkening of the background behind the block, between 0 and 85.
  final int dim;

  BlockCustomization copyWith({int? opacity, int? blur, int? dim}) {
    return BlockCustomization(
      opacity: opacity ?? this.opacity,
      blur: blur ?? this.blur,
      dim: dim ?? this.dim,
    );
  }

  static const BlockCustomization defaults = BlockCustomization();
  static const BlockCustomization glass = BlockCustomization(
    opacity: 60,
    blur: 20,
    dim: 15,
  );
}

/// The blocks of the interface that can be decorated.
enum CustomizationBlock { sidebar, contentView, miniplayer }

/// The customization of the interface.
class CustomizationState {
  const CustomizationState({
    this.wallpaperPath,
    this.wallpaperBlur = 0,
    this.wallpaperDim = 0,
    this.sidebar = BlockCustomization.defaults,
    this.contentView = BlockCustomization.defaults,
    this.miniplayer = BlockCustomization.defaults,
  });

  /// The path of the wallpaper, in the documents directory.
  final String? wallpaperPath;

  /// The blur of the wallpaper.
  final int wallpaperBlur;

  /// The darkening of the wallpaper.
  final int wallpaperDim;

  final BlockCustomization sidebar;
  final BlockCustomization contentView;
  final BlockCustomization miniplayer;

  bool get hasWallpaper => wallpaperPath != null && wallpaperPath!.isNotEmpty;

  BlockCustomization blockFor(CustomizationBlock block) {
    switch (block) {
      case CustomizationBlock.sidebar:
        return sidebar;
      case CustomizationBlock.contentView:
        return contentView;
      case CustomizationBlock.miniplayer:
        return miniplayer;
    }
  }

  CustomizationState copyWith({
    String? wallpaperPath,
    bool clearWallpaper = false,
    int? wallpaperBlur,
    int? wallpaperDim,
    BlockCustomization? sidebar,
    BlockCustomization? contentView,
    BlockCustomization? miniplayer,
  }) {
    return CustomizationState(
      wallpaperPath: clearWallpaper
          ? null
          : (wallpaperPath ?? this.wallpaperPath),
      wallpaperBlur: wallpaperBlur ?? this.wallpaperBlur,
      wallpaperDim: wallpaperDim ?? this.wallpaperDim,
      sidebar: sidebar ?? this.sidebar,
      contentView: contentView ?? this.contentView,
      miniplayer: miniplayer ?? this.miniplayer,
    );
  }
}

/// Manages the wallpaper and the decoration of the blocks.
class CustomizationController extends Notifier<CustomizationState> {
  static const String _wallpaperName = 'wallpaper';

  @override
  CustomizationState build() {
    final settings = ref.read(settingsProvider);
    return CustomizationState(
      wallpaperPath: settings.wallpaperPath,
      wallpaperBlur: settings.wallpaperBlur,
      wallpaperDim: settings.wallpaperDim,
      sidebar: settings.sidebarDecoration,
      contentView: settings.contentDecoration,
      miniplayer: settings.miniplayerDecoration,
    );
  }

  /// Picks a wallpaper and copies it in the documents directory.
  Future<bool> pickWallpaper() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null) return false;

      final documents = await getApplicationDocumentsDirectory();
      final target = File('${documents.path}/$_wallpaperName');
      await File(path).copy(target.path);

      state = state.copyWith(wallpaperPath: target.path);
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes the wallpaper.
  Future<void> clearWallpaper() async {
    final path = state.wallpaperPath;
    state = state.copyWith(clearWallpaper: true);
    await _persist();
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
  }

  /// Sets the blur and the darkening of the wallpaper.
  Future<void> setWallpaper({int? blur, int? dim}) async {
    state = state.copyWith(wallpaperBlur: blur, wallpaperDim: dim);
    await _persist();
  }

  /// Changes the decoration of one block.
  Future<void> setBlock(
    CustomizationBlock block, {
    int? opacity,
    int? blur,
    int? dim,
  }) async {
    final current = state.blockFor(block);
    final updated = current.copyWith(opacity: opacity, blur: blur, dim: dim);

    switch (block) {
      case CustomizationBlock.sidebar:
        state = state.copyWith(sidebar: updated);
      case CustomizationBlock.contentView:
        state = state.copyWith(contentView: updated);
      case CustomizationBlock.miniplayer:
        state = state.copyWith(miniplayer: updated);
    }
    await _persist();
  }

  /// Applies the decoration of a block to every block.
  Future<void> applyToAll(CustomizationBlock block) async {
    final source = state.blockFor(block);
    state = state.copyWith(
      sidebar: source,
      contentView: source,
      miniplayer: source,
    );
    await _persist();
  }

  /// Restores the default decoration of a block.
  Future<void> resetBlock(CustomizationBlock block) async {
    await setBlock(
      block,
      opacity: BlockCustomization.defaults.opacity,
      blur: BlockCustomization.defaults.blur,
      dim: BlockCustomization.defaults.dim,
    );
  }

  /// Restores everything.
  Future<void> resetAll() async {
    state = const CustomizationState();
    await _persist();
  }

  Future<void> _persist() async {
    final settings = ref.read(settingsProvider);
    final updated = settings.copyWith(
      wallpaperPath: state.wallpaperPath,
      wallpaperBlur: state.wallpaperBlur,
      wallpaperDim: state.wallpaperDim,
      sidebarDecoration: state.sidebar,
      contentDecoration: state.contentView,
      miniplayerDecoration: state.miniplayer,
    );
    await ref.read(settingsProvider.notifier).update(updated);
  }
}

/// The customization controller provider.
final customizationControllerProvider =
    NotifierProvider<CustomizationController, CustomizationState>(
      CustomizationController.new,
    );

/// Draws the wallpaper behind the interface.
class WallpaperBackground extends ConsumerWidget {
  const WallpaperBackground({super.key, required this.child, this.fallback});

  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customization = ref.watch(customizationControllerProvider);
    final path = customization.wallpaperPath;

    if (path == null || path.isEmpty || !File(path).existsSync()) {
      final backdrop = fallback;
      if (backdrop == null) return child;
      return Stack(fit: StackFit.expand, children: [backdrop, child]);
    }

    final file = File(path);

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: customization.wallpaperBlur.toDouble(),
            sigmaY: customization.wallpaperBlur.toDouble(),
          ),
          child: Image.file(file, fit: BoxFit.cover),
        ),
        if (customization.wallpaperDim > 0)
          ColoredBox(
            color: Colors.black.withValues(
              alpha: customization.wallpaperDim / 100,
            ),
          ),
        child,
      ],
    );
  }
}

/// Applies the decoration of a block: the opacity of the content and the
/// blur and the darkening of what is behind it.
class DecoratedBlock extends ConsumerWidget {
  const DecoratedBlock({super.key, required this.block, required this.child});

  final CustomizationBlock block;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customization = ref.watch(customizationControllerProvider);
    final config = customization.blockFor(block);

    final content = Opacity(
      opacity: config.opacity.clamp(0, 100) / 100,
      child: child,
    );

    if (config.blur <= 0 && config.dim <= 0) return content;

    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: config.blur.toDouble(),
        sigmaY: config.blur.toDouble(),
      ),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: config.dim / 100),
        child: content,
      ),
    );
  }
}
