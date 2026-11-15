import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../features/player/player_controller.dart';
import '../providers/app_providers.dart';

/// Small decoded images, bounded extraction time and auto-disposed providers
/// keep artwork colour extraction off the playback/position update path.
final artworkPaletteProvider = FutureProvider.autoDispose
    .family<Color?, String>((ref, url) async {
      if (url.isEmpty) return null;
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          ResizeImage(
            url.startsWith('file:')
                ? FileImage(File.fromUri(Uri.parse(url)))
                : CachedNetworkImageProvider(url),
            width: 64,
            height: 64,
          ),
          size: const Size(64, 64),
          maximumColorCount: 8,
        ).timeout(const Duration(seconds: 3));
        return palette.mutedColor?.color ?? palette.dominantColor?.color;
      } catch (_) {
        return null;
      }
    });

final ambientAccentProvider = Provider<Color>((ref) {
  final url = ref.watch(
    playerControllerProvider.select((s) => s.currentTrack?.coverUrl ?? ''),
  );
  final palette = ref.watch(artworkPaletteProvider(url)).asData?.value;
  return palette ??
      ref.watch(settingsProvider.select((s) => s.accentVariant.accentColor));
});
