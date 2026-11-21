import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repo.dart';
import '../models/models.dart';

/// المستودع الحالي (حقيقي أو تجريبي) — يُحدَّد في main().
late Repo repo;

class AppState extends ChangeNotifier {
  String lang = 'ar';
  bool dark = true;
  Profile? profile;

  /// منظور المدير: '' = لوحة المدير، 'staff' = كموظف، 'client' = كعميل (عرض فقط).
  String viewAs = '';
  bool canEditPrices = false;
  bool booting = true;

  String get realRole => profile?.role ?? 'none';
  String get role => (realRole == 'admin' && viewAs.isNotEmpty) ? viewAs : realRole;
  bool get signedIn => profile != null;

  Future<void> loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      lang = p.getString('lang') ?? 'ar';
      dark = p.getBool('dark') ?? true;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('lang', lang);
      await p.setBool('dark', dark);
    } catch (_) {}
  }

  void setLang(String l) {
    lang = l;
    _save();
    notifyListeners();
  }

  void toggleTheme() {
    dark = !dark;
    _save();
    notifyListeners();
  }

  void setProfile(Profile? p) {
    profile = p;
    viewAs = '';
    notifyListeners();
  }

  /// تحديث بيانات الملف الشخصي مع إبقاء منظور المدير الحالي.
  void refreshProfile(Profile p) {
    profile = p;
    notifyListeners();
  }

  void setViewAs(String v) {
    viewAs = v;
    notifyListeners();
  }

  void setBooting(bool b) {
    booting = b;
    notifyListeners();
  }

  void setCanEditPrices(bool v) {
    canEditPrices = v;
    notifyListeners();
  }
}

final appState = AppState();
