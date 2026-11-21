import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../utils/json.dart';
import 'api_exception.dart';

/// Thin, typed wrapper over the Waveify backend.
///
/// Requests remain generic and use standard Authorization headers. The app
/// no longer depends on a custom request signer or proprietary signing protocol.
class ApiClient {
  ApiClient({
    Dio? dio,
    this._tokenProvider,
    this._onRefreshSession,
  }) {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            responseType: ResponseType.json,
            headers: {'accept': 'application/json'},
          ),
        );
  }

  late final Dio _dio;
  final Future<String?> Function()? _tokenProvider;
  final Future<bool> Function()? _onRefreshSession;

  final Map<String, Future<dynamic>> _inFlightGetRequests = {};
  final Random _random = Random();

  /// Called when a request fails: the connectivity feature uses it to trip
  /// the diagnostics wall.
  void Function({
    required String method,
    required String path,
    int? status,
    String? code,
    int latencyMs,
  })?
  onFailure;

  Dio get raw => _dio;

  /// Performs a request, handling auth, timeouts and 401 retries.
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
    Duration? timeout,
    bool skipAuth = false,
  }) async {
    final key = '$method::$path::${query ?? const {}}';
    if (method == 'GET') {
      final existing = _inFlightGetRequests[key];
      if (existing != null) return existing;
      final future =
          _execute<dynamic>(
            path,
            method: method,
            body: body,
            query: query,
            allowRefresh: allowRefresh,
            timeout: timeout,
            skipAuth: skipAuth,
          ).whenComplete(() {
            _inFlightGetRequests.remove(key);
          });
      _inFlightGetRequests[key] = future;
      return future;
    }

    return _execute<dynamic>(
      path,
      method: method,
      body: body,
      query: query,
      allowRefresh: allowRefresh,
      timeout: timeout,
      skipAuth: skipAuth,
    );
  }

  Future<T> _execute<T>(
    String path, {
    required String method,
    Object? body,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
    Duration? timeout,
    bool skipAuth = false,
  }) async {
    var token = skipAuth ? null : await _tokenProvider?.call();

    Future<Response<dynamic>> send(String? accessToken) {
      final headers = <String, dynamic>{
        'x-client-version': AppConfig.clientVersion,
        'x-platform': _platformName,
        'x-request-id': _nextRequestId(),
        if (body != null) 'content-type': 'application/json',
        if (accessToken != null) 'authorization': 'Bearer $accessToken',
      };

      return _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: headers,
        ),
      );
    }

    final started = DateTime.now();
    Response<dynamic> response;
    try {
      response = await send(token);
    } on DioException catch (err) {
      if (err.response?.statusCode == 401 &&
          allowRefresh &&
          !path.startsWith('/v1/auth/')) {
        final refreshed = await _onRefreshSession?.call() ?? false;
        if (refreshed) {
          try {
            response = await send(await _tokenProvider?.call());
          } on DioException catch (retryError) {
            throw _mapDioError(retryError);
          }
        } else {
          final mapped = _mapDioError(err);
          _reportFailure(path, method, mapped, started);
          throw mapped;
        }
      } else {
        final mapped = _mapDioError(err);
        _reportFailure(path, method, mapped, started);
        throw mapped;
      }
    }

    if (response.statusCode == 401 &&
        allowRefresh &&
        !path.startsWith('/v1/auth/')) {
      final refreshed = await _onRefreshSession?.call() ?? false;
      if (refreshed) {
        final newToken = await _tokenProvider?.call();
        try {
          response = await send(newToken);
        } on DioException catch (err) {
          throw _mapDioError(err);
        }
      }
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final map = asRecord(response.data);
      final requestId =
          response.headers.value('x-request-id') ??
          asStringOrNull(map?['reqId']) ??
          asStringOrNull(map?['requestId']);
      throw ApiException(
        status,
        asStringOrNull(map?['message']) ??
            asStringOrNull(map?['error']) ??
            response.statusMessage ??
            'Request failed',
        code: asStringOrNull(map?['code']),
        requestId: requestId,
      );
    }

    if (status == 204 || response.data == null) return null as T;
    if (response.data is String && (response.data as String).isEmpty) {
      return null as T;
    }
    return response.data as T;
  }

  void _reportFailure(
    String path,
    String method,
    ApiException error,
    DateTime started,
  ) {
    onFailure?.call(
      method: method,
      path: path,
      status: error.status == 0 ? null : error.status,
      code: error.code,
      latencyMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  String _nextRequestId() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer('req-');
    for (var i = 0; i < 16; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  ApiException _mapDioError(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException(
          0,
          'Request timed out. Please check your network connection.',
          code: 'TIMEOUT_ERROR',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ApiException(
          0,
          'Network error. Unable to reach server.',
          code: 'NETWORK_ERROR',
        );
      case DioExceptionType.badResponse:
        final response = err.response;
        final map = asRecord(response?.data);
        return ApiException(
          response?.statusCode ?? 0,
          asStringOrNull(map?['message']) ??
              asStringOrNull(map?['error']) ??
              'Request failed',
          code: asStringOrNull(map?['code']),
          requestId: response?.headers.value('x-request-id'),
        );
      case DioExceptionType.cancel:
        return ApiException(0, 'Request cancelled.', code: 'CANCELLED');
    }
  }

  /// Performs a streaming request and returns the raw response body.
  ///
  /// The request is signed exactly like a regular one; the difference is that
  /// the body is delivered incrementally, which the lyrics endpoint needs.
  ///
  /// Note: dio returns a [ResponseBody] for a streamed response, the byte
  /// stream is available through `ResponseBody.stream`.
  Future<ResponseBody> stream(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    final token = await _tokenProvider?.call();
    final response = await _dio.get<dynamic>(
      path,
      queryParameters: query,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {if (token != null) 'authorization': 'Bearer $token'},
      ),
    );

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(status, 'Streaming request failed with HTTP $status.');
    }

    final data = response.data;
    if (data is ResponseBody) return data;
    throw ApiException(status, 'The streaming response was not readable.');
  }
}
