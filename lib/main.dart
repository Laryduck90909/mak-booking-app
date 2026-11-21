import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config.dart';
import 'core/state.dart';
import 'data/catalog.dart';
import 'data/demo_repo.dart';
import 'data/supabase_repo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.loadPrefs();
  await Catalog.load();

  if (AppConfig.demoOnly) {
    repo = DemoRepo();
  } else {
    try {
      await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
      repo = SupabaseRepo();
    } catch (_) {
      // تعذّرت التهيئة (مفاتيح خاطئة؟) → وضع تجريبي بدل شاشة بيضاء
      repo = DemoRepo();
    }
  }
  runApp(const MakApp());
}
