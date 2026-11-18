import 'package:waveify/core/local/local_library_store.dart';
import 'package:waveify/core/theme/artwork_palette.dart';
import 'package:waveify/features/lyrics/lyrics_controller.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waveify/app.dart';
import 'package:waveify/app/router.dart';
import 'package:waveify/app/listening_room.dart';
import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/features/auth/auth_controller.dart';
import 'package:waveify/features/downloads/downloads_controller.dart';
import 'package:waveify/features/downloads/downloads_store.dart';
import 'package:waveify/features/player/player_controller.dart';
import 'package:waveify/features/player/player_state.dart';
import 'package:waveify/features/player/ui/mini_player.dart';
import 'package:waveify/features/player/ui/fullscreen_player_page.dart';
import 'package:waveify/models/track.dart';
import 'package:waveify/shared/widgets/glass.dart';
import 'package:waveify/shared/widgets/artwork_stage.dart';
import 'package:waveify/shared/widgets/common.dart';

import '../support/ui_fixtures.dart';
import '../support/artwork_fixtures.dart';

import 'package:cached_network_image/cached_network_image.dart';

/// Exercises the real UI against observable transport state, without a device,
/// a server, audio plugins or third party image/network dependencies.
class FixtureDeviceStore extends LocalLibraryStore {
  @override
  Future<T> read<T>(T Function(Map<String, dynamic>) action) async =>
      action(LocalLibraryStore.empty());
}

class PreviewLyricsController extends LyricsController {
  @override
  LyricsState build() => const LyricsState();
}

class FixtureDownloadsStore extends DownloadsStore {
  @override
  Future<List<DownloadedTrack>> load() async => const [];
}

class PreviewPlayer extends PlayerController {
  void showStatus(PlayerStatus status, {String? error}) => state = state
      .copyWith(status: status, error: error, clearError: error == null);
  @override
  PlayerState build() => PlayerState(
    currentTrack: fixtureTracks.first,
    queue: fixtureTracks,
    currentIndex: 0,
    status: PlayerStatus.paused,
    duration: const Duration(minutes: 4),
    position: const Duration(seconds: 74),
  );
  @override
  Future<void> togglePlayPause() async => state = state.copyWith(
    status: state.isPlaying ? PlayerStatus.paused : PlayerStatus.playing,
  );
  @override
  Future<void> seek(Duration position) async =>
      state = state.copyWith(position: position);
  @override
  Future<void> setVolume(double volume) async =>
      state = state.copyWith(volume: volume);
  @override
  Future<void> skipNext({bool isAutoEnd = false}) async =>
      state = state.copyWith(currentTrack: fixtureTracks[1], currentIndex: 1);
  @override
  Future<void> skipPrevious() async => state = state.copyWith(
    currentTrack: fixtureTracks.first,
    currentIndex: 0,
  );
  @override
  void reorderQueue(int fromIndex, int toIndex) {
    final next = [...state.queue];
    next.insert(toIndex, next.removeAt(fromIndex));
    state = state.copyWith(queue: next);
  }

