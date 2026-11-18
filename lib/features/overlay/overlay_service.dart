import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/window_service.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/app_settings.dart';
import '../auth/auth_controller.dart';

/// The state of the overlay.
class OverlayState {
  const OverlayState({this.isOpen = false, this.error});

  /// True when the window is in the overlay mode.
  final bool isOpen;

  /// The last error, when the mode could not be applied.
  final String? error;

  OverlayState copyWith({
    bool? isOpen,
    String? error,
    bool clearError = false,
  }) {
    return OverlayState(
      isOpen: isOpen ?? this.isOpen,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Opens and closes the overlay.
///
/// The overlay is the mini player that floats above the other windows: the
/// window of the application shrinks to a small bar that stays in the
/// foreground. It is toggled with the system shortcut or from the settings.
class OverlayService extends Notifier<OverlayState> {
  bool _transitioning = false;

  @override
  OverlayState build() {
    // The session decides whether the overlay can stay open.
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.isAuthenticated && state.isOpen) close();
    });

    // The settings decide where the overlay appears.
    ref.listen(settingsProvider, (previous, next) {
      if (!state.isOpen) return;
      WindowService.instance.enterOverlayMode(alignment: _alignmentFor(next));
    });

    return const OverlayState();
  }

  /// Opens the overlay, or closes it when it is already open.
  Future<void> toggle() async {
    if (state.isOpen) {
      await close();
    } else {
      await open();
    }
  }

  /// Opens the overlay.
  Future<void> open() async {
    if (state.isOpen || _transitioning || !WindowService.instance.isDesktop) {
      return;
    }

    // Without a session there is no player to show.
    if (!ref.read(authControllerProvider).isAuthenticated) return;

    final settings = ref.read(settingsProvider);
    _transitioning = true;
    try {
      await WindowService.instance.enterOverlayMode(
        alignment: _alignmentFor(settings),
      );
      state = state.copyWith(isOpen: true, clearError: true);
    } finally {
      _transitioning = false;
    }
    if (!ref.read(authControllerProvider).isAuthenticated) await close();
  }

  /// Closes the overlay and gives the window back its size.
  Future<void> close() async {
    if (!state.isOpen || _transitioning) return;

    _transitioning = true;
    try {
      await WindowService.instance.exitOverlayMode();
      state = state.copyWith(isOpen: false);
    } finally {
      _transitioning = false;
    }
  }

  /// The anchor of the overlay.
  Alignment _alignmentFor(AppSettings settings) {
    switch (settings.overlayPosition) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      default:
        return Alignment.topRight;
    }
  }
}

/// The overlay service provider.
final overlayServiceProvider = NotifierProvider<OverlayService, OverlayState>(
  OverlayService.new,
);
