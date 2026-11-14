/// Runtime configuration for the Waveify client.
///
/// Values come from `--dart-define` at build time, e.g.
///   flutter run --dart-define=API_URL=http://localhost:1337
///   flutter run --dart-define=COVERS_PROXY_URL=https://images.example.com
class AppConfig {
  AppConfig._();

  static const String defaultPrimaryApi = '';
  static const String defaultCoversProxy = '';

  static const Set<String> _loopbackHosts = {
    'localhost',
    '127.0.0.1',
    '[::1]',
  };

  static const String _rawApiUrl =
      String.fromEnvironment('API_URL', defaultValue: defaultPrimaryApi);
  static const String _rawCoversProxyUrl = String.fromEnvironment(
    'COVERS_PROXY_URL',
    defaultValue: defaultCoversProxy,
  );
  static const String _clientVersion = String.fromEnvironment(
    'CLIENT_VERSION',
    defaultValue: '1.0.0-flutter',
  );

  /// Only HTTPS (or plain HTTP on loopback) is accepted. If no backend is
  /// configured, the app intentionally stays in offline/local-first mode.
  static String resolveApiBaseUrl(String? envUrl) {
    final clean = envUrl?.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean != null && clean.isNotEmpty && isSecureBaseUrl(clean)) return clean;
    return defaultPrimaryApi;
  }

  static bool isSecureBaseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme == 'http') {
      return _loopbackHosts.contains(uri.host.toLowerCase());
    }
    return false;
  }

  static String get apiBaseUrl => resolveApiBaseUrl(_rawApiUrl);

  static String get coversProxyUrl => _rawCoversProxyUrl.trim().isEmpty
      ? defaultCoversProxy
      : _rawCoversProxyUrl.trim();

  static bool get hasConfiguredBackend => apiBaseUrl.trim().isNotEmpty;

  static String get clientVersion => _clientVersion;

  /// Resolves a media path against the API base URL.
  static String mediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = apiBaseUrl;
    return path.startsWith('/') ? '$base$path' : '$base/$path';
  }
}
