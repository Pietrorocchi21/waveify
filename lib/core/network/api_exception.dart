/// Error raised by the Waveify API client.
class ApiException implements Exception {
  ApiException(
    this.status,
    this.message, {
    this.code,
    this.requestId,
  });

  final int status;
  final String message;
  final String? code;
  final String? requestId;

  bool get isNetworkError => status == 0;
  bool get isUnauthorized => status == 401 || status == 403;
  bool get isNotFound => status == 404;
  bool get isRateLimited => status == 429;
  bool get isServerError => status >= 500;

  String? get traceInfo => requestId == null ? null : '[reqId: $requestId]';

  @override
  String toString() =>
      'ApiException($status${code != null ? ', $code' : ''}): $message';
}
