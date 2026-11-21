import 'package:mak_booking/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseService {
  static Future<void> init() async {
    if (!AppConfig.useBackend) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
