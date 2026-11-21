abstract final class AppConfig {
  static const supabaseUrl = 'https://ysvhnyhbtwvyloeqypkf.supabase.co';
  static const supabaseAnonKey =
      'sb_publishable_gZ4bfFknEqipXTDY4N8ehw_-ALl41S8';

  static const demoMode = bool.fromEnvironment('DEMO_MODE');
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get useBackend => hasSupabase && !demoMode;

  static const depositRate = 0.10;
  static const currency = 'MAD';
}
