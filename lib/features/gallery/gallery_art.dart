import 'package:flutter/material.dart';

import '../../shared/widgets/common.dart';
import 'gallery_catalog.dart';

Color galleryDemoTint(int? index) => switch (index) {
  0 => const Color(0xFFDD6BBB),
  1 => const Color(0xFF60C7D0),
  _ => const Color(0xFFF0A56E),
};

class GalleryArt extends StatelessWidget {
  const GalleryArt({
    super.key,
    required this.album,
    required this.size,
    this.coverOverride,
  });

  final GalleryAlbum album;
  final double size;
  final String? coverOverride;

  @override
  Widget build(BuildContext context) {
    if (!album.isDemo) {
      return CoverImage(
        url: coverOverride ?? album.cover,
        size: size,
        borderRadius: 12,
        decodeWidth: (size * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(128, 1024),
      );
    }
    final colors = switch (album.demoIndex) {
      0 => const [Color(0xFF421347), Color(0xFFDD6BBB)],
      1 => const [Color(0xFF102446), Color(0xFF60C7D0)],
      _ => const [Color(0xFF3A241D), Color(0xFFF0A56E)],
    };
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _DemoArtwork(colors),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoArtwork extends CustomPainter {
  const _DemoArtwork(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [colors.first, const Color(0xFF08080C)],
        ).createShader(bounds),
    );
    final center = Offset(size.width * .62, size.height * .45);
    final radius = size.width * .37;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [colors.last, colors.first.withValues(alpha: .15)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    for (var i = 1; i <= 9; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width * (.18 + i * .075),
          height: size.height * (.12 + i * .043),
        ),
        Paint()
          ..color = colors.last.withValues(alpha: .22 + i * .035)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_DemoArtwork oldDelegate) => oldDelegate.colors != colors;
}
