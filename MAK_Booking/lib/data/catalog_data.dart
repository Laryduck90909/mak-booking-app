import 'package:mak_booking/models/design_request.dart';

class CatalogOption {
  const CatalogOption(this.id, this.ar, this.en);
  final String id;
  final String ar;
  final String en;
  String title(String locale) => locale == 'ar' ? ar : en;
}

class BriefQuestion {
  const BriefQuestion(this.id, this.ar, this.en);
  final String id;
  final String ar;
  final String en;
  String title(String locale) => locale == 'ar' ? ar : en;
}

abstract final class CatalogData {
  static const categories = [
    'identity',
    'social',
    'print',
    'packaging',
    'digital'
  ];

  static const _serviceRows = <(String, String, String, double)>[
    ('identity', 'شعار أساسي', 'Primary logo', 300),
    ('identity', 'شعار مع دليل استخدام', 'Logo with usage guide', 700),
    ('identity', 'هوية بصرية متكاملة', 'Complete visual identity', 1800),
    ('identity', 'إعادة تصميم الشعار', 'Logo redesign', 300),
    ('identity', 'نظام ألوان العلامة', 'Brand colour system', 700),
    ('identity', 'نظام الخطوط', 'Typography system', 1800),
    ('identity', 'أيقونات مخصصة', 'Custom icon set', 300),
    ('identity', 'نمط بصري', 'Brand pattern', 700),
    ('identity', 'دليل الهوية الموسع', 'Extended brand guidelines', 1800),
    ('identity', 'تصميم شعار متحرك', 'Animated logo', 300),
    ('identity', 'تسمية العلامة', 'Brand naming', 700),
    ('identity', 'استراتيجية الهوية', 'Identity strategy', 1800),
    ('identity', 'بطاقة أعمال', 'Business card', 300),
    ('identity', 'ورق رسمي وظرف', 'Letterhead and envelope', 700),
    ('identity', 'حزمة إطلاق العلامة', 'Brand launch package', 1800),
    ('social', 'تصميم منشور واحد', 'Single social post', 300),
    ('social', 'حزمة 10 منشورات', '10-post package', 700),
    ('social', 'حملة اجتماعية متكاملة', 'Full social campaign', 1800),
    ('social', 'تصميم قصة', 'Story design', 300),
    ('social', 'حزمة قوالب قصص', 'Story template pack', 700),
    ('social', 'خطة محتوى بصرية', 'Visual content plan', 1800),
    ('social', 'غلاف حساب', 'Profile cover', 300),
    ('social', 'قوالب منشورات قابلة للتعديل', 'Editable post templates', 700),
    ('social', 'هوية حساب متكاملة', 'Complete account identity', 1800),
    ('social', 'تصميم إعلان', 'Advertisement design', 300),
    ('social', 'حزمة إعلانات', 'Advertising pack', 700),
    ('social', 'حملة إطلاق منتج', 'Product launch campaign', 1800),
    ('social', 'أغلفة الهايلايت', 'Highlight covers', 300),
    ('social', 'تقويم محتوى شهري', 'Monthly content calendar', 700),
    ('social', 'إدارة بصرية شهرية', 'Monthly visual management', 1800),
    ('print', 'بروشور ثنائي الطي', 'Bi-fold brochure', 300),
    ('print', 'بروشور متعدد الصفحات', 'Multi-page brochure', 700),
    ('print', 'كتالوج منتجات', 'Product catalogue', 1800),
    ('print', 'ملصق إعلاني', 'Poster', 300),
    ('print', 'قائمة طعام', 'Menu design', 700),
    ('print', 'تقرير سنوي', 'Annual report', 1800),
    ('print', 'بطاقة دعوة', 'Invitation card', 300),
    ('print', 'مجلة أو مطوية فاخرة', 'Premium magazine or leaflet', 700),
    ('print', 'كتاب مطبوع كامل', 'Complete printed book', 1800),
    ('print', 'لوحة إعلانية', 'Billboard', 300),
    ('print', 'مطبوعات فعالية', 'Event print collateral', 700),
    ('print', 'هوية معرض متكاملة', 'Complete exhibition identity', 1800),
    ('print', 'شهادة وتقدير', 'Certificate design', 300),
    ('print', 'ملف صحفي', 'Press kit', 700),
    ('print', 'مطبوعات مؤسسية شاملة', 'Corporate print suite', 1800),
    ('packaging', 'ملصق منتج', 'Product label', 300),
    ('packaging', 'تصميم علبة', 'Box design', 700),
    ('packaging', 'نظام تغليف متكامل', 'Complete packaging system', 1800),
    ('packaging', 'كيس تسوق', 'Shopping bag', 300),
    ('packaging', 'تغليف مجموعة منتجات', 'Product range packaging', 700),
    ('packaging', 'تغليف فاخر', 'Luxury packaging', 1800),
    ('packaging', 'غلاف أكواب', 'Cup sleeve', 300),
    ('packaging', 'تغليف أغذية', 'Food packaging', 700),
    ('packaging', 'خط تغليف لمستحضرات تجميل', 'Cosmetics packaging line', 1800),
    ('packaging', 'بطاقة داخل العلبة', 'In-box card', 300),
    ('packaging', 'علبة اشتراك', 'Subscription box', 700),
    (
      'packaging',
      'تجربة فتح علبة متكاملة',
      'Complete unboxing experience',
      1800
    ),
    ('packaging', 'ملصق ختم', 'Seal sticker', 300),
    ('packaging', 'تغليف هدية', 'Gift packaging', 700),
    ('packaging', 'هوية منتج وتغليف', 'Product identity and packaging', 1800),
    ('digital', 'بانر ويب', 'Web banner', 300),
    ('digital', 'واجهة صفحة هبوط', 'Landing page UI', 700),
    ('digital', 'واجهة موقع متكاملة', 'Complete website UI', 1800),
    ('digital', 'أيقونة تطبيق', 'App icon', 300),
    ('digital', 'واجهات تطبيق أساسية', 'Core app screens', 700),
    ('digital', 'نظام تصميم رقمي', 'Digital design system', 1800),
    ('digital', 'عرض تقديمي', 'Presentation design', 300),
    ('digital', 'قالب عرض متكامل', 'Complete presentation template', 700),
    ('digital', 'تجربة مستخدم وواجهات منتج', 'Product UX and UI', 1800),
    ('digital', 'إنفوجرافيك', 'Infographic', 300),
    ('digital', 'لوحة معلومات', 'Dashboard UI', 700),
    ('digital', 'منصة رقمية متكاملة', 'Complete digital platform UI', 1800),
    ('digital', 'توقيع بريد إلكتروني', 'Email signature', 300),
    ('digital', 'نشرة بريدية', 'Email newsletter', 700),
    ('digital', 'هوية رقمية شاملة', 'Complete digital identity', 1800),
  ];

