/// إعدادات التطبيق. المفاتيح تُمرَّر عند البناء بـ --dart-define (لا أسرار هنا).
/// المفتاح العام (anon) فقط يُستعمل؛ لا يوجد أي مفتاح service_role في التطبيق.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://efibuqhuyxilvxpylhvr.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// --dart-define=DEMO_MODE=true يفرض الوضع التجريبي.
  static const demoFlag = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// بدون مفاتيح Supabase يعمل التطبيق تلقائياً بالوضع التجريبي.
  static bool get demoOnly => demoFlag || !hasBackend;

  // ---- الألوان في معالج التصميم ----
  static const minColors = 3; // الحد الأدنى المطلوب من العميل
  static const maxColors = 5; // الحد الأقصى

  // ---- حدود الطلب ----
  static const maxServices = 5;
  static const maxMockups = 5;
  static const maxUploadMb = 50;

  // ---- ساعات العمل (بتوقيت GMT) ----
  static const workStartHourGmt = 8;
  static const workHoursPerDay = 8;
  static const slaWorkingHours = 8;

  // ---- نافذة الإلغاء/التعديل المجانية ----
  static const freeWindowDays = 3;
  static const quoteValidDays = 7;

  static const allowedUploadExt = ['png', 'jpg', 'jpeg', 'pdf', 'psd', 'ai', 'zip', 'svg', 'webp'];
}
