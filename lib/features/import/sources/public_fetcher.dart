import 'dart:convert';

import 'package:dio/dio.dart';

/// A browser-like user agent, needed by the pages that serve the data of the
/// external services.
const String browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Fetches a public resource, with the headers a browser would send.
class PublicFetcher {
  PublicFetcher({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: true,
      headers: {
        'user-agent': browserUserAgent,
        'accept-language': 'en-US,en;q=0.9',
      },
    );
  }

  final Dio _dio;

  /// The body of a response, as text.
  Future<String> text(
    String url, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final response = await _dio.get<dynamic>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.plain,
        headers: headers,
      ),
    );
    final data = response.data;
    return data is String ? data : jsonEncode(data);
  }

  /// The body of a response, as JSON.
  Future<Map<String, dynamic>> json(
    String url, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final response = await _dio.get<dynamic>(
      url,
      cancelToken: cancelToken,
      options: Options(headers: headers),
    );
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }
}
