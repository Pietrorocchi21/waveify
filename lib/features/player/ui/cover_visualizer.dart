import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

import '../../../shared/widgets/common.dart';

/// The animated background of the player, built from the cover art.
///
/// The cover is tinted with the current accent color through a procedural
/// fragment shader: the mix amount follows a time-driven wave, so the whole
/// background subtly breathes with the playback.
class CoverVisualizer extends StatefulWidget {
  const CoverVisualizer({
    super.key,
    required this.coverUrl,
    this.tint = const Color(0xFFFF3B3B),
  });

  final String coverUrl;
  final Color tint;

  @override
  State<CoverVisualizer> createState() => _CoverVisualizerState();
}

class _CoverVisualizerState extends State<CoverVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      (context, shader, child) {
        return AnimatedSampler(
          (image, size, canvas) {
            final time = _controller.value * 60;
            shader
              ..setFloat(0, time)
              ..setFloat(1, 1 / size.width)
              ..setFloat(2, widget.tint.r)
              ..setFloat(3, widget.tint.g)
              ..setFloat(4, widget.tint.b)
              ..setImageSampler(0, image);

            canvas.drawRect(
              Offset.zero & size,
              Paint()..shader = shader,
            );
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      assetKey: 'shaders/cover_ambient.frag',
      child: _CoverTexture(url: widget.coverUrl),
    );
  }
}

/// The cover, drawn as the source of the shader.
class _CoverTexture extends StatelessWidget {
  const _CoverTexture({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return SizedBox.expand(
      child: CoverImage(url: url, borderRadius: 0),
    );
  }
}
