import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/local_library_store.dart';
import '../network/api_exception.dart';

/// Reads fresh account state and commits atomically against its server revision.
/// A conflicting write is surfaced; callbacks are never silently replayed.
class SupabaseLibraryStore extends LocalLibraryStore {
  SupabaseLibraryStore(this.client);
  final SupabaseClient client;
  Future<void> _tail = Future.value();

  String get userId =>
      client.auth.currentUser?.id ??
      (throw ApiException(401, 'Sign in to access your cloud library.'));

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) async {
      try {
        return await action();
      } on PostgrestException catch (error) {
        final missing = {
          '42P01',
          '42883',
          'PGRST202',
          'PGRST205',
        }.contains(error.code);
        throw ApiException(
          missing
              ? 503
              : error.code == '23505'
              ? 409
              : 503,
          missing
              ? 'Cloud library setup is missing. Apply the Waveify library migration and retry.'
              : error.code == '23505'
              ? 'This username is already taken.'
              : 'Cloud library operation failed. Retry when the service is available.',
          code: missing ? 'CLOUD_MIGRATION_REQUIRED' : error.code,
        );
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Future<Map<String, dynamic>> _snapshot() async {
    final row = await client
        .from('waveify_libraries')
        .select('revision,data')
        .eq('owner_id', userId)
        .maybeSingle();
    return row ?? {'revision': 0, 'data': LocalLibraryStore.empty()};
  }

  Map<String, dynamic> _data(Map<String, dynamic> snapshot) {
    final data = Map<String, dynamic>.from(snapshot['data'] as Map);
    final saved = Map<String, dynamic>.from(data['user'] as Map? ?? {});
    final user = client.auth.currentUser!;
    data['user'] = {
      ...saved,
      'id': user.id,
      'email': user.email,
      'username': saved['username'] == 'local'
          ? (user.userMetadata ?? {})['username']
          : saved['username'],
      'displayName': saved['id'] == 'local'
          ? (user.userMetadata ?? {})['displayName'] ?? user.email
          : saved['displayName'],
    };
    return data;
  }

  @override
  Future<T> read<T>(T Function(Map<String, dynamic>) action) =>
      _serialized(() async => action(_data(await _snapshot())));

  @override
  Future<T> update<T>(T Function(Map<String, dynamic>) action) =>
      _serialized(() async {
        final snapshot = await _snapshot();
        final data = _data(snapshot);
        final result = action(data);
        final saved = await client.rpc(
          'waveify_save_library',
          params: {
            'expected_revision': snapshot['revision'],
            'library_data': data,
          },
        );
        if (saved == null) {
          throw ApiException(
            409,
            'Library changed on another device. Reload and retry.',
            code: 'LIBRARY_CONFLICT',
          );
        }
        return result;
      });
}
