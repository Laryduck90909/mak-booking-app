import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../data/supabase_repo.dart';

/// استعادة الجلسة عند فتح التطبيق (Supabase يحفظ الجلسة محلياً).
Future<void> restoreSession() async {
  try {
    if (repo.userId != null) {
      await completeLogin();
    }
  } catch (_) {
    try {
      await repo.signOut();
    } catch (_) {}
  }
  appState.setBooting(false);
}

/// بعد نجاح تسجيل الدخول: تحميل الملف الشخصي والتحقق من الحساب.
Future<void> completeLogin() async {
  final p = await repo.currentProfile();
  if (p == null) {
    await repo.signOut();
    throw Exception(t(
      'تم إنشاء الحساب لكن الملف الشخصي لم يُنشأ بعد. أعد المحاولة بعد قليل أو تواصل مع M.A.K.',
      'Account created but the profile is not ready yet. Try again shortly or contact M.A.K.',
    ));
  }
  if (!p.active) {
    await repo.signOut();
    throw Exception(t('الحساب موقوف، تواصل مع M.A.K', 'Account suspended, contact M.A.K'));
  }
  if (p.role == 'staff') {
    appState.setCanEditPrices(await repo.myCanEditPrices());
  } else {
    appState.setCanEditPrices(p.role == 'admin');
  }
  appState.setProfile(p);
  if (p.isStaffOrAdmin) {
    repo.expireQuotes();
  }
  final r = repo;
  if (r is SupabaseRepo) r.flushOutbox();
}

Future<void> logout() async {
  await repo.signOut();
  appState.setProfile(null);
}
