// Test-only artwork and in-memory cache; no images or music are added to the app.
// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class ArtworkFixtureCache extends Fake implements BaseCacheManager {
  ArtworkFixtureCache(this.images);
  final Map<String, Uint8List> images;
  final fs = MemoryFileSystem();
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final bytes = images[url];
    if (bytes == null) throw StateError('Unexpected artwork fixture: $url');
    final file = fs.file('/${Uri.parse(url).pathSegments.last}')
      ..writeAsBytesSync(bytes);
    yield FileInfo(file, FileSource.Cache, DateTime(2100), url);
  }
}

Future<Map<String, Uint8List>> createArtworkFixtures() async {
  final result = <String, Uint8List>{};
  final palettes = [
    [
      const ui.Color(0xFF152335),
      const ui.Color(0xFF4C91A8),
      const ui.Color(0xFFC9DAE2),
    ],
    [
      const ui.Color(0xFF2C1733),
      const ui.Color(0xFFBF6544),
      const ui.Color(0xFFF0C28A),
    ],
    [
      const ui.Color(0xFF0C2626),
      const ui.Color(0xFF3C726A),
      const ui.Color(0xFFA8C1A7),
    ],
  ];
  for (var i = 0; i < 3; i++) {
    final colors = palettes[i];
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const bounds = ui.Rect.fromLTWH(0, 0, 512, 512);
    canvas.drawRect(
      bounds,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          const ui.Offset(512, 512),
          [colors[0], colors[1]],
        ),
    );
    canvas.drawCircle(
      ui.Offset(330, 170 + i * 25),
      90,
      ui.Paint()
        ..shader = ui.Gradient.radial(ui.Offset(330, 170 + i * 25), 90, [
          colors[2],
          colors[1].withValues(alpha: 0.2),
        ]),
    );
    for (var j = 0; j < 18; j++) {
      final y = 220.0 + j * 20;
      final path = ui.Path()
        ..moveTo(-50, y)
        ..cubicTo(150, y - 190 + i * 50, 300, y + 170, 560, y - 80)
        ..lineTo(560, 560)
        ..lineTo(-50, 560)
        ..close();
      canvas.drawPath(
        path,
        ui.Paint()..color = colors[0].withValues(alpha: 0.07 + j * 0.025),
      );
    }
    final label =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'Roboto',
              fontSize: 50,
              fontWeight: ui.FontWeight.w500,
            ),
          )
          ..pushStyle(ui.TextStyle(color: colors[2], letterSpacing: -1.5))
          ..addText(['Between\nthe waves', 'Blue\nroom', 'Slow\nmotion'][i]);
    final text = label.build()
      ..layout(const ui.ParagraphConstraints(width: 400));
    canvas.drawParagraph(text, const ui.Offset(40, 40));
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 512);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    result['https://waveify.fixture/$i.png'] = bytes!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  }
  return result;
}
