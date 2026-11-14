import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';

class WindowService {
  WindowService._();

  static final WindowService instance = WindowService._();

  bool _initialized = false;
  bool _isMaximized = false;

  static const Size initialSize = Size(1200, 780);
  static const Size minimumSize = Size(1100, 705);

  static const Size overlaySize = Size(420, 88);

  static const Size _noLimit = Size(-1, -1);

  bool _isOverlay = false;

  bool get isOverlay => _isOverlay;

  Future<void> enterOverlayMode({
    Alignment alignment = Alignment.topRight,
  }) async {
    if (!isDesktop || _isOverlay) return;
    _isOverlay = true;

    await _safe(() => windowManager.unmaximize());
    await _safe(() => windowManager.setMinimumSize(Size.zero));
    await _safe(() => windowManager.setMaximumSize(_noLimit));
    await _safe(() => windowManager.setBounds(_overlayBounds(alignment)));
    await _safe(() => windowManager.setMinimumSize(overlaySize));
    await _safe(() => windowManager.setMaximumSize(overlaySize));
    await _safe(() => windowManager.setAlwaysOnTop(true));
    await _safe(() => windowManager.setSkipTaskbar(true));
    await _safe(() => windowManager.setAlignment(alignment));
  }

  Future<void> exitOverlayMode() async {
    if (!isDesktop || !_isOverlay) return;
    _isOverlay = false;

    await _safe(() => windowManager.setAlwaysOnTop(false));
    await _safe(() => windowManager.setSkipTaskbar(false));
    await _safe(() => windowManager.setResizable(true));
    await _safe(() => windowManager.setMinimumSize(Size.zero));
    await _safe(() => windowManager.setMaximumSize(_noLimit));
    await _safe(() => windowManager.setBounds(_normalBounds()));
    await _safe(() => windowManager.setMinimumSize(minimumSize));
    await _safe(() => windowManager.center());
  }

  Rect _overlayBounds(Alignment alignment) {
    final view = PlatformDispatcher.instance.views.first;
    final screen = Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    );

    const margin = 16.0;
    final left = alignment.x < 0
        ? screen.width - overlaySize.width - margin
        : alignment.x == 0
        ? (screen.width - overlaySize.width) / 2
        : margin;
    final top = alignment.y < 0
        ? screen.height - overlaySize.height - margin
        : margin;

    return Rect.fromLTWH(left, top, overlaySize.width, overlaySize.height);
  }

  Rect _normalBounds() {
    final view = PlatformDispatcher.instance.views.first;
    final screen = Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    );
    return Rect.fromLTWH(
      ((screen.width - initialSize.width) / 2).clamp(0, double.infinity),
      ((screen.height - initialSize.height) / 2).clamp(0, double.infinity),
      initialSize.width,
      initialSize.height,
    );
  }

  Future<void> _safe(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      debugPrint('[window] operazione non supportata: $error');
    }
  }

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> initialize() async {
    if (_initialized || !isDesktop) return;
    _initialized = true;

    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: initialSize,
      minimumSize: minimumSize,
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(_listener);
  }

  late final _WindowListener _listener = _WindowListener(
    onMaximizeChanged: (value) => _isMaximized = value,
  );

  Future<void> minimize() => windowManager.minimize();

  Future<void> toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> close() => windowManager.close();

  bool get isMaximized => _isMaximized;

  Future<void> setKeepAwake(bool enabled) async {
    if (!isDesktop) return;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (error) {
      debugPrint('[window] keep awake: $error');
    }
  }
}

class _WindowListener with WindowListener {
  _WindowListener({required this.onMaximizeChanged});

  final void Function(bool maximized) onMaximizeChanged;

  @override
  void onWindowMaximize() => onMaximizeChanged(true);

  @override
  void onWindowUnmaximize() => onMaximizeChanged(false);
}

class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowService.instance.isDesktop) return child;
    return MoveWindow(child: child);
  }
}

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    final service = WindowService.instance;
    if (!service.isDesktop) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: Icons.remove_rounded,
          tooltip: 'Minimize',
          onPressed: service.minimize,
        ),
        _ControlButton(
          icon: service.isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          tooltip: 'Maximize',
          onPressed: service.toggleMaximize,
        ),
        _ControlButton(
          icon: Icons.close_rounded,
          tooltip: 'Close',
          danger: true,
          onPressed: service.close,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: 44,
            height: 32,
            child: Icon(
              icon,
              size: 16,
              color: danger ? theme.colorScheme.error : theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
