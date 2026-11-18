import 'dart:convert';

import 'package:flutter/material.dart';

import '../utils/json.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/customization/customization_controller.dart';
import '../theme/app_theme.dart';

/// How the queue repeats.
enum PlaybackRepeatMode { off, all, one }

/// Audio quality preference.
enum AudioQuality { low, standard, high, lossless }

/// Shape of the mini player.
enum MiniPlayerStyle { standard, rounded }

/// What a double click on a track does.
enum TrackDoubleClickBehavior { play, queue }

/// What the player shows when it starts with an empty queue.
enum DefaultPlaybackContext { resume, empty }

/// Persisted application settings.
///
/// Mirrors the `SessionState` slice of `playerStore.ts` plus the appearance
/// preferences that live in `customizationStore.ts`.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.accentVariant = AccentVariant.defaultVariant,
    this.locale = 'en',
    this.volume = 1,
    this.repeat = PlaybackRepeatMode.off,
    this.shuffle = false,
    this.audioQuality = AudioQuality.standard,
    this.miniPlayerStyle = MiniPlayerStyle.standard,
    this.pauseOnDeviceChange = false,
    this.autoplaySimilar = true,
    this.trackDoubleClickBehavior = TrackDoubleClickBehavior.play,
    this.defaultPlaybackContext = DefaultPlaybackContext.resume,
    this.playbackRate = 1,
    this.pitchSemitones = 0,
    this.isPitchLinked = true,
    this.keepSpeedAcrossTracks = false,
    this.isReverbEnabled = false,
    this.reverbLevel = 0.35,
    this.overlayAlwaysOnTop = true,
    this.overlayPosition = 'topRight',
    this.lyricsOffsetMs = 0,
    this.discordEnabled = false,
    this.discordShowArtwork = true,
    this.discordShowArtistImage = true,
    this.discordShowTime = true,
    this.wallpaperPath,
    this.wallpaperBlur = 0,
    this.wallpaperDim = 0,
    this.videoBackdrop = true,
    this.sidebarDecoration = const BlockCustomization(),
    this.contentDecoration = const BlockCustomization(),
    this.miniplayerDecoration = const BlockCustomization(),
  });

  final ThemeMode themeMode;
  final AccentVariant accentVariant;
  final String locale;
  final double volume;
  final PlaybackRepeatMode repeat;
  final bool shuffle;
  final AudioQuality audioQuality;
  final MiniPlayerStyle miniPlayerStyle;
  final bool pauseOnDeviceChange;
  final bool autoplaySimilar;
  final TrackDoubleClickBehavior trackDoubleClickBehavior;
  final DefaultPlaybackContext defaultPlaybackContext;
  final double playbackRate;
  final double pitchSemitones;
  final bool isPitchLinked;
  final bool keepSpeedAcrossTracks;
  final bool isReverbEnabled;
  final double reverbLevel;

  /// True when the overlay window stays above the other windows.
  final bool overlayAlwaysOnTop;

  /// Where the overlay window appears: `topLeft`, `topCenter` or `topRight`.
  final String overlayPosition;
  final int lyricsOffsetMs;
  final bool discordEnabled;
  final bool discordShowArtwork;
  final bool discordShowArtistImage;
  final bool discordShowTime;

  /// The path of the wallpaper, in the documents directory.
  final String? wallpaperPath;
  final int wallpaperBlur;
  final int wallpaperDim;
  final bool videoBackdrop;
  final BlockCustomization sidebarDecoration;
  final BlockCustomization contentDecoration;
  final BlockCustomization miniplayerDecoration;

  static const String _key = 'waveify_settings_v1';

  /// Reads the settings from disk, falling back to the defaults.
  static Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const AppSettings();
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == map['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        accentVariant: AccentVariant.fromId(map['accentVariant'] as String?),
        locale: map['locale'] as String? ?? 'en',
        volume: (map['volume'] as num?)?.toDouble() ?? 1,
        repeat: PlaybackRepeatMode.values.firstWhere(
          (m) => m.name == map['repeat'],
          orElse: () => PlaybackRepeatMode.off,
        ),
        shuffle: map['shuffle'] as bool? ?? false,
        audioQuality: AudioQuality.values.firstWhere(
          (m) => m.name == map['audioQuality'],
          orElse: () => AudioQuality.standard,
        ),
        miniPlayerStyle: MiniPlayerStyle.values.firstWhere(
          (m) => m.name == map['miniPlayerStyle'],
          orElse: () => MiniPlayerStyle.standard,
        ),
        pauseOnDeviceChange: map['pauseOnDeviceChange'] as bool? ?? false,
        autoplaySimilar: map['autoplaySimilar'] as bool? ?? true,
        trackDoubleClickBehavior: TrackDoubleClickBehavior.values.firstWhere(
          (m) => m.name == map['trackDoubleClickBehavior'],
          orElse: () => TrackDoubleClickBehavior.play,
        ),
        defaultPlaybackContext: DefaultPlaybackContext.values.firstWhere(
          (m) => m.name == map['defaultPlaybackContext'],
          orElse: () => DefaultPlaybackContext.resume,
        ),
        playbackRate: (map['playbackRate'] as num?)?.toDouble() ?? 1,
        pitchSemitones: (map['pitchSemitones'] as num?)?.toDouble() ?? 0,
        isPitchLinked: map['isPitchLinked'] as bool? ?? true,
        keepSpeedAcrossTracks: map['keepSpeedAcrossTracks'] as bool? ?? false,
        isReverbEnabled: map['isReverbEnabled'] as bool? ?? false,
        reverbLevel: (map['reverbLevel'] as num?)?.toDouble() ?? 0.35,
        lyricsOffsetMs: (map['lyricsOffsetMs'] as num?)?.toInt() ?? 0,
        discordEnabled: map['discordEnabled'] as bool? ?? false,
        discordShowArtwork: map['discordShowArtwork'] as bool? ?? true,
        discordShowArtistImage: map['discordShowArtistImage'] as bool? ?? true,
        discordShowTime: map['discordShowTime'] as bool? ?? true,
        wallpaperPath: map['wallpaperPath'] as String?,
        wallpaperBlur: (map['wallpaperBlur'] as num?)?.round() ?? 0,
        wallpaperDim: (map['wallpaperDim'] as num?)?.round() ?? 0,
        videoBackdrop: map['videoBackdrop'] != false,
        sidebarDecoration: _decodeBlock(map['sidebarDecoration']),
        contentDecoration: _decodeBlock(map['contentDecoration']),
        miniplayerDecoration: _decodeBlock(map['miniplayerDecoration']),
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  /// A copy with the given fields replaced.
  AppSettings copyWith({
    ThemeMode? themeMode,
    AccentVariant? accentVariant,
    String? locale,
    double? volume,
    PlaybackRepeatMode? repeat,
    bool? shuffle,
    AudioQuality? audioQuality,
    MiniPlayerStyle? miniPlayerStyle,
    bool? pauseOnDeviceChange,
    bool? autoplaySimilar,
    TrackDoubleClickBehavior? trackDoubleClickBehavior,
    DefaultPlaybackContext? defaultPlaybackContext,
    double? playbackRate,
    double? pitchSemitones,
    bool? isPitchLinked,
    bool? keepSpeedAcrossTracks,
    bool? isReverbEnabled,
    double? reverbLevel,
    bool? overlayAlwaysOnTop,
    String? overlayPosition,
    int? lyricsOffsetMs,
    bool? discordEnabled,
    bool? discordShowArtwork,
    bool? discordShowArtistImage,
    bool? discordShowTime,
    String? wallpaperPath,
    bool clearWallpaper = false,
    int? wallpaperBlur,
    int? wallpaperDim,
    bool? videoBackdrop,
    BlockCustomization? sidebarDecoration,
    BlockCustomization? contentDecoration,
    BlockCustomization? miniplayerDecoration,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentVariant: accentVariant ?? this.accentVariant,
      locale: locale ?? this.locale,
      volume: volume ?? this.volume,
      repeat: repeat ?? this.repeat,
      shuffle: shuffle ?? this.shuffle,
      audioQuality: audioQuality ?? this.audioQuality,
      miniPlayerStyle: miniPlayerStyle ?? this.miniPlayerStyle,
      pauseOnDeviceChange: pauseOnDeviceChange ?? this.pauseOnDeviceChange,
      autoplaySimilar: autoplaySimilar ?? this.autoplaySimilar,
      trackDoubleClickBehavior:
          trackDoubleClickBehavior ?? this.trackDoubleClickBehavior,
      defaultPlaybackContext:
          defaultPlaybackContext ?? this.defaultPlaybackContext,
      playbackRate: playbackRate ?? this.playbackRate,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      isPitchLinked: isPitchLinked ?? this.isPitchLinked,
      keepSpeedAcrossTracks:
          keepSpeedAcrossTracks ?? this.keepSpeedAcrossTracks,
      isReverbEnabled: isReverbEnabled ?? this.isReverbEnabled,
      reverbLevel: reverbLevel ?? this.reverbLevel,
      overlayAlwaysOnTop: overlayAlwaysOnTop ?? this.overlayAlwaysOnTop,
      overlayPosition: overlayPosition ?? this.overlayPosition,
      lyricsOffsetMs: lyricsOffsetMs ?? this.lyricsOffsetMs,
      discordEnabled: discordEnabled ?? this.discordEnabled,
      discordShowArtwork: discordShowArtwork ?? this.discordShowArtwork,
      discordShowArtistImage:
          discordShowArtistImage ?? this.discordShowArtistImage,
      discordShowTime: discordShowTime ?? this.discordShowTime,
      wallpaperPath: clearWallpaper
          ? null
          : (wallpaperPath ?? this.wallpaperPath),
      wallpaperBlur: wallpaperBlur ?? this.wallpaperBlur,
      wallpaperDim: wallpaperDim ?? this.wallpaperDim,
      videoBackdrop: videoBackdrop ?? this.videoBackdrop,
      sidebarDecoration: sidebarDecoration ?? this.sidebarDecoration,
      contentDecoration: contentDecoration ?? this.contentDecoration,
      miniplayerDecoration: miniplayerDecoration ?? this.miniplayerDecoration,
    );
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'themeMode': themeMode.name,
          'accentVariant': accentVariant.id,
          'locale': locale,
          'volume': volume,
          'repeat': repeat.name,
          'shuffle': shuffle,
          'audioQuality': audioQuality.name,
          'miniPlayerStyle': miniPlayerStyle.name,
          'pauseOnDeviceChange': pauseOnDeviceChange,
          'autoplaySimilar': autoplaySimilar,
          'trackDoubleClickBehavior': trackDoubleClickBehavior.name,
          'defaultPlaybackContext': defaultPlaybackContext.name,
          'playbackRate': playbackRate,
          'pitchSemitones': pitchSemitones,
          'isPitchLinked': isPitchLinked,
          'keepSpeedAcrossTracks': keepSpeedAcrossTracks,
          'isReverbEnabled': isReverbEnabled,
          'reverbLevel': reverbLevel,
          'overlayAlwaysOnTop': overlayAlwaysOnTop,
          'overlayPosition': overlayPosition,
          'lyricsOffsetMs': lyricsOffsetMs,
          'discordEnabled': discordEnabled,
          'discordShowArtwork': discordShowArtwork,
          'discordShowArtistImage': discordShowArtistImage,
          'discordShowTime': discordShowTime,
          'wallpaperPath': wallpaperPath,
          'wallpaperBlur': wallpaperBlur,
          'wallpaperDim': wallpaperDim,
          'videoBackdrop': videoBackdrop,
          'sidebarDecoration': _encodeBlock(sidebarDecoration),
          'contentDecoration': _encodeBlock(contentDecoration),
          'miniplayerDecoration': _encodeBlock(miniplayerDecoration),
        }),
      );
    } catch (_) {}
  }
}

Map<String, dynamic> _encodeBlock(BlockCustomization block) => {
  'opacity': block.opacity,
  'blur': block.blur,
  'dim': block.dim,
};

BlockCustomization _decodeBlock(Object? raw) {
  final map = asRecord(raw);
  if (map == null) return const BlockCustomization();
  return BlockCustomization(
    opacity: (map['opacity'] as num?)?.round() ?? 100,
    blur: (map['blur'] as num?)?.round() ?? 0,
    dim: (map['dim'] as num?)?.round() ?? 0,
  );
}
