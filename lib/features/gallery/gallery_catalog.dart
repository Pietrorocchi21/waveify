import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';
import '../collection/ui/collection_page.dart';

class GalleryAlbum {
  const GalleryAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.cover = '',
    this.year,
    this.demoIndex,
  });

  final String id;
  final String title;
  final String artist;
  final String cover;
  final int? year;
  final int? demoIndex;

  bool get isDemo => demoIndex != null;
}

const demoAlbums = [
  GalleryAlbum(
    id: 'demo-violet',
    title: 'Violet Hours',
    artist: 'Waveify Demo',
    demoIndex: 0,
  ),
  GalleryAlbum(
    id: 'demo-tides',
    title: 'Glass Tides',
    artist: 'Waveify Demo',
    demoIndex: 1,
  ),
  GalleryAlbum(
    id: 'demo-orbit',
    title: 'Quiet Orbit',
    artist: 'Waveify Demo',
    demoIndex: 2,
  ),
];

Future<CatalogCollection> loadDemoAlbum(GalleryAlbum album) async {
  final directory = await getTemporaryDirectory();
  final index = album.demoIndex!;
  final file = File('${directory.path}/waveify-gallery-v1-$index.wav');
  if (!await file.exists()) {
    final data = await rootBundle.load('assets/demo/room-$index.wav');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
  return CatalogCollection(
    type: 'demo',
    id: album.id,
    title: album.title,
    subtitle: album.artist,
    tracks: [
      Track(
        id: 'gallery-demo:${album.id}',
        title: album.title,
        artists: album.artist,
        sourceUrl: file.uri.toString(),
        durationMs: 6000,
      ),
    ],
    durationMs: 6000,
  );
}
