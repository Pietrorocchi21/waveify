import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'local_library_store.dart';

/// Implements the existing API contract for the library on this device.
/// It does not pretend to authenticate a cloud account or supply social data.
class LocalApiClient extends ApiClient {
  LocalApiClient(this.store);
  final LocalLibraryStore store;
  String get ownerId => 'local';
  bool get supportsPublicSharing => false;
  static const _uuid = Uuid();
  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static String _now() => DateTime.now().toUtc().toIso8601String();

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
    Duration? timeout,
    bool skipAuth = false,
  }) async {
    final segments = Uri.parse(path).pathSegments;
    final input = _map(body);
    dynamic route(Map<String, dynamic> data) {
      final tracks = _map(data['tracks']);
      final playlists = _map(data['playlists']);
      final liked = _map(data['liked']);
      final collections = _map(data['collections']);
      final history = List<dynamic>.from(data['history'] as List? ?? []);
      Map<String, dynamic> track(String id) {
        final value = tracks[id];
        if (value == null) {
          throw ApiException(404, 'Track is not in the device library.');
        }
        return _map(value);
      }

      void remember(dynamic snapshot) {
        final value = _map(snapshot);
        if ('${value['id'] ?? ''}'.isNotEmpty) {
          tracks['${value['id']}'] = {
            ..._map(tracks['${value['id']}']),
            ...value,
          };
        }
      }

      void commit() {
        data['tracks'] = tracks;
        data['playlists'] = playlists;
        data['liked'] = liked;
        data['collections'] = collections;
        data['history'] = history;
      }

      if (path.startsWith('/v1/auth/')) {
        throw ApiException(
          503,
          'Configure a cloud service to use an online account.',
          code: 'CLOUD_NOT_CONFIGURED',
        );
      }
      if (path == '/v1/me' || path == '/v1/users/me') {
        if (method == 'PATCH') {
          const fields = {'displayName', 'username', 'bio', 'avatarUrl'};
          data['user'] = {
            ..._map(data['user']),
            for (final entry in input.entries)
              if (fields.contains(entry.key)) entry.key: entry.value,
          };
        }
        return data['user'];
      }
      final albums = <String, Map<String, dynamic>>{};
      final artists = <String, Map<String, dynamic>>{};
      for (final raw in tracks.values) {
        final t = _map(raw);
        final album = _map(t['album']);
        final credits = t['artists'] is List ? t['artists'] as List : const [];
        if ('${album['id'] ?? ''}'.isNotEmpty) {
          final entry = albums.putIfAbsent(
            '${album['id']}',
            () => {
              ...album,
              'type': 'album',
              'artists': credits,
              'cover': t['cover'],
              'tracks': <dynamic>[],
              'durationMs': 0,
            },
          );
          (entry['tracks'] as List).add(t);
          entry['trackCount'] = (entry['tracks'] as List).length;
          entry['durationMs'] =
              (entry['durationMs'] as int) +
              ((t['durationMs'] as num?)?.toInt() ?? 0);
        }
        for (final rawCredit in credits) {
          final credit = _map(rawCredit);
          final id = '${credit['id'] ?? ''}';
          if (id.isEmpty || id == 'unknown') continue;
          final entry = artists.putIfAbsent(
            id,
            () => {
              ...credit,
              'type': 'artist',
              'cover': t['cover'],
              'tracks': <dynamic>[],
              'albums': <dynamic>[],
            },
          );
          (entry['tracks'] as List).add(t);
          if (albums.containsKey(album['id']) &&
              !(entry['albums'] as List).any((a) => a['id'] == album['id'])) {
            (entry['albums'] as List).add(albums[album['id']]);
          }
        }
      }
      if (segments.length == 3 && segments[1] == 'albums') {
        final album = albums[segments[2]];
        if (album == null) {
          throw ApiException(404, 'Album is not in this library.');
        }
        return album;
      }
      if (segments.length == 3 && segments[1] == 'artists') {
        final artist = artists[segments[2]];
        if (artist == null) {
          throw ApiException(404, 'Artist is not in this library.');
        }
        return artist;
      }
      if (path == '/v1/search') {
        final words = '${query?['q'] ?? ''}'.trim().toLowerCase().split(
          RegExp(r'\s+'),
        );
        final type = query?['type'] ?? 'all';
        final matches = tracks.values
            .map(_map)
            .where(
              (t) => words.every(
                (word) => '${t['title']} ${t['artists']} ${t['album']}'
                    .toLowerCase()
                    .contains(word),
              ),
            )
            .toList();
        return {
          'items': [
            for (final entity in [...albums.values, ...artists.values])
              if ((type == 'all' || type == entity['type']) &&
                  words.every(
                    (word) => '${entity['title'] ?? entity['name']}'
                        .toLowerCase()
                        .contains(word),
                  ))
                entity,
            if (type == 'all' || type == 'track')
              for (final t in matches)
                {
                  ...t,
                  'type': 'track',
                  'id': t['id'],
                  'track': t,
                  'title': t['title'],
                  'cover': t['cover'],
                },
          ],
        };
      }
      if (segments.length >= 3 && segments[1] == 'tracks') {
        final id = segments[2];
        if (segments.length == 3) return track(id);
        if (segments.last == 'stream') {
          final t = track(id);
          return {'url': t['sourceUrl'], 'durationMs': t['durationMs']};
        }
        if (segments.last == 'radio') {
          final seed = track(id);
          final exclude = {...(input['history'] as List? ?? []), id};
          final items =
              tracks.values
                  .map(_map)
                  .where((t) => !exclude.contains(t['id']))
                  .toList()
                ..sort(
                  (a, b) => (b['artists'] == seed['artists'] ? 1 : 0).compareTo(
                    a['artists'] == seed['artists'] ? 1 : 0,
                  ),
                );
          return {
            'items': items
                .take((query?['k'] as int?) ?? (input['k'] as int?) ?? 20)
                .toList(),
          };
        }
      }
      if (path == '/v1/me/library/tracks') {
        final offset = int.tryParse('${query?['cursor'] ?? 0}') ?? 0;
        final limit = int.tryParse('${query?['limit'] ?? 100}') ?? 100;
        final entries = liked.entries.toList()
          ..sort((a, b) => '${b.value}'.compareTo('${a.value}'));
        return {
          'items': entries
              .skip(offset)
              .take(limit)
              .where((e) => tracks.containsKey(e.key))
              .map((e) => {'track': tracks[e.key], 'likedAt': e.value})
              .toList(),
          'nextCursor': offset + limit < entries.length
              ? '${offset + limit}'
              : null,
        };
      }
      if (segments.length == 5 &&
          segments[1] == 'me' &&
          segments[2] == 'library') {
        final type = segments[3], id = segments[4];
        if (type == 'tracks') {
          if (method == 'PUT') {
            remember(input['track']);
            track(id);
            liked[id] = _now();
          }
          if (method == 'DELETE') liked.remove(id);
        } else {
          final key = '$type:$id';
          if (method == 'PUT') {
            final entity = type == 'albums'
                ? _map(albums[id])
                : type == 'artists'
                ? _map(artists[id])
                : _map(_map(playlists[id])['playlist']);
            collections[key] = {
              'id': id,
              'type': type,
              'title': entity['title'] ?? entity['name'] ?? id,
              'cover': entity['cover'],
              'savedAt': _now(),
            };
          }
          if (method == 'DELETE') collections.remove(key);
        }
        commit();
        return null;
      }
      if (segments.length == 4 &&
          segments[1] == 'me' &&
          segments[2] == 'library') {
        return {
          'items': collections.values
              .map(_map)
              .where((c) => c['type'] == segments.last)
              .toList(),
        };
      }
      if (path == '/v1/me/playlists') {
        if (method == 'GET') {
          return {
            'items': playlists.values.map((p) => _map(p)['playlist']).toList(),
          };
        }
        final title = '${input['title'] ?? ''}'.trim();
        if (title.isEmpty) throw ApiException(400, 'A playlist needs a title.');
        final value = {
          'id': _uuid.v4(),
          'title': title,
          'description': input['description'],
          'isPublic': supportsPublicSharing && input['isPublic'] == true,
          'ownerId': ownerId,
          'revision': 0,
          'createdAt': _now(),
          'updatedAt': _now(),
        };
        playlists['${value['id']}'] = {'playlist': value, 'items': <dynamic>[]};
        commit();
        return value;
      }
      if (segments.length >= 4 &&
          segments[1] == 'me' &&
          segments[2] == 'playlists') {
        final id = segments[3];
        if (!playlists.containsKey(id)) {
          throw ApiException(404, 'Playlist not found.');
        }
        final value = _map(playlists[id]);
        final playlist = _map(value['playlist']);
        final items = List<dynamic>.from(value['items'] as List? ?? []);
        if (segments.length == 4) {
          if (method == 'GET') return value;
          if (method == 'DELETE') {
            playlists.remove(id);
            commit();
            return null;
          }
          playlist.addAll({
            for (final e in input.entries)
              if (e.key == 'title' ||
                  e.key == 'description' ||
                  (supportsPublicSharing && e.key == 'isPublic'))
                e.key: e.value,
          });
        } else if (segments[4] == 'tracks') {
          final snapshots = segments.length == 6
              ? [input['track'] ?? tracks[segments[5]]]
              : input['tracks'] as List? ?? [];
          var added = 0, rejected = 0;
          Map<String, dynamic>? last;
          for (final raw in snapshots) {
            final t = _map(raw);
            if ('${t['id'] ?? ''}'.isEmpty) {
              rejected++;
              continue;
            }
            remember(t);
            last = {
              'id': _uuid.v4(),
              'track': t,
              'position': items.length,
              'addedAt': _now(),
            };
            items.add(last);
            added++;
          }
          playlist['revision'] = (playlist['revision'] as int? ?? 0) + 1;
          value['playlist'] = playlist;
          value['items'] = items;
          playlists[id] = value;
          commit();
          return segments.length == 6
              ? last
              : {'added': added, 'rejected': rejected};
        } else if (segments[4] == 'items' && segments.length >= 6) {
          final index = items.indexWhere(
            (item) => _map(item)['id'] == segments[5],
          );
          if (index < 0) throw ApiException(404, 'Playlist item not found.');
          if (method == 'DELETE') {
            items.removeAt(index);
          } else if (segments.last == 'move') {
            if (input['revision'] != playlist['revision']) {
              throw ApiException(409, 'Playlist changed. Reload it and retry.');
            }
            if (input['beforeItemId'] != segments[5]) {
              final item = items.removeAt(index);
              final target = input['beforeItemId'] == null
                  ? items.length
                  : items.indexWhere(
                      (e) => _map(e)['id'] == input['beforeItemId'],
                    );
              if (target < 0) throw ApiException(404, 'Target item not found.');
              items.insert(target, item);
            }
          }
        }
        playlist['revision'] = (playlist['revision'] as int? ?? 0) + 1;
        playlist['updatedAt'] = _now();
        value['playlist'] = playlist;
        value['items'] = [
          for (var i = 0; i < items.length; i++)
            {..._map(items[i]), 'position': i},
        ];
        playlists[id] = value;
        commit();
        return segments.length == 4 ? playlist : value;
      }
      if (path == '/v1/me/playback/events') {
        final id = '${input['trackId'] ?? ''}';
        if (tracks.containsKey(id)) {
          final snapshot = track(id);
          final eventId = '${input['playbackSessionId'] ?? _uuid.v4()}';
          history.removeWhere((e) => _map(e)['id'] == eventId);
          history.insert(0, {
            ...input,
            'id': eventId,
            'track': snapshot,
            'listenedAt': _now(),
          });
          if (history.length > 2000) history.removeRange(2000, history.length);
          commit();
        }
        return null;
      }
      if (path == '/v1/me/history') {
        final offset = int.tryParse('${query?['cursor'] ?? 0}') ?? 0;
        final limit = int.tryParse('${query?['limit'] ?? 30}') ?? 30;
        return {
          'items': history.skip(offset).take(limit).toList(),
          'nextCursor': offset + limit < history.length
              ? '${offset + limit}'
              : null,
        };
      }
      if (path == '/v1/explore/popular') {
        final counts = <String, int>{};
        for (final event in history.map(_map)) {
          final id = '${_map(event['track'])['id']}';
          counts[id] = (counts[id] ?? 0) + 1;
        }
        final ordered = tracks.values.map(_map).toList()
          ..sort(
            (a, b) => (counts[b['id']] ?? 0).compareTo(counts[a['id']] ?? 0),
          );
        return {
          'items': [
            for (var i = 0; i < ordered.length; i++)
              {
                'rank': i + 1,
                'track': ordered[i],
                'playCount': counts[ordered[i]['id']] ?? 0,
              },
          ],
        };
      }
      if (path == '/v1/me/recommendations/daily-mixes') {
        return {
          'items': [
            for (final p in playlists.values.map(_map))
              if ((p['items'] as List).isNotEmpty)
                {
                  ..._map(p['playlist']),
                  'tracks': (p['items'] as List)
                      .map((e) => _map(e)['track'])
                      .toList(),
                  'trackCount': (p['items'] as List).length,
                },
          ],
        };
      }
      if (segments.length >= 3 && segments[1] == 'users') {
        final user = _map(data['user']);
        if (segments[2] != ownerId &&
            segments[2] != user['username'] &&
            segments[2] != 'me') {
          throw ApiException(
            503,
            'Social profiles require a cloud account.',
            code: 'CLOUD_REQUIRED',
          );
        }
        if (segments.length == 3) {
          return {...user, 'followersCount': 0, 'followingCount': 0};
        }
        if (segments.last == 'playlists') {
          return {
            'items': playlists.values.map((p) => _map(p)['playlist']).toList(),
          };
        }
        if (segments.last == 'history') return {'items': history};
        if (segments.last == 'followers' || segments.last == 'following') {
          return <dynamic>[];
        }
      }
      throw ApiException(
        501,
        'This feature needs a configured cloud service.',
        code: 'CLOUD_REQUIRED',
      );
    }

    return method == 'GET' ? store.read(route) : store.update(route);
  }

  @override
  Future<ResponseBody> stream(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    final id = Uri.parse(path).pathSegments[2];
    final text = await store.read(
      (data) => _map(_map(data['tracks'])[id])['localLyrics'] as String?,
    );
    final events = [
      if (text != null && text.isNotEmpty)
        {
          'type': 'provider',
          'provider': 'local',
          'status': 'found',
          'candidate': {
            'provider': 'local',
            'syncLevel': 'line_level',
            'contentKind': 'line_synced',
            'lyrics': {'format': 'lrc', 'content': text},
            'quality': {'total': 100},
          },
        },
      {'type': 'done', 'status': text == null ? 'not_found' : 'found'},
    ];
    return ResponseBody.fromString(
      events.map((e) => 'data: ${jsonEncode(e)}\n\n').join(),
      200,
    );
  }
}