  static final services = List<RequestItem>.generate(_serviceRows.length, (i) {
    final row = _serviceRows[i];
    return RequestItem(
      key: 'service_${i + 1}',
      titleAr: row.$2,
      titleEn: row.$3,
      unitPrice: row.$4,
    );
  });

  static String categoryOf(String key) =>
      _serviceRows[int.parse(key.split('_').last) - 1].$1;

  static const _mockupBases = <CatalogOption>[
    CatalogOption('card', 'بطاقة أعمال', 'Business card'),
    CatalogOption('bag', 'حقيبة تسوق', 'Shopping bag'),
    CatalogOption('box', 'علبة منتج', 'Product box'),
    CatalogOption('bottle', 'عبوة', 'Bottle'),
    CatalogOption('cup', 'كوب', 'Cup'),
    CatalogOption('phone', 'هاتف', 'Phone'),
    CatalogOption('laptop', 'حاسوب محمول', 'Laptop'),
    CatalogOption('sign', 'لوحة واجهة', 'Storefront sign'),
    CatalogOption('billboard', 'لوحة إعلانية', 'Billboard'),
    CatalogOption('shirt', 'قميص', 'T-shirt'),
    CatalogOption('cap', 'قبعة', 'Cap'),
    CatalogOption('paper', 'ورق رسمي', 'Letterhead'),
    CatalogOption('book', 'كتاب', 'Book'),
    CatalogOption('brochure', 'بروشور', 'Brochure'),
    CatalogOption('poster', 'ملصق', 'Poster'),
    CatalogOption('packaging', 'تغليف', 'Packaging'),
    CatalogOption('screen', 'شاشة رقمية', 'Digital screen'),
  ];
  static const _mockupScenes = <CatalogOption>[
    CatalogOption('studio', 'استوديو', 'Studio'),
    CatalogOption('street', 'خارجي', 'Outdoor'),
    CatalogOption('minimal', 'بسيط', 'Minimal'),
    CatalogOption('premium', 'فاخر', 'Premium'),
  ];

  static final mockups = List<CatalogOption>.generate(68, (i) {
    final base = _mockupBases[i ~/ 4];
    final scene = _mockupScenes[i % 4];
    return CatalogOption(
      'mockup_${i + 1}',
      '${base.ar} — ${scene.ar}',
      '${base.en} — ${scene.en}',
    );
  });

