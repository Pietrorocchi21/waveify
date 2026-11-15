import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_api_client.dart';
import '../network/api_exception.dart';
import 'supabase_library_store.dart';

class SupabaseApiClient extends LocalApiClient {
  SupabaseApiClient(this.client, {this.refreshTokenProvider})
    : super(SupabaseLibraryStore(client));
  final SupabaseClient client;
  final String? Function()? refreshTokenProvider;

  @override
  bool get supportsPublicSharing => true;

  @override
  String get ownerId => client.auth.currentUser?.id ?? '';

  Future<void> _restore() async {
    if (client.auth.currentSession != null) return;
    final token = refreshTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      await client.auth.setSession(token);
    }
    if (client.auth.currentUser == null) {
      throw ApiException(401, 'Sign in to access your cloud account.');
    }
  }

  Future<Map<String, dynamic>> _tokens(AuthResponse response) async {
    final session = response.session;
    if (session == null) {
      throw ApiException(
        403,
        'Confirm your email before signing in.',
        code: 'EMAIL_CONFIRMATION_REQUIRED',
      );
    }
    return {
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'expiresAt': session.expiresAt,
      'user': await store.read((data) => data['user']),
    };
  }

  /// Resolve artwork on copies of API results. Library transport locations stay
  /// canonical, so the next read can obtain fresh credentials after expiry.
  Future<dynamic> _artwork(
    dynamic value,
    Map<String, Future<String>> signed, {
    String? key,
    bool inCover = false,
  }) async {
    if (value is List) {
      return Future.wait(value.map((item) => _artwork(item, signed)));
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final name = '${entry.key}';
        result[name] = await _artwork(
          entry.value,
          signed,
          key: name,
          inCover: name == 'cover' || (inCover && name != 'sourceUrl'),
        );
      }
      return result;
    }
    final artwork =
        key == 'coverUrl' ||
        key == 'avatarUrl' ||
        key == 'cover' ||
        (inCover && (key == 'url' || key == 'fallbackUrl'));
    if (artwork && value is String && value.startsWith('storage://')) {
      return await signed.putIfAbsent(value, () {
        final uri = Uri.parse(value);
        return client.storage
            .from(uri.host)
            .createSignedUrl(uri.pathSegments.join('/'), 3600);
      });
    }
    return value;
  }

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
    try {
      final result = await _request(
        path,
        method: method,
        body: body,
        query: query,
        allowRefresh: allowRefresh,
        timeout: timeout,
        skipAuth: skipAuth,
      );
      return await _artwork(result, {});
    } on StorageException catch (error) {
      throw ApiException(
        int.tryParse(error.statusCode ?? '') ?? 503,
        error.message,
        code: 'MEDIA_STORAGE_ERROR',
      );
    }
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
    Duration? timeout,
    bool skipAuth = false,
  }) async {
    try {
      final input = body is Map
          ? Map<String, dynamic>.from(body)
          : <String, dynamic>{};
      if (path == '/v1/auth/login') {
        return await _tokens(
          await client.auth.signInWithPassword(
            email: input['email'] as String,
            password: input['password'] as String,
          ),
        );
      }
      if (path == '/v1/auth/register') {
        return await _tokens(
          await client.auth.signUp(
            email: input['email'] as String,
            password: input['password'] as String,
            data: {
              'username': input['username'],
              'displayName': input['displayName'],
            },
          ),
        );
      }
      if (path == '/v1/auth/refresh') {
        return await _tokens(
          await client.auth.setSession(input['refreshToken'] as String),
        );
      }
      await _restore();
      if (path == '/v1/auth/logout') {
        await client.auth.signOut(scope: SignOutScope.local);
        return null;
      }
      final segments = Uri.parse(path).pathSegments;
      if ((path == '/v1/me' || path == '/v1/users/me') && method == 'PATCH') {
        const fields = {
          'displayName',
          'username',
          'bio',
          'avatarUrl',
          'isPublic',
          'showActivity',
          'showHistory',
          'showLikedTracks',
          'participateLeaderboards',
        };
        return await store.update((data) {
          data['user'] = {
            ...Map<String, dynamic>.from(data['user'] as Map),
            for (final entry in input.entries)
              if (fields.contains(entry.key)) entry.key: entry.value,
          };
          return data['user'];
        });
      }
      if (segments.length >= 3 && segments[1] == 'users') {
        final handle = segments[2];
        final own = handle == ownerId || handle == 'me';
        final row = own
            ? null
            : await client
                  .from('waveify_profiles')
                  .select()
                  .eq(
                    RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(handle)
                        ? 'id'
                        : 'username',
                    handle,
                  )
                  .maybeSingle();
        if (!own && row == null) {
          throw ApiException(404, 'Public profile not found.');
        }
        final id = own ? ownerId : row!['id'] as String;
        if (segments.length == 3) {
          final profile = own
              ? await store.read((data) => data['user'])
              : row!['data'];
          final followers = await client
              .from('waveify_follows')
              .select('follower_id')
              .eq('followed_id', id);
          final following = await client
              .from('waveify_follows')
              .select('followed_id')
              .eq('follower_id', id);
          return {
            ...Map<String, dynamic>.from(profile as Map),
            'followersCount': followers.length,
            'followingCount': following.length,
            'isFollowing': followers.any(
              (item) => item['follower_id'] == ownerId,
            ),
          };
        }
        if (segments.last == 'follow') {
          if (method == 'DELETE') {
            await client
                .from('waveify_follows')
                .delete()
                .eq('follower_id', ownerId)
                .eq('followed_id', id);
          } else if (method == 'POST' || method == 'PUT') {
            await client.from('waveify_follows').upsert({
              'follower_id': ownerId,
              'followed_id': id,
            }, ignoreDuplicates: true);
          } else {
            throw ApiException(405, 'Use POST or DELETE to change a follow.');
          }
          return null;
        }
        if (segments.last == 'followers' || segments.last == 'following') {
          final followers = segments.last == 'followers';
          final links = await client
              .from('waveify_follows')
              .select()
              .eq(followers ? 'followed_id' : 'follower_id', id);
          final ids = links
              .map(
                (row) =>
                    row[followers ? 'follower_id' : 'followed_id'] as String,
              )
              .toList();
          if (ids.isEmpty) return <dynamic>[];
          final profiles = await client
              .from('waveify_profiles')
              .select('data')
              .inFilter('id', ids);
          return profiles.map((row) => row['data']).toList();
        }
        if (!own && method != 'GET') {
          throw ApiException(403, 'Only the owner can edit this library.');
        }
        if (!own && segments.last == 'playlists') {
          final rows = await client
              .from('waveify_public_playlists')
              .select('data')
              .eq('owner_id', id);
          return {
            'items': rows
                .map((row) => (row['data'] as Map)['playlist'])
                .toList(),
          };
        }
        if (!own && segments.last == 'history') {
          final shared = await client
              .from('waveify_public_history')
              .select('data')
              .eq('owner_id', id)
              .maybeSingle();
          if (shared == null) {
            throw ApiException(403, 'This listening history is private.');
          }
          final items = shared['data'] as List;
          final offset = (int.tryParse('${query?['cursor'] ?? 0}') ?? 0).clamp(
            0,
            items.length,
          );
          final limit = (int.tryParse('${query?['limit'] ?? 30}') ?? 30).clamp(
            1,
            100,
          );
          return {
            'items': items.skip(offset).take(limit).toList(),
            'nextCursor': offset + limit < items.length
                ? '${offset + limit}'
                : null,
          };
        }
        if (!own) {
          throw ApiException(404, 'Profile resource not found.');
        }
        path = '/v1/me/${segments.skip(3).join('/')}';
      }
      if (segments.length >= 3 && segments[1] == 'leaderboards') {
        return await client.rpc(
          'waveify_leaderboard',
          params: {
            'artist_id': segments.length == 4 && segments[2] == 'artist'
                ? segments[3]
                : null,
            'selected_period': query?['period'] ?? 'weekly',
            'result_limit': int.tryParse('${query?['limit'] ?? 20}') ?? 20,
          },
        );
      }
      if (method == 'GET' &&
          segments.length == 4 &&
          segments[1] == 'me' &&
          segments[2] == 'playlists') {
        final own = await store.read(
          (data) => (data['playlists'] as Map)[segments[3]],
        );
        if (own == null) {
          final shared = await client
              .from('waveify_public_playlists')
              .select('data')
              .eq('id', segments[3])
              .maybeSingle();
          if (shared == null) {
            throw ApiException(404, 'Playlist not found or private.');
          }
          return shared['data'];
        }
      }
      final result = await super.request(
        path,
        method: method,
        body: body,
        query: query,
        allowRefresh: allowRefresh,
        timeout: timeout,
        skipAuth: skipAuth,
      );
      if (segments.length == 4 &&
          segments[1] == 'tracks' &&
          segments.last == 'stream' &&
          result is Map) {
        final uri = Uri.tryParse('${result['url'] ?? ''}');
        if (uri?.scheme == 'storage') {
          return {
            ...result,
            'url': await client.storage
                .from(uri!.host)
                .createSignedUrl(uri.pathSegments.join('/'), 3600),
          };
        }
        if (uri?.scheme != 'https' && uri?.scheme != 'http') {
          throw ApiException(
            422,
            'Upload this audio file to play it on another device.',
            code: 'MEDIA_NOT_UPLOADED',
          );
        }
      }
      return result;
    } on AuthException catch (error) {
      throw ApiException(
        int.tryParse(error.statusCode ?? '') ?? 401,
        error.message,
        code: error.code,
      );
    } on PostgrestException catch (error) {
      throw ApiException(
        503,
        'Cloud library unavailable. Apply the Waveify library migration and retry.',
        code: error.code,
      );
    } on StorageException catch (error) {
      throw ApiException(
        int.tryParse(error.statusCode ?? '') ?? 503,
        error.message,
        code: 'MEDIA_STORAGE_ERROR',
      );
    }
  }

  /// Called only for an explicit upload; persists bytes in the private bucket.
  Future<String> uploadTrack(
    Uint8List bytes, {
    required String filename,
    String contentType = 'application/octet-stream',
  }) async {
    await _restore();
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$ownerId/${const Uuid().v4()}/$safeName';
    await client.storage
        .from('waveify_media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return 'storage://waveify_media/$path';
  }
}
