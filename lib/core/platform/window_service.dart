import 'dart:io';
import 'dart:math' as math;

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../theme/app_theme.dart';

class WindowService {
  WindowService._();

  static final WindowService instance = WindowService._();

  bool _initialized = false;
  bool _isMaximized = false;

  static const Size initialSize = Size(1200, 780);
  static const Size minimumSize = Size(400, 560);

  static const Size overlaySize = Size(420, 88);

  static const Size _noLimit = Size(-1, -1);

  bool _isOverlay = false;
  Rect? _previousBounds;
  bool _previousMaximized = false;

  bool get isOverlay => _isOverlay;

  Future<void> enterOverlayMode({
    Alignment alignment = Alignment.topRight,
  }) async {
    if (!isDesktop) return;
    if (_isOverlay) {
      await _safe(
        () async => windowManager.setBounds(await _overlayBounds(alignment)),
      );
      return;
    }
    _previousMaximized = _isMaximized;
    if (!_previousMaximized) {
      await _safe(
        () async => _previousBounds = await windowManager.getBounds(),
      );
    }
    _isOverlay = true;

    await _safe(() => windowManager.unmaximize());
    await _safe(() => windowManager.setMinimumSize(Size.zero));
    await _safe(() => windowManager.setMaximumSize(_noLimit));
    await _safe(
      () async => windowManager.setBounds(await _overlayBounds(alignment)),
    );
    await _safe(() => windowManager.setMinimumSize(overlaySize));
    await _safe(() => windowManager.setMaximumSize(overlaySize));
    await _safe(() => windowManager.setResizable(false));
    await _safe(() => windowManager.setMaximizable(false));
    await _safe(() => windowManager.setAlwaysOnTop(true));
    await _safe(() => windowManager.setSkipTaskbar(true));
  }

  Future<void> exitOverlayMode() async {
    if (!isDesktop || !_isOverlay) return;
    _isOverlay = false;

    await _safe(() => windowManager.setAlwaysOnTop(false));
    await _safe(() => windowManager.setSkipTaskbar(false));
    await _safe(() => windowManager.setResizable(true));
    await _safe(() => windowManager.setMaximizable(true));
    await _safe(() => windowManager.setMinimumSize(Size.zero));
    await _safe(() => windowManager.setMaximumSize(_noLimit));
    await _safe(
      () async =>
          windowManager.setBounds(_previousBounds ?? await _normalBounds()),
    );
    await _safe(() => windowManager.setMinimumSize(minimumSize));
    if (_previousMaximized) await _safe(() => windowManager.maximize());
    _previousBounds = null;
  }

  Future<Rect> _workArea() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay().timeout(
        const Duration(seconds: 2),
      );
      return (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size);
    } catch (_) {
      final view = PlatformDispatcher.instance.views.first;
      return Offset.zero &
          Size(
            view.physicalSize.width / view.devicePixelRatio,
            view.physicalSize.height / view.devicePixelRatio,
          );
    }
  }

  Future<Rect> _overlayBounds(Alignment alignment) async {
    final work = await _workArea();
    const margin = 16.0;
    return Rect.fromLTWH(
      work.left +
          margin +
          math.max(0, work.width - overlaySize.width - margin * 2) *
              (alignment.x + 1) /
              2,
      work.top +
          margin +
          math.max(0, work.height - overlaySize.height - margin * 2) *
              (alignment.y + 1) /
              2,
      overlaySize.width,
      overlaySize.height,
    );
  }

  Future<Rect> _normalBounds() async {
    final work = await _workArea();
    final width = math.min(initialSize.width, math.max(320.0, work.width - 32));
    final height = math.min(
      initialSize.height,
      math.max(320.0, work.height - 32),
    );
    return Rect.fromLTWH(
      work.left + (work.width - width) / 2,
      work.top + (work.height - height) / 2,
      width,
      height,
    );
  }

  Future<bool> fitsWorkArea() async {
    if (!isDesktop) return true;
    final work = await _workArea();
    final bounds = await windowManager.getBounds();
    const tolerance = 2.0;
    return bounds.left >= work.left - tolerance &&
        bounds.top >= work.top - tolerance &&
        bounds.right <= work.right + tolerance &&
        bounds.bottom <= work.bottom + tolerance;
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

    final bounds = await _normalBounds();
    final options = WindowOptions(
      size: bounds.size,
      minimumSize: Size(
        math.min(minimumSize.width, bounds.width),
        math.min(minimumSize.height, bounds.height),
      ),
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