  static const styles = <CatalogOption>[
    CatalogOption('minimal', 'بسيط', 'Minimal'),
    CatalogOption('luxury', 'فاخر', 'Luxury'),
    CatalogOption('bold', 'جريء', 'Bold'),
    CatalogOption('graphity', 'Graphity', 'Graphity'),
    CatalogOption('modern', 'عصري', 'Modern'),
    CatalogOption('classic', 'كلاسيكي', 'Classic'),
    CatalogOption('organic', 'عضوي', 'Organic'),
    CatalogOption('geometric', 'هندسي', 'Geometric'),
    CatalogOption('retro', 'ريترو', 'Retro'),
    CatalogOption('futuristic', 'مستقبلي', 'Futuristic'),
    CatalogOption('playful', 'مرح', 'Playful'),
    CatalogOption('editorial', 'تحريري', 'Editorial'),
    CatalogOption('brutalist', 'بروتالي', 'Brutalist'),
    CatalogOption('elegant', 'أنيق', 'Elegant'),
    CatalogOption('industrial', 'صناعي', 'Industrial'),
    CatalogOption('artistic', 'فني', 'Artistic'),
    CatalogOption('tech', 'تقني', 'Tech'),
    CatalogOption('vintage', 'قديم', 'Vintage'),
    CatalogOption('clean', 'نظيف', 'Clean'),
  ];

  static const briefQuestions = <BriefQuestion>[
    BriefQuestion('q01', 'ما اسم المشروع أو العلامة؟',
        'What is the project or brand name?'),
    BriefQuestion('q02', 'ماذا يقدم المشروع؟', 'What does the project offer?'),
    BriefQuestion('q03', 'ما القصة المختصرة وراء الفكرة؟',
        'What is the short story behind the idea?'),
    BriefQuestion('q04', 'من الجمهور الأساسي؟', 'Who is the primary audience?'),
    BriefQuestion('q05', 'ما أعمار الجمهور واهتماماته؟',
        'What are the audience ages and interests?'),
    BriefQuestion('q06', 'في أي أسواق تعمل؟', 'Which markets do you serve?'),
    BriefQuestion('q07', 'من أهم المنافسين؟', 'Who are your main competitors?'),
    BriefQuestion('q08', 'ما الذي يميزك عنهم؟', 'What differentiates you?'),
    BriefQuestion(
        'q09', 'ما الهدف الأساسي من التصميم؟', 'What is the main design goal?'),
    BriefQuestion('q10', 'ما الانطباع الذي تريد تركه؟',
        'What impression should it leave?'),
    BriefQuestion('q11', 'هل لديك شعار حالي؟ اذكر ما تحبه وما تريد تغييره.',
        'Do you have a logo? What works and what should change?'),
    BriefQuestion('q12', 'ما الكلمات التي تصف شخصية العلامة؟',
        'Which words describe the brand personality?'),
    BriefQuestion('q13', 'هل هناك رموز يجب استخدامها أو تجنبها؟',
        'Are there symbols to use or avoid?'),
    BriefQuestion('q14', 'ما الألوان المفضلة أو الممنوعة؟',
        'Are there preferred or forbidden colours?'),
    BriefQuestion('q15', 'اذكر علامات تعجبك بصرياً ولماذا.',
        'Name visual brands you admire and why.'),
    BriefQuestion('q16', 'أين سيظهر التصميم أساساً؟',
        'Where will the design appear most?'),
    BriefQuestion('q17', 'ما المقاسات أو الصيغ المطلوبة؟',
        'Which sizes or formats are required?'),
    BriefQuestion(
        'q18', 'ما النصوص التي يجب تضمينها؟', 'Which copy must be included?'),
    BriefQuestion(
        'q19', 'هل المحتوى النهائي جاهز؟', 'Is the final content ready?'),
    BriefQuestion('q20', 'هل توجد صور أو أصول متوفرة؟',
        'Do you have images or existing assets?'),
    BriefQuestion('q21', 'ما تاريخ التسليم المطلوب؟',
        'What is the required delivery date?'),
    BriefQuestion('q22', 'هل هناك موعد إطلاق مرتبط بالمشروع؟',
        'Is there a related launch date?'),
    BriefQuestion('q23', 'من سيعتمد التصميم؟', 'Who will approve the design?'),
    BriefQuestion('q24', 'ما أولوياتك: السرعة أم التفاصيل أم التجريب؟',
        'Prioritise speed, detail or experimentation.'),
    BriefQuestion('q25', 'ما الميزانية المتوقعة إن وُجدت؟',
        'What is the expected budget, if any?'),
    BriefQuestion('q26', 'هل تحتاج ملفات قابلة للتعديل؟',
        'Do you need editable source files?'),
    BriefQuestion('q27', 'هل تحتاج نسخاً بلغات أخرى؟',
        'Do you need additional language versions?'),
    BriefQuestion('q28', 'كيف ستقيس نجاح التصميم؟',
        'How will you measure design success?'),
    BriefQuestion('q29', 'هل توجد اشتراطات قانونية أو طباعية؟',
        'Are there legal or print requirements?'),
    BriefQuestion('q30', 'أضف أي تفاصيل أخرى تساعدنا.',
        'Add anything else that will help us.'),
  ];

  static const palette = <String>[
    '0B3B3A',
    'FFCCBF',
    'D9A441',
    '7A3E65',
    '315C8C',
    'C8553D',
    '2D6A4F',
    'F4A261',
    '6D597A',
    '222222',
    'F5F0E6',
    '8CB369',
  ];
}