  @override
  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    String? context,
    String? contextCover,
    int? index,
    bool preserveQueue = false,
  }) async {
    state = state.copyWith(
      currentTrack: track,
      queue: queue,
      status: PlayerStatus.playing,
    );
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  // Opt-in captures keep ordinary CI independent of OS/font-specific pixels.
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final captureDirectory =
        const String.fromEnvironment('UI_CAPTURE_DIR').isEmpty
        ? '${Directory.systemTemp.path}/waveify-previews'
        : const String.fromEnvironment('UI_CAPTURE_DIR');
    final file = File('$captureDirectory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final sdk = Platform.environment['FLUTTER_ROOT']!;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/${entry.value}')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    CachedNetworkImageProvider.defaultCacheManager = ArtworkFixtureCache(
      await createArtworkFixtures(),
    );
  });
  for (final size in [
    const Size(1440, 1000),
    const Size(390, 844),
    const Size(320, 640),
  ]) {
    testWidgets('main screens and transport fit ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      if (size.width == 390) {
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.resetPadding);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(FixtureApi()),
          artworkPaletteProvider.overrideWith((ref, url) async => null),
          localLibraryStoreProvider.overrideWithValue(FixtureDeviceStore()),
          lyricsControllerProvider.overrideWith(PreviewLyricsController.new),
          downloadsStoreProvider.overrideWithValue(FixtureDownloadsStore()),
          sessionProvider.overrideWithValue(FixtureSessionStore()),
          innertubeCatalogProvider.overrideWithValue(FixtureCatalog()),
          playerControllerProvider.overrideWith(PreviewPlayer.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(
            key: ValueKey('capture'),
            child: WaveifyApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'login-${size.width.toInt()}');
      final signIn = container
          .read(authControllerProvider.notifier)
          .login('test@example.com', 'password123');
      await tester.pump();
      await signIn;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'home-${size.width.toInt()}');
      final desktopRoom = size.width >= 1120;
      final dock = desktopRoom
          ? find.byType(ListeningRoomDock)
          : find.byType(MiniPlayer);
      expect(dock, findsOneWidget);
      expect(
        find.byType(ListeningRoomQueue),
        desktopRoom ? findsOneWidget : findsNothing,
      );
      // Dock occupies layout space; content cannot extend behind it.
      final scroll = find.byType(CustomScrollView).first;
      expect(
        tester.getRect(scroll).bottom,
        lessThanOrEqualTo(tester.getRect(dock).top),
      );
      await tester.tap(
        find.descendant(
          of: dock,
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(playerControllerProvider).isPlaying, isTrue);
      final sliders = find.descendant(of: dock, matching: find.byType(Slider));
      final timeline = desktopRoom ? sliders.first : sliders.last;
      await tester.tap(timeline);
      await tester.pumpAndSettle();
      expect(
        container.read(playerControllerProvider).position.inSeconds,
        greaterThan(74),
      );
      if (size.width >= 900) {
        await tester.tap(desktopRoom ? sliders.last : sliders.first);
        await tester.pumpAndSettle();
        expect(container.read(playerControllerProvider).volume, lessThan(1));
      }

      await tester.tap(
        find.descendant(
          of: dock,
          matching: find.byIcon(Icons.skip_next_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(playerControllerProvider).currentTrack?.id, 't2');
      final router = container.read(routerProvider);
      for (final path in [
        '/search',
        '/library',
        '/downloads',
        '/remote',
        '/settings',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$path at ${size.width}',
        );
        await capture(tester, '${path.substring(1)}-${size.width.toInt()}');
      }
      router.go('/');
      await tester.pumpAndSettle();
      // Existing full-player flow is reachable from track metadata.
      await tester.tap(
        find.descendant(of: dock, matching: find.text('Blue room')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FullscreenPlayerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'player-${size.width.toInt()}');
      for (final icon in [Icons.lyrics_outlined, Icons.tune_rounded]) {
        await tester.tap(find.byIcon(icon));
        await tester.pumpAndSettle();
        expect(find.byType(GlassSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
        container.read(routerProvider).pop();
        await tester.pumpAndSettle();
      }

      final preview =
          container.read(playerControllerProvider.notifier) as PreviewPlayer;
      preview.showStatus(PlayerStatus.loading);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      preview.showStatus(
        PlayerStatus.error,
        error: 'The audio source is unavailable. Try another track.',
      );
      await tester.pump();
      expect(
        find.text('The audio source is unavailable. Try another track.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      preview.showStatus(PlayerStatus.paused);
      await tester.pump();

      router.go('/');
      await tester.pumpAndSettle();
      // The queue has unique row keys and remains usable with multiple tracks.
      final context = tester.element(dock);
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => Consumer(
          builder: (context, ref, child) => TextButton(
            onPressed: () => showQueueSheet(context, ref),
            child: const Text('Open queue'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open queue'));
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'queue-${size.width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'cover selection is silent, follows playback and survives resizing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var activated = -1;
      final entries = [
        for (var i = 0; i < 3; i++)
          StageArtwork(
            id: '$i',
            title: 'Track $i',
            subtitle: 'Artist',
            coverUrl: '',
            onActivate: () => activated = i,
          ),
      ];
      Widget app(int current, {bool reduced = false}) => ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: tester.view.physicalSize,
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ArtworkStage(
                  items: entries,
                  initialIndex: current,
                  actionLabel: 'Play',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Track 1'), findsOneWidget);
      expect(activated, -1);
      await tester.tap(find.text('Play'));
      expect(activated, 1);
      await tester.pumpWidget(app(2));
      await tester.pumpAndSettle();
      expect(find.text('Track 2'), findsOneWidget);
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.pumpWidget(app(2, reduced: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Track 0'), findsOneWidget);
      expect(activated, 1);
    },
  );

  testWidgets('one missing cover stays readable without carousel controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArtworkStage(
                items: [
                  StageArtwork(
                    id: 'only',
                    title: 'Single track',
                    subtitle: 'Artist',
                    coverUrl: '',
                    onActivate: () {},
                  ),
                ],
                actionLabel: 'Play',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Single track'), findsOneWidget);
    expect(find.byType(CoverImage), findsWidgets);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass buttons support keyboard focus and reduced transparency', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            highContrast: true,
          ),
          child: Scaffold(
            body: GlassPanel(
              child: GlassButton(
                onPressed: () => taps++,
                child: const Text('Play'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('Play'));
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 2);
    expect(find.byType(TextButton), findsOneWidget);
  });
}
