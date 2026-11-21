import 'package:flutter/material.dart';
import 'config.dart';
import 'i18n.dart';

extension ColorX on Color {
  /// شفافية دون استعمال APIs قديمة/متغيّرة
  Color fade(double o) => withAlpha((o.clamp(0.0, 1.0) * 255).round());
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String fmtNum(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

String fmtMad(num v) => '${fmtNum(v)} ${t('د.م.', 'MAD')}';

String fmtDate(DateTime? d) => d == null ? '—' : '${d.year}-${_two(d.month)}-${_two(d.day)}';

String fmtDateTime(DateTime? d) => d == null ? '—' : '${fmtDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

String fmtMonth(DateTime d) => '${d.year}-${_two(d.month)}';

String relTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return t('الآن', 'now');
  if (diff.inMinutes < 60) return t('منذ ${diff.inMinutes} د', '${diff.inMinutes}m ago');
  if (diff.inHours < 24) return t('منذ ${diff.inHours} س', '${diff.inHours}h ago');
  return t('منذ ${diff.inDays} يوم', '${diff.inDays}d ago');
}

/// عدد ساعات العمل (8 ساعات/يوم بتوقيت GMT) بين لحظتين.
double workingHoursBetween(DateTime from, DateTime to) {
  var a = from.toUtc();
  final b = to.toUtc();
  if (!b.isAfter(a)) return 0;
  var total = 0.0;
  var day = DateTime.utc(a.year, a.month, a.day);
  var guard = 0;
  while (day.isBefore(b) && guard < 400) {
    final ws = day.add(const Duration(hours: AppConfig.workStartHourGmt));
    final we = ws.add(const Duration(hours: AppConfig.workHoursPerDay));
    final s = a.isAfter(ws) ? a : ws;
    final e = b.isBefore(we) ? b : we;
    if (e.isAfter(s)) total += e.difference(s).inMinutes / 60.0;
    day = day.add(const Duration(days: 1));
    guard++;
  }
  return total;
}

/// استخراج رسالة مفهومة من أي خطأ.
String errMsg(Object e) {
  var s = e.toString();
  try {
    final dyn = e as dynamic;
    final m = dyn.message;
    if (m is String && m.isNotEmpty) s = m;
  } catch (_) {}
  final low = s.toLowerCase();
  if (low.contains('invalid login credentials')) return t('البريد أو كلمة المرور غير صحيحة', 'Wrong email or password');
  if (low.contains('email not confirmed')) return t('لم يتم تأكيد البريد بعد — افتح رسالة التأكيد في بريدك', 'Email not confirmed yet');
  if (low.contains('user already registered')) return t('هذا البريد مسجّل مسبقاً', 'Email already registered');
  if (low.contains('row-level security') || low.contains('not allowed') || low.contains('permission denied')) {
    return t('ليست لديك صلاحية لهذا الإجراء', 'You do not have permission for this action');
  }
  if (low.contains('failed host lookup') || low.contains('socketexception') || low.contains('clientexception') || low.contains('xmlhttprequest')) {
    return t('لا يوجد اتصال بالإنترنت', 'No internet connection');
  }
  if (low.contains('signed contracts are immutable')) return t('العقد الموقّع لا يمكن تعديله', 'Signed contracts cannot be edited');
  return s.replaceFirst('Exception: ', '');
}

bool looksOffline(Object e) {
  final low = e.toString().toLowerCase();
  return low.contains('failed host lookup') || low.contains('socketexception') || low.contains('clientexception') ||
      low.contains('xmlhttprequest') || low.contains('connection closed') || low.contains('network is unreachable') ||
      low.contains('connection refused') || low.contains('timed out');
}

bool isWide(BuildContext c) => MediaQuery.of(c).size.width >= 900;

int pct(int amount, int percent) => (amount * percent / 100).round();
