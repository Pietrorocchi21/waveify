import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session_store.dart';
import '../i18n/translator.dart';
import '../media/innertube/innertube_catalog.dart';
import '../media/innertube/stream_resolver.dart';
import '../music/aggregated_music_repository.dart';
import '../music/music_source.dart';
import '../../features/connectivity/connectivity_controller.dart';
import '../../models/auth.dart';
import '../network/api_client.dart';
import '../network/catalog_service.dart';
import '../network/waveify_api.dart';
import '../storage/app_settings.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';

// Re-exported so that importing the providers also brings the theme
// extensions (`ThemeData.textTertiary` and friends) into scope.
export '../theme/app_theme.dart';

/// Persisted application settings.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> init() async {
    state = await AppSettings.load();
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await next.save();
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      update(_copyWith(themeMode: mode));

  Future<void> setAccent(AccentVariant variant) =>
      update(_copyWith(accentVariant: variant));

  Future<void> setLocale(String locale) => update(_copyWith(locale: locale));

  Future<void> setVolume(double volume) =>
      update(_copyWith(volume: volume.clamp(0.0, 1.0)));

  Future<void> setShuffle(bool value) => update(_copyWith(shuffle: value));

  Future<void> setRepeat(PlaybackRepeatMode mode) => update(_copyWith(repeat: mode));

  Future<void> setAutoplaySimilar(bool value) =>
      update(_copyWith(autoplaySimilar: value));

  Future<void> setPlaybackRate(double rate) =>
      update(_copyWith(playbackRate: rate));

  Future<void> setPitchSemitones(double semitones) =>
      update(_copyWith(pitchSemitones: semitones));

  Future<void> setIsPitchLinked(bool value) =>
      update(_copyWith(isPitchLinked: value));

  Future<void> setLyricsOffset(int offsetMs) =>
      update(_copyWith(lyricsOffsetMs: offsetMs));

  Future<void> setReverbEnabled(bool value) =>
      update(_copyWith(isReverbEnabled: value));

  Future<void> setReverbLevel(double level) =>
      update(_copyWith(reverbLevel: level));

  Future<void> setOverlayAlwaysOnTop(bool value) =>
      update(_copyWith(overlayAlwaysOnTop: value));

  Future<void> setOverlayPosition(String position) =>
      update(_copyWith(overlayPosition: position));

  Future<void> setDiscordEnabled(bool value) =>
      update(_copyWith(discordEnabled: value));

  Future<void> setDiscordShowArtwork(bool value) =>
      update(_copyWith(discordShowArtwork: value));

  Future<void> setDiscordShowArtistImage(bool value) =>
      update(_copyWith(discordShowArtistImage: value));

  Future<void> setDiscordShowTime(bool value) =>
      update(_copyWith(discordShowTime: value));

  AppSettings _copyWith({
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
  }) {
    final s = state;
    return AppSettings(
      themeMode: themeMode ?? s.themeMode,
      accentVariant: accentVariant ?? s.accentVariant,
      locale: locale ?? s.locale,
      volume: volume ?? s.volume,
      repeat: repeat ?? s.repeat,
      shuffle: shuffle ?? s.shuffle,
      audioQuality: audioQuality ?? s.audioQuality,
      miniPlayerStyle: miniPlayerStyle ?? s.miniPlayerStyle,
      pauseOnDeviceChange: pauseOnDeviceChange ?? s.pauseOnDeviceChange,
      autoplaySimilar: autoplaySimilar ?? s.autoplaySimilar,
      trackDoubleClickBehavior:
          trackDoubleClickBehavior ?? s.trackDoubleClickBehavior,
      defaultPlaybackContext:
          defaultPlaybackContext ?? s.defaultPlaybackContext,
      playbackRate: playbackRate ?? s.playbackRate,
      pitchSemitones: pitchSemitones ?? s.pitchSemitones,
      isPitchLinked: isPitchLinked ?? s.isPitchLinked,
      keepSpeedAcrossTracks: keepSpeedAcrossTracks ?? s.keepSpeedAcrossTracks,
      isReverbEnabled: isReverbEnabled ?? s.isReverbEnabled,
      reverbLevel: reverbLevel ?? s.reverbLevel,
      overlayAlwaysOnTop: overlayAlwaysOnTop ?? s.overlayAlwaysOnTop,
      overlayPosition: overlayPosition ?? s.overlayPosition,
      lyricsOffsetMs: lyricsOffsetMs ?? s.lyricsOffsetMs,
      discordEnabled: discordEnabled ?? s.discordEnabled,
      discordShowArtwork: discordShowArtwork ?? s.discordShowArtwork,
      discordShowArtistImage:
          discordShowArtistImage ?? s.discordShowArtistImage,
      discordShowTime: discordShowTime ?? s.discordShowTime,
    );
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// The currently selected locale code.
final localeProvider = Provider<String>(
  (ref) => ref.watch(settingsProvider.select((s) => s.locale)),
);

/// The loaded translation table for the current locale, plus the English
/// fallback used for missing keys.
final translationsProvider = FutureProvider<(Translations, Translations)>((
  ref,
) async {
  final locale = ref.watch(localeProvider);
  final current = await Translations.load(locale);
  final fallback = locale == 'en' ? current : await Translations.load('en');
  return (current, fallback);
});

/// The translator for the current locale, with an English fallback.
final translatorProvider = Provider<Translator>((ref) {
  return ref
      .watch(translationsProvider)
      .maybeWhen(
        data: (pair) => Translator(pair.$1, fallback: pair.$2),
        orElse: () => Translator(Translations('en', const {})),
      );
});

/// The auth session store.
final sessionProvider = Provider<AuthSessionStore>((ref) {
  final store = AuthSessionStore();

  // The refresh call needs the API, and the API needs the token from this
  // store: going through the provider graph would create a cycle, so the
  // refresh uses a dedicated client with the same auth flow but no custom signer.
  store.refreshPerform = (refreshToken) async {
    final client = ApiClient();
    final data = await client.request(
      '/v1/auth/refresh',
      method: 'POST',
      body: {'refreshToken': refreshToken},
      allowRefresh: false,
      skipAuth: true,
    );
    return AuthTokens.fromJson(asRecord(data));
  };

  return store;
});

/// The generic HTTP client.
final apiClientProvider = Provider<ApiClient>((ref) {
  final session = ref.watch(sessionProvider);
  final client = ApiClient(
    tokenProvider: () => session.validAccessToken(),
    onRefreshSession: () async {
      final refreshed = await session.refresh();
      return refreshed != null;
    },
  );

  // The failed requests feed the connectivity diagnostics.
  client.onFailure =
      ({
        required String method,
        required String path,
        int? status,
        String? code,
        int latencyMs = 0,
      }) {
        ref
            .read(connectivityControllerProvider.notifier)
            .recordFailure(
              method: method,
              path: path,
              status: status,
              code: code,
              latencyMs: latencyMs,
            );
      };

  return client;
});

/// The typed Waveify API.
final apiProvider = Provider<WaveifyApi>((ref) {
  return WaveifyApi(ref.watch(apiClientProvider));
});

/// Multi-source music aggregation: local-first, remote-fallback and provider
/// abstraction for future integrations such as YouTube Music, SoundCloud or a
/// custom backend.
final musicSourcesProvider = Provider<List<MusicSource>>((ref) {
  final api = ref.watch(apiProvider);
  return [
    LocalMusicSource(),
    YouTubeMusicSource(
      catalog: InnertubeCatalog(),
      resolver: StreamResolver(),
    ),
    WaveifyRemoteSource(api: api),
  ];
});

final musicRepositoryProvider = Provider<AggregatedMusicRepository>((ref) {
  return AggregatedMusicRepository(
    sources: ref.watch(musicSourcesProvider),
  );
});

/// The YouTube stream resolver.
final streamResolverProvider = Provider<StreamResolver>((ref) {
  return StreamResolver();
});

/// The InnerTube catalog (search, albums, playlists, artists).
final innertubeCatalogProvider = Provider<InnertubeCatalog>((ref) {
  return InnertubeCatalog();
});

/// The catalog service: InnerTube first, the backend as a fallback.
final catalogProvider = Provider<CatalogService>((ref) {
  return CatalogService(
    catalog: ref.watch(innertubeCatalogProvider),
    api: ref.watch(apiProvider),
  );
});

