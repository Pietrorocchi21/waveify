import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/player_controller.dart';
import '../../app/router.dart';
import '../providers/app_providers.dart';
import 'deeplink_parser.dart';

/// Receives the `waveify://` deep links and opens the matching page.
///
/// The incoming links are validated by [parseDeepLink] before they are used,
/// so a link can only point at a well known entity.
class DeepLinkService {
  DeepLinkService({
    required this.ref,
    required this.router,
    AppLinks? appLinks,
  }) : _appLinks = appLinks ?? AppLinks();

  final Ref ref;
  final GoRouter router;
  final AppLinks _appLinks;

  StreamSubscription<Uri>? _subscription;

  /// Starts listening for the deep links.
  Future<void> start() async {
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => handleUri(uri.toString()),
      onError: (Object error) => debugPrint('[deeplink] $error'),
    );

    // The link that started the app.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        // The navigation is deferred: the router is not ready yet.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleUri(initial.toString());
        });
      }
    } catch (error) {
      debugPrint('[deeplink] initial link: $error');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Opens the target of a deep link.
  Future<void> handleUri(String raw) async {
    final target = parseDeepLink(raw);
    if (target == null) {
      debugPrint('[deeplink] ignorata: $raw');
      return;
    }
    await open(target);
  }

  /// Opens a deep link target.
  Future<void> open(DeepLinkTarget target) async {
    switch (target.type) {
      case DeepLinkType.artist:
        router.go('/artist?id=${Uri.encodeQueryComponent(target.id)}');
      case DeepLinkType.album:
        router.go(
          '/collection?type=album&id=${Uri.encodeQueryComponent(target.id)}',
        );
      case DeepLinkType.playlist:
        router.go(
          '/collection?type=playlist&id=${Uri.encodeQueryComponent(target.id)}',
        );
      case DeepLinkType.track:
        await _openTrack(target.id);
    }
  }

  Future<void> _openTrack(String id) async {
    try {
      final catalog = ref.read(catalogProvider);
      final track = await catalog.getTrack(id);
      await ref.read(playerControllerProvider.notifier).playTrack(
            track,
            queue: [track],
            context: 'deeplink',
            contextCover: track.coverUrl,
          );
      router.go('/player');
    } catch (error) {
      // Unknown id or offline: stay where we are.
      debugPrint('[deeplink] brano non risolvibile: $error');
    }
  }
}

/// The deep link service.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(
    ref: ref,
    router: ref.watch(routerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
