/// Public client configuration supplied at build time. Never use a service key.
abstract final class CloudConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static String get key => publishableKey.isNotEmpty ? publishableKey : anonKey;
  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;
}
