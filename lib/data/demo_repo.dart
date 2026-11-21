import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import '../models/models.dart';
import 'catalog.dart';
import 'repo.dart';

/// مستودع تجريبي بالذاكرة: يحاكي قواعد قاعدة البيانات (القبول، التوقيع، الدفع...)
/// لتجربة اللوحات الثلاث دون Supabase.
class DemoRepo implements Repo {
  final _changes = StreamController<void>.broadcast();
  final _rnd = Random(7);
  String? _uid;
  int _seqOrder = 0, _seqContract = 0, _seqInvoice = 0, _id = 0;

  late final List<Profile> _profiles;
  final List<Order> _orders = [];
  final List<Quote> _quotes = [];
  final List<Contract> _contracts = [];
  final List<Payment> _payments = [];
  final List<Invoice> _invoices = [];
  final List<ChatMsg> _msgs = [];
  final List<Map<String, dynamic>> _notifs = []; // {user, n}
  final List<ChangeRequest> _changeReqs = [];
  final List<Expense> _expenses = [];
  final List<ScoreEntry> _scores = [];
  final List<Assignment> _assign = [];
  final List<AuditRow> _audit = [];
  final Map<String, List<FileRef>> _files = {};
  final Map<String, bool> _perm = {'u-staff1': true, 'u-staff2': false};
  CompanySettings _settings = CompanySettings(
    companyName: 'M.A.K', accountHolder: 'M.A.K (تجريبي)', bankName: 'بريد بنك', rib: '000 000 0000000000000000 00',
    email: 'contact@mak.demo', phone: '+212 600 000 000', whatsapp: '212600000000', city: 'Casablanca',
  );
  final List<PriceTier> _tiers = [
    PriceTier(code: 'small', labelAr: 'صغير', labelEn: 'Small', price: 150),
    PriceTier(code: 'medium', labelAr: 'متوسط', labelEn: 'Medium', price: 350),
    PriceTier(code: 'large', labelAr: 'كبير', labelEn: 'Large', price: 700),
    PriceTier(code: 'premium', labelAr: 'مميّز', labelEn: 'Premium', price: 950),
  ];
  late List<BriefQuestion> _brief;
  late List<ContractTemplate> _templates;

  DemoRepo() {
    _profiles = [
      Profile(id: 'u-admin', email: 'admin@mak.demo', fullName: 'المدير (تجريبي)', role: 'admin'),
      Profile(id: 'u-staff1', email: 'yassine@mak.demo', fullName: 'ياسين — مصمم', role: 'staff', canEditPrices: true),
      Profile(id: 'u-staff2', email: 'salma@mak.demo', fullName: 'سلمى — كاتبة ومترجمة', role: 'staff'),
      Profile(id: 'u-client1', email: 'sara@client.demo', fullName: 'سارة المنصوري', role: 'client', phone: '+212 611 000 001'),
      Profile(id: 'u-client2', email: 'karim@client.demo', fullName: 'كريم بنعلي', role: 'client'),
      Profile(id: 'u-client3', email: 'nour@client.demo', fullName: 'شركة نور للتسويق', role: 'client'),
    ];
    _brief = List<BriefQuestion>.from(Catalog.briefQuestions);
    _templates = [
      ContractTemplate(id: 't-design', section: 'design', title: 'عقد خدمة تصميم M.A.K', bodyAr: Catalog.contractAr, bodyEn: Catalog.contractEn),
      ContractTemplate(id: 't-web', section: 'web', title: 'عقد خدمة برمجة M.A.K', bodyAr: Catalog.contractAr, bodyEn: Catalog.contractEn),
      ContractTemplate(id: 't-writing', section: 'writing', title: 'عقد خدمة كتابة M.A.K', bodyAr: Catalog.contractAr, bodyEn: Catalog.contractEn),
    ];
    _seed();
  }

  // ---------------------------------------------------------------- مساعدات
  void _emit() => _changes.add(null);
  String _nid() => 'd${++_id}';
  Profile _p(String id) => _profiles.firstWhere((p) => p.id == id, orElse: () => _profiles.first);
  Profile get _me => _p(_uid ?? 'u-admin');
  bool get _isAdmin => _me.role == 'admin';
  bool get _isStaff => _me.role == 'admin' || _me.role == 'staff';
  Map<String, int> get _tierMap => {for (final x in _tiers) x.code: x.price};

  String _code() {
    while (true) {
      final c = (10000 + _rnd.nextInt(90000)).toString();
      if (!_orders.any((o) => o.verificationCode == c)) return c;
    }
  }

  String _two(int n) => n.toString().padLeft(4, '0');
  void _notify(String user, String type, String title, String body, String link) {
    _notifs.insert(0, {
      'user': user,
      'n': AppNotification(id: _nid(), type: type, title: title, body: body, link: link, createdAt: DateTime.now()),
    });
  }

  void _notifyRole(bool adminOnly, String type, String title, String body, String link) {
    for (final p in _profiles) {
      if (p.role == 'admin' || (!adminOnly && p.role == 'staff')) _notify(p.id, type, title, body, link);
    }
  }

  void _log(String action, String entity, String id) {
    _audit.insert(0, AuditRow(action: action, entity: entity, entityId: id, actorName: _me.display, createdAt: DateTime.now()));
  }

  void _setOrder(Order o) {
    final i = _orders.indexWhere((x) => x.id == o.id);
    if (i >= 0) _orders[i] = o;
  }

  Order _ord(String id) => _orders.firstWhere((o) => o.id == id);

  Map<String, dynamic> _answers(String brand) => {
        'q01': brand, 'q02': 'تجارة إلكترونية', 'q03': 'عصرية، دافئة وقريبة من الناس', 'q04': 'لا — أحتاج واحدة',
        'q05': '#0B3B3A و #FFCCBF', 'q06': 'للمصمم', 'q07': 'تسويق', 'q08': 'إنستغرام والمتجر الإلكتروني',
        'q09': '3', 'q10': '2026-12-10', 'q11': '22-40 — الجنسان', 'q12': 'الموضة، التسوق عبر الهاتف',
        'q13': 'المغرب — العربية والفرنسية', 'q14': 'جودة بسعر عادل', 'q15': brand, 'q16': 'ودّية',
        'q17': 'نعم', 'q18': 'علامات مينيماليست أنيقة', 'q19': 'الألوان الصاخبة', 'q20': 'الأحمر الفاقع',
        'q21': 'Minimalist', 'q22': 'نظيف وواضح', 'q23': 'خطوط بسيطة', 'q24': ['PNG', 'PDF', 'SVG'],
        'q25': '1080×1080 و A4', 'q26': 'نعم', 'q27': ['AI', 'Figma'], 'q28': 'الشعار القديم مرفق',
        'q29': 'صاحبة المشروع — مراجع واحد', 'q30': 'نعم، يمكن عرض العمل',
      };

  Map<String, dynamic> _designPayload(List<String> keys, List<String> mockups, String style, List<Map<String, String>> colors, String brand) {
    final sel = keys.map((k) => Catalog.item(k)).whereType<CatalogItem>().toList();
    final pr = priceItems(sel, _tierMap);
    return {
      ...pr,
      'section': 'design', 'mockups': mockups, 'style': style, 'colors': colors,
      'brief_answers': _answers(brand), 'client_note': '', 'version': 2,
    };
  }

  // ---------------------------------------------------------------- بيانات أولية
  void _seed() {
    final now = DateTime.now();
    final colors = [
      {'format': 'hex', 'value': '#0B3B3A', 'name': 'تركواز الشركة'},
      {'format': 'hex', 'value': '#FFCCBF', 'name': 'خوخي'},
      {'format': 'rgb', 'value': '255, 255, 255', 'name': 'أبيض'},
      {'format': 'cmyk', 'value': '81, 19, 20, 77', 'name': ''},
    ];

    Order mk(String clientId, String section, String title, String status, Map<String, dynamic> payload, int total, int deposit, int daysAgo, {DateTime? started, double hoursAgo = 0}) {
      _seqOrder++;
      final c = _p(clientId);
      return Order(
        id: 'MAK-2026-${_two(_seqOrder)}', clientId: clientId, section: section, title: title, status: status,
        verificationCode: _code(), payload: payload, totalMad: total, depositMad: deposit,
        createdAt: now.subtract(Duration(days: daysAgo, minutes: (hoursAgo * 60).round())), executionStartedAt: started,
        clientName: c.fullName, clientEmail: c.email,
      );
    }

    // 1 — قيد التنفيذ، عقد موقّع، عربون مؤكَّد
    final o1 = mk('u-client1', 'design', 'تصميم — شعار + بطاقة عمل — سارة المنصوري',
        'in_progress', _designPayload(['logo', 'business_card'], ['business_card', 'letterhead', 'tshirt'], 'minimalist', colors, 'Sara Atelier'),
        1200, 120, 3, started: now.subtract(const Duration(days: 1)));
    // 2 — عرض سعر مُرسل بانتظار العميل
    final o2 = mk('u-client2', 'design', 'تصميم — فلاير + بوستر — كريم بنعلي', 'quoted',
        _designPayload(['flyer', 'poster'], ['poster_wall', 'flyer'], 'modern', colors.sublist(0, 3), 'Karim Events'), 0, 0, 2);
    // 3 — ويب جديد
    final o3 = mk('u-client1', 'web', 'ويب — متجر إلكتروني — سارة المنصوري', 'new', {
      'section': 'web', 'service_type': 'website', 'platforms': <String>[], 'description': 'متجر إلكتروني لبيع الحقائب اليدوية مع دفع عند الاستلام.',
      'goals': 'رفع المبيعات وعرض الكتالوج', 'pages': 'الرئيسية، المنتجات، من نحن، اتصل بنا', 'colors': colors.sublist(0, 3),
      'language': 'laisser_mak', 'ui_language': 'ar', 'estimate_total': 0, 'needs_manual_pricing': true, 'version': 2,
    }, 0, 0, 0, hoursAgo: 3);
    // 4 — كتابة، عقد بانتظار العميل
    final o4 = mk('u-client3', 'writing', 'كتابة — ترجمة كتيّب تعريفي — شركة نور', 'contract_pending', {
      'section': 'writing', 'mode': 'translation', 'from_lang': 'ar', 'to_lang': 'fr', 'word_count': 3200,
      'description': 'كتيّب تعريفي للشركة', 'estimate_total': 0, 'needs_manual_pricing': true, 'version': 2,
    }, 1600, 0, 4);
    // 5 — معاينة أُرسلت
    final o5 = mk('u-client3', 'design', 'تصميم — بوستر + ملصق — شركة نور', 'preview_sent',
        _designPayload(['poster', 'sticker'], ['poster_frame', 'sticker'], 'graphity', colors, 'Nour Marketing'), 500, 50, 9,
        started: now.subtract(const Duration(days: 6)));
    // 6 — مكتمل
    final o6 = mk('u-client2', 'design', 'تصميم — كيس رقائق — كريم بنعلي', 'completed',
        _designPayload(['chips'], ['chips_bag'], 'playful', colors, 'Karim Snacks'), 350, 35, 30, started: now.subtract(const Duration(days: 25)));
    // 7 — جديد + مقترح سعر متغير بانتظار المدير
    final o7 = mk('u-client1', 'design', 'تصميم — عبوة عطر — سارة المنصوري', 'new',
        _designPayload(['perfume'], ['perfume_bottle', 'product_box'], 'luxury', colors, 'Sara Parfums'), 0, 0, 1);
    // 8 — ملغى
    final o8 = mk('u-client2', 'writing', 'كتابة — مقال تسويقي — كريم بنعلي', 'cancelled', {
      'section': 'writing', 'mode': 'authoring', 'kind': 'مقال', 'topic': 'التسويق الرقمي', 'estimate_total': 0, 'needs_manual_pricing': true, 'version': 2,
    }, 400, 40, 14);
    // طلبات قديمة مكتملة (لتظهر مدخولات الأشهر السابقة في المحاسبة)
    final o9 = mk('u-client3', 'design', 'تصميم — شعار — شركة نور', 'completed',
        _designPayload(['logo'], ['billboard'], 'corporate', colors, 'Nour'), 950, 95, 75, started: now.subtract(const Duration(days: 70)));
    final o10 = mk('u-client2', 'design', 'تصميم — بروشور — كريم بنعلي', 'completed',
        _designPayload(['brochure'], ['brochure'], 'modern', colors, 'Karim'), 700, 70, 45, started: now.subtract(const Duration(days: 40)));
    _orders.addAll([o10, o9, o8, o7, o6, o5, o4, o3, o2, o1]);

    // عروض الأسعار
    Quote q(String order, int base, int delta, String status, String note, {int proposedDaysAgo = 1}) => Quote(
          id: _nid(), orderId: order, status: status, note: note, baseTotal: base, delta: delta, finalTotal: base + delta,
          proposedBy: 'u-staff1', approvedBy: status == 'pending_approval' ? null : 'u-admin',
          validUntil: status == 'pending_approval' ? null : now.add(const Duration(days: 5)), createdAt: now.subtract(Duration(days: proposedDaysAgo)),
        );
    _quotes.addAll([
      q(o1.id, 1300, -100, 'accepted', 'خصم عميل جديد', proposedDaysAgo: 3),
      q(o2.id, 700, 0, 'sent', ''),
      q(o4.id, 1600, 0, 'accepted', 'سعر الكلمة 0.5 درهم', proposedDaysAgo: 4),
      q(o5.id, 500, 0, 'accepted', '', proposedDaysAgo: 9),
      q(o6.id, 350, 0, 'accepted', '', proposedDaysAgo: 30),
      q(o7.id, 950, -50, 'pending_approval', 'عميلة متكررة — خصم رمزي'),
    ]);

    // عقود
    final (ar1, en1) = _txt(o1);
    _seqContract++;
    _contracts.add(Contract(
      id: 'CON-2026-${_two(_seqContract)}', orderId: o1.id, status: 'signed', rendered_ar: ar1, rendered_en: en1,
      clientSignature: 'demo', adminSignature: 'demo', signedAt: now.subtract(const Duration(days: 1)), createdAt: now.subtract(const Duration(days: 2)),
    ));
    final (ar4, en4) = _txt(o4);
    _seqContract++;
    _contracts.add(Contract(
      id: 'CON-2026-${_two(_seqContract)}', orderId: o4.id, status: 'awaiting_client', rendered_ar: ar4, rendered_en: en4, createdAt: now.subtract(const Duration(hours: 5)),
    ));
    final (ar5, en5) = _txt(o5);
    _seqContract++;
    _contracts.add(Contract(
      id: 'CON-2026-${_two(_seqContract)}', orderId: o5.id, status: 'signed', rendered_ar: ar5, rendered_en: en5,
      clientSignature: 'demo', adminSignature: 'demo', signedAt: now.subtract(const Duration(days: 6)), createdAt: now.subtract(const Duration(days: 7)),
    ));

    // دفعات وفواتير
    void pay(Order o, String kind, int amount, int daysAgo) {
      _payments.add(Payment(
        id: _nid(), orderId: o.id, kind: kind, method: 'bank', amount: amount, receiptPath: '${o.id}/receipt.jpg',
        confirmedBy: 'u-staff1', confirmedAt: now.subtract(Duration(days: daysAgo)), createdAt: now.subtract(Duration(days: daysAgo + 1)),
      ));
    }

    pay(o1, 'deposit', 120, 1);
    pay(o5, 'deposit', 50, 6);
    pay(o6, 'deposit', 35, 25);
    pay(o6, 'full', 315, 20);
    for (final o in [o1, o5, o6]) {
      _seqInvoice++;
      _invoices.add(Invoice(
        id: 'INV-2026-${_two(_seqInvoice)}', orderId: o.id, clientName: o.clientName,
        lines: [{'label': o.title, 'amount': o.totalMad}], total: o.totalMad,
        status: o.id == o6.id ? 'paid' : 'issued', issuedAt: now.subtract(const Duration(days: 1)),
      ));
    }

    // رسائل
    void msg(Order o, String sender, String body, double hoursAgo) {
      final p = _p(sender);
      _msgs.add(ChatMsg(id: _nid(), orderId: o.id, senderId: sender, body: body, senderName: p.fullName, senderRole: p.role, createdAt: now.subtract(Duration(minutes: (hoursAgo * 60).round()))));
    }

    msg(o1, 'u-client1', 'مرحباً، هل يمكن أن يكون الشعار بدرجة تركوازية أغمق؟', 20);
    msg(o1, 'u-staff1', 'أكيد! سأجهّز نسختين للمقارنة غداً.', 18);
    msg(o2, 'u-staff1', 'أرسلتُ لكم عرض السعر، صالح 7 أيام.', 40);
    msg(o4, 'u-client3', 'هل ستكون الترجمة مراجعة لغوياً؟', 6);
    msg(o4, 'u-staff2', 'نعم، تُراجَع قبل التسليم. العقد بانتظار توقيعكم.', 5);

    // تعيينات ونقاط
    _assign.addAll([
      Assignment(employeeId: 'u-staff1', orderId: o1.id, role: 'designer'),
      Assignment(employeeId: 'u-staff1', orderId: o5.id, role: 'designer'),
      Assignment(employeeId: 'u-staff1', orderId: o6.id, role: 'designer'),
      Assignment(employeeId: 'u-staff2', orderId: o4.id, role: 'translator'),
    ]);
    _scores.add(ScoreEntry(employeeId: 'u-staff1', orderId: o6.id, managerRating: 9, clientRating: 5));

    // مصاريف
    for (var m = 0; m < 4; m++) {
      final d = DateTime(now.year, now.month - m, 5);
      _expenses.add(Expense(id: _nid(), accountCode: '5300', description: 'اشتراكات برامج التصميم', method: 'bank', date: d, amount: 450));
      _expenses.add(Expense(id: _nid(), accountCode: '5200', description: 'راتب موظف', method: 'bank', date: d, amount: 1800));
    }
    pay(o9, 'full', 950, 68);
    pay(o10, 'full', 700, 38);

    // إشعارات أولية
    _notify('u-client1', 'quote', 'عرض سعر جديد', 'تم إرسال عرض سعر لطلبك ${o1.id}', '/orders/${o1.id}');
    _notify('u-admin', 'quote', 'مقترح سعر بانتظارك', 'اقترح الموظف تعديل سعر للطلب ${o7.id}', '/orders/${o7.id}');
    _notify('u-staff1', 'message', 'رسالة جديدة من العميل', 'رسالة جديدة على الطلب ${o1.id}', '/orders/${o1.id}');
  }

  (String, String) _txt(Order o) {
    final r = buildContractTexts_(o);
    return (r.$1, r.$2);
  }

  (String, String) buildContractTexts_(Order o) {
    // نص مختصر للبيانات الأولية؛ العقود الجديدة تُبنى من القالب الكامل.
    final ar = Catalog.contractAr
        .replaceAll('{{ORDER_ID}}', o.id)
        .replaceAll('{{COMPANY_NAME}}', _settings.companyName)
        .replaceAll('{{COMPANY_CITY}}', _settings.city)
        .replaceAll('{{COMPANY_EMAIL}}', _settings.email)
        .replaceAll('{{CLIENT_NAME}}', o.clientName)
        .replaceAll('{{CLIENT_EMAIL}}', o.clientEmail)
        .replaceAll('{{TOTAL}}', '${o.totalMad} د.م.')
        .replaceAll('{{DEPOSIT}}', '${(o.totalMad * 0.1).round()} د.م.')
        .replaceAll('{{DATE}}', DateTime.now().toIso8601String().substring(0, 10))
        .replaceAll('{{SCOPE}}', o.title)
        .replaceAll('{{SECTION_NOTE}}', '')
        .replaceAll('{{REVISIONS}}', '2')
        .replaceAll('{{CANCEL_FINE}}', '10')
        .replaceAll('{{MODIFY_FEE}}', '5');
    final en = Catalog.contractEn
        .replaceAll('{{ORDER_ID}}', o.id)
        .replaceAll('{{COMPANY_NAME}}', _settings.companyName)
        .replaceAll('{{COMPANY_CITY}}', _settings.city)
        .replaceAll('{{COMPANY_EMAIL}}', _settings.email)
        .replaceAll('{{CLIENT_NAME}}', o.clientName)
        .replaceAll('{{CLIENT_EMAIL}}', o.clientEmail)
        .replaceAll('{{TOTAL}}', '${o.totalMad} MAD')
        .replaceAll('{{DEPOSIT}}', '${(o.totalMad * 0.1).round()} MAD')
        .replaceAll('{{DATE}}', DateTime.now().toIso8601String().substring(0, 10))
        .replaceAll('{{SCOPE}}', o.title)
        .replaceAll('{{SECTION_NOTE}}', '')
        .replaceAll('{{REVISIONS}}', '2')
        .replaceAll('{{CANCEL_FINE}}', '10')
        .replaceAll('{{MODIFY_FEE}}', '5');
    final cid = 'CON-2026-${_two(_seqContract + 1)}';
    return (ar.replaceAll('{{CONTRACT_ID}}', cid), en.replaceAll('{{CONTRACT_ID}}', cid));
  }

  // ---------------------------------------------------------------- Repo
  @override
  Stream<void> get changes => _changes.stream;
  @override
  String? get userId => _uid;
  @override
  bool get isDemo => true;

  @override
  Future<SignUpResult> signUp(String email, String password, String fullName) async {
    final p = Profile(id: _nid(), email: email, fullName: fullName, role: 'client');
    _profiles.add(p);
    _uid = p.id;
    return SignUpResult.signedIn;
  }

  @override
  Future<void> signIn(String email, String password) async {
    final p = _profiles.where((x) => x.email == email).toList();
    if (p.isEmpty) throw Exception('Invalid login credentials');
    _uid = p.first.id;
  }

  @override
  Future<void> demoSignIn(String role) async {
    _uid = role == 'admin' ? 'u-admin' : (role == 'staff' ? 'u-staff1' : 'u-client1');
  }

  @override
  Future<void> signOut() async {
    _uid = null;
  }

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<Profile?> currentProfile() async => _uid == null ? null : _me;

  @override
  Future<List<Profile>> listProfiles() async => List<Profile>.from(_profiles);

  @override
  Future<void> setRole(String userId, String role) async {
    final i = _profiles.indexWhere((p) => p.id == userId);
    if (i < 0) return;
    final o = _profiles[i];
    _profiles[i] = Profile(id: o.id, email: o.email, fullName: o.fullName, role: role, phone: o.phone, active: o.active);
    _log('UPDATE', 'profiles', userId);
    _emit();
  }

  @override
  Future<void> setActive(String userId, bool active) async {
    final i = _profiles.indexWhere((p) => p.id == userId);
    if (i < 0) return;
    final o = _profiles[i];
    _profiles[i] = Profile(id: o.id, email: o.email, fullName: o.fullName, role: o.role, phone: o.phone, active: active);
    _emit();
  }

  @override
  Future<void> updateMyProfile({required String fullName, String? phone}) async {
    final i = _profiles.indexWhere((p) => p.id == _uid);
    if (i < 0) return;
    final o = _profiles[i];
    _profiles[i] = Profile(id: o.id, email: o.email, fullName: fullName, role: o.role, phone: phone, active: o.active, canEditPrices: o.canEditPrices);
    _emit();
  }

  @override
  Future<Map<String, bool>> staffPermissions() async => Map<String, bool>.from(_perm);

  @override
  Future<void> setCanEditPrices(String employeeId, bool v) async {
    _perm[employeeId] = v;
    _emit();
  }

  @override
  Future<bool> myCanEditPrices() async => _isAdmin || (_perm[_uid] ?? false);

  // ---- الطلبات
  @override
  Future<List<Order>> listOrders() async => List<Order>.from(_orders)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<Order>> listMyOrders() async {
    final id = _me.role == 'client' ? _me.id : 'u-client1';
    return (await listOrders()).where((o) => o.clientId == id).toList();
  }

  @override
  Future<Order> getOrder(String id) async => _ord(id);

  @override
  Future<Order?> createOrder({required String section, required String title, required Map<String, dynamic> payload}) async {
    final cid = _me.role == 'client' ? _me.id : 'u-client1';
    final c = _p(cid);
    _seqOrder++;
    final o = Order(
      id: 'MAK-2026-${_two(_seqOrder)}', clientId: cid, section: section, title: title, status: 'new', verificationCode: _code(),
      payload: payload, totalMad: 0, depositMad: 0, createdAt: DateTime.now(), clientName: c.fullName, clientEmail: c.email,
    );
    _orders.add(o);
    _notifyRole(false, 'system', 'طلب جديد', 'وصل طلب جديد ${o.id} من ${c.display}', '/orders/${o.id}');
    _emit();
    return o;
  }

  @override
  Future<void> setOrderStatus(String id, String status) async {
    var o = _ord(id);
    o = o.copyWith(status: status);
    _setOrder(o);
    _notify(o.clientId, 'system', 'تحديث حالة الطلب', 'تم تحديث حالة الطلب ${o.id}', '/orders/${o.id}');
    if (status == 'completed') {
      for (final a in _assign.where((a) => a.orderId == id)) {
        if (!_scores.any((s) => s.orderId == id && s.employeeId == a.employeeId)) {
          _scores.add(ScoreEntry(employeeId: a.employeeId, orderId: id));
        }
      }
    }
    _log('UPDATE', 'orders', id);
    _emit();
  }

  @override
  Future<void> setDeposit(String id, int depositMad) async {
    final o = _ord(id);
    _setOrder(o.copyWith(depositMad: min(depositMad, o.totalMad)));
    _emit();
  }

  // ---- الملفات
  @override
  Future<String> uploadFile(String bucket, String orderId, String name, Uint8List bytes) async {
    final path = '$orderId/$name';
    _files.putIfAbsent('$bucket|$orderId', () => []).add(FileRef(name: name, path: path, bucket: bucket));
    _emit();
    return path;
  }

  @override
  Future<List<FileRef>> listFiles(String bucket, String orderId) async => List<FileRef>.from(_files['$bucket|$orderId'] ?? []);

  @override
  Future<String> fileUrl(String bucket, String path) async => '';

  // ---- عروض الأسعار
  @override
  Future<List<Quote>> listQuotes({String? orderId}) async {
    final l = _quotes.where((q) => orderId == null || q.orderId == orderId).toList();
    l.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  @override
  Future<void> proposeQuote({required String orderId, required int base, required int delta, required String note, required bool send}) async {
    final sendNow = send && (delta == 0 || _isAdmin);
    var o = _ord(orderId);
    if (sendNow && (o.status == 'rejected' || o.status == 'expired')) o = o.copyWith(status: 'new');
    final q = Quote(
      id: _nid(), orderId: orderId, status: sendNow ? 'sent' : 'pending_approval', note: note, baseTotal: base, delta: delta,
      finalTotal: base + delta, proposedBy: _uid, approvedBy: sendNow && _isAdmin ? _uid : null,
      validUntil: sendNow ? DateTime.now().add(const Duration(days: 7)) : null, createdAt: DateTime.now(),
    );
    _quotes.add(q);
    if (sendNow) {
      if (o.status == 'new') o = o.copyWith(status: 'quoted');
      _notify(o.clientId, 'quote', 'عرض سعر جديد', 'تم إرسال عرض سعر لطلبك $orderId', '/orders/$orderId');
    } else {
      _notifyRole(true, 'quote', 'مقترح سعر بانتظارك', 'اقترح ${_me.display} سعراً للطلب $orderId', '/orders/$orderId');
    }
    _setOrder(o);
    _log('INSERT', 'quotes', q.id);
    _emit();
  }

  void _replaceQuote(Quote q, {String? status, String? approvedBy, DateTime? validUntil}) {
    final i = _quotes.indexWhere((x) => x.id == q.id);
    _quotes[i] = Quote(
      id: q.id, orderId: q.orderId, status: status ?? q.status, note: q.note, baseTotal: q.baseTotal, delta: q.delta, finalTotal: q.finalTotal,
      proposedBy: q.proposedBy, approvedBy: approvedBy ?? q.approvedBy, validUntil: validUntil ?? q.validUntil, createdAt: q.createdAt,
    );
  }

  @override
  Future<void> approveQuote(String quoteId) async {
    if (!_isAdmin) throw Exception('Not allowed');
    final q = _quotes.firstWhere((x) => x.id == quoteId);
    _replaceQuote(q, status: 'sent', approvedBy: _uid, validUntil: DateTime.now().add(const Duration(days: 7)));
    var o = _ord(q.orderId);
    if (o.status == 'rejected' || o.status == 'expired' || o.status == 'new') o = o.copyWith(status: 'quoted');
    _setOrder(o);
    _notify(o.clientId, 'quote', 'عرض سعر جديد', 'تم إرسال عرض سعر لطلبك ${o.id}', '/orders/${o.id}');
    _log('UPDATE', 'quotes', quoteId);
    _emit();
  }

  @override
  Future<void> rejectProposal(String quoteId) async {
    if (!_isAdmin) throw Exception('Not allowed');
    final q = _quotes.firstWhere((x) => x.id == quoteId);
    _replaceQuote(q, status: 'rejected');
    _emit();
  }

  @override
  Future<bool> acceptQuote(String quoteId) async {
    final q = _quotes.firstWhere((x) => x.id == quoteId);
    final o = _ord(q.orderId);
    if (q.status != 'sent' || o.status != 'quoted') throw Exception('Quote is not open for a response');
    if (q.expired) {
      _replaceQuote(q, status: 'expired');
      _setOrder(o.copyWith(status: 'expired'));
      _emit();
      return false;
    }
    _replaceQuote(q, status: 'accepted');
    _setOrder(o.copyWith(status: 'accepted', totalMad: q.finalTotal));
    _notifyRole(true, 'quote', 'تم قبول عرض السعر', 'قبل العميل عرض السعر للطلب ${o.id}', '/orders/${o.id}');
    _emit();
    return true;
  }

  @override
  Future<void> rejectQuote(String quoteId) async {
    final q = _quotes.firstWhere((x) => x.id == quoteId);
    final o = _ord(q.orderId);
    _replaceQuote(q, status: 'rejected');
    _setOrder(o.copyWith(status: 'rejected'));
    _notifyRole(true, 'quote', 'تم رفض عرض السعر', 'رفض العميل عرض السعر للطلب ${o.id}', '/orders/${o.id}');
    _emit();
  }

  @override
  Future<void> expireQuotes() async {
    var changed = false;
    for (final q in List<Quote>.from(_quotes)) {
      if (q.status == 'sent' && q.expired) {
        _replaceQuote(q, status: 'expired');
        final o = _ord(q.orderId);
        if (o.status == 'quoted') _setOrder(o.copyWith(status: 'expired'));
        changed = true;
      }
    }
    if (changed) _emit();
  }

  // ---- العقود
  @override
  Future<List<Contract>> listContracts({String? orderId}) async {
    final l = _contracts.where((c) => orderId == null || c.orderId == orderId).toList();
    l.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  @override
  Future<List<ContractTemplate>> listTemplates() async => List<ContractTemplate>.from(_templates);

  @override
  Future<void> saveTemplate(String id, String ar, String en) async {
    final i = _templates.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final o = _templates[i];
    _templates[i] = ContractTemplate(id: o.id, section: o.section, title: o.title, bodyAr: ar, bodyEn: en);
    _emit();
  }

  void _replaceContract(Contract c, {String? status, String? ar, String? en, String? cs, String? asg, DateTime? signedAt}) {
    final i = _contracts.indexWhere((x) => x.id == c.id);
    _contracts[i] = Contract(
      id: c.id, orderId: c.orderId, status: status ?? c.status, kind: c.kind, rendered_ar: ar ?? c.rendered_ar, rendered_en: en ?? c.rendered_en,
      clientSignature: cs ?? c.clientSignature, adminSignature: asg ?? c.adminSignature, parentId: c.parentId, templateId: c.templateId,
      signedAt: signedAt ?? c.signedAt, createdAt: c.createdAt,
    );
  }

  @override
  Future<Contract> createContract({required String orderId, required String ar, required String en, String? parentId, String? templateId}) async {
    _seqContract++;
    final id = 'CON-2026-${_two(_seqContract)}';
    final c = Contract(
      id: id, orderId: orderId, status: 'draft', kind: parentId == null ? 'main' : 'addendum',
      rendered_ar: ar.replaceAll('{{CONTRACT_ID}}', id), rendered_en: en.replaceAll('{{CONTRACT_ID}}', id),
      parentId: parentId, templateId: templateId, createdAt: DateTime.now(),
    );
    _contracts.add(c);
    final o = _ord(orderId);
    if (parentId == null && o.status == 'accepted') {
      _setOrder(o.copyWith(status: 'contract_pending', depositMad: (o.totalMad * _settings.depositPct / 100).round()));
    }
    _log('INSERT', 'contracts', id);
    _emit();
    return c;
  }

  @override
  Future<void> updateContractText(String id, String ar, String en) async {
    final c = _contracts.firstWhere((x) => x.id == id);
    if (c.status == 'signed') throw Exception('Signed contracts are immutable');
    _replaceContract(c, ar: ar, en: en);
    _emit();
  }

  @override
  Future<void> sendContractToClient(String id) async {
    final c = _contracts.firstWhere((x) => x.id == id);
    _replaceContract(c, status: 'awaiting_client');
    final o = _ord(c.orderId);
    _notify(o.clientId, 'contract', 'عقد بانتظار توقيعك', 'تم تجهيز العقد ${c.id} لطلبك ${o.id}', '/contracts/${c.id}');
    _emit();
  }

  @override
  Future<void> voidContract(String id) async {
    final c = _contracts.firstWhere((x) => x.id == id);
    if (c.status == 'signed') throw Exception('Signed contracts are immutable');
    _replaceContract(c, status: 'void');
    _emit();
  }

  @override
  Future<void> signAsClient(String id, String signature) async {
    final c = _contracts.firstWhere((x) => x.id == id);
    if (c.status != 'awaiting_client') throw Exception('Contract is not awaiting the client signature');
    _replaceContract(c, status: 'awaiting_admin', cs: signature);
    _notifyRole(true, 'contract', 'عقد بانتظار توقيع المدير', 'يوجد عقد جديد يحتاج الاعتماد', '/contracts/$id');
    _emit();
  }

  @override
  Future<void> signAsAdmin(String id, String signature) async {
    if (!_isAdmin) throw Exception('Not allowed');
    final c = _contracts.firstWhere((x) => x.id == id);
    if (c.status != 'awaiting_admin') throw Exception('Contract is not awaiting the admin signature');
    _replaceContract(c, status: 'signed', asg: signature, signedAt: DateTime.now());
    final o = _ord(c.orderId);
    if (!c.isAddendum && (o.status == 'accepted' || o.status == 'contract_pending')) {
      _setOrder(o.copyWith(status: 'in_progress', executionStartedAt: DateTime.now()));
    }
    _notify(o.clientId, 'contract', 'تم توقيع العقد', 'تم اعتماد العقد الخاص بطلبك — بدأ التنفيذ', '/contracts/$id');
    _log('UPDATE', 'contracts', id);
    _emit();
  }

  // ---- الدفع
  @override
  Future<List<Payment>> listPayments({String? orderId}) async {
    final l = _payments.where((p) => orderId == null || p.orderId == orderId).toList();
    l.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  @override
  Future<void> submitPayment({required String orderId, required String kind, required int amount, String? receiptPath}) async {
    _payments.add(Payment(id: _nid(), orderId: orderId, kind: kind, method: 'bank', amount: amount, receiptPath: receiptPath, createdAt: DateTime.now()));
    _notifyRole(false, 'payment', 'وصل دفع جديد', 'رفع العميل وصل دفع للطلب $orderId', '/orders/$orderId');
    _emit();
  }

  @override
  Future<void> confirmPayment(String id) async {
    final i = _payments.indexWhere((x) => x.id == id);
    final p = _payments[i];
    if (p.confirmed) throw Exception('Confirmed payments cannot be modified');
    _payments[i] = Payment(
      id: p.id, orderId: p.orderId, kind: p.kind, method: p.method, amount: p.amount, receiptPath: p.receiptPath,
      confirmedBy: _uid, confirmedAt: DateTime.now(), createdAt: p.createdAt,
    );
    final o = _ord(p.orderId);
    if (!_invoices.any((v) => v.orderId == o.id)) {
      _seqInvoice++;
      _invoices.add(Invoice(
        id: 'INV-2026-${_two(_seqInvoice)}', orderId: o.id, clientName: o.clientName, lines: [{'label': o.title, 'amount': o.totalMad}],
        total: o.totalMad, status: 'issued', issuedAt: DateTime.now(),
      ));
    }
    final paid = _payments.where((x) => x.orderId == o.id && x.confirmed && x.kind != 'fine').fold<int>(0, (a, b) => a + b.amount);
    if (o.totalMad > 0 && paid >= o.totalMad) {
      if (o.status == 'in_progress' || o.status == 'preview_sent') _setOrder(o.copyWith(status: 'paid'));
      for (var k = 0; k < _invoices.length; k++) {
        final v = _invoices[k];
        if (v.orderId == o.id) {
          _invoices[k] = Invoice(id: v.id, clientName: v.clientName, status: 'paid', orderId: v.orderId, lines: v.lines, total: v.total, issuedAt: v.issuedAt);
        }
      }
    }
    _notify(o.clientId, 'payment', 'تم تأكيد الدفع', 'تم تأكيد الدفع للطلب ${o.id}', '/orders/${o.id}');
    _log('UPDATE', 'payments', id);
    _emit();
  }

  @override
  Future<void> addFine(String orderId, int amount) async {
    if (!_isAdmin) throw Exception('Not allowed');
    _payments.add(Payment(id: _nid(), orderId: orderId, kind: 'fine', method: 'bank', amount: amount, createdAt: DateTime.now()));
    _emit();
  }

  @override
  Future<List<Invoice>> listInvoices({String? orderId}) async {
    final l = _invoices.where((p) => orderId == null || p.orderId == orderId).toList();
    l.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return l;
  }

  // ---- المحادثة
  List<ChatMsg> _msgsFor(String orderId) {
    final l = _msgs.where((m) => m.orderId == orderId).toList();
    l.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return l;
  }

  @override
  Stream<List<ChatMsg>> watchMessages(String orderId) async* {
    yield _msgsFor(orderId);
    await for (final _ in _changes.stream) {
      yield _msgsFor(orderId);
    }
  }

  @override
  Future<void> sendMessage(String orderId, String body, {String? attachmentPath}) async {
    final me = _me;
    _msgs.add(ChatMsg(
      id: _nid(), orderId: orderId, senderId: me.id, body: body, attachmentPath: attachmentPath,
      senderName: me.fullName, senderRole: me.role, createdAt: DateTime.now(),
    ));
    final o = _ord(orderId);
    if (me.id != o.clientId) {
      _notify(o.clientId, 'message', 'رسالة جديدة', 'لديك رسالة جديدة على الطلب $orderId', '/orders/$orderId');
    } else {
      _notifyRole(false, 'message', 'رسالة جديدة من العميل', 'رسالة جديدة على الطلب $orderId', '/orders/$orderId');
    }
    _emit();
  }

  @override
  Future<List<ConvPreview>> conversations() async {
    final out = <ConvPreview>[];
    final orders = _me.role == 'client' ? await listMyOrders() : await listOrders();
    for (final o in orders) {
      final m = _msgsFor(o.id);
      out.add(ConvPreview(o, m.isEmpty ? null : m.last));
    }
    out.sort((a, b) => (b.last?.createdAt ?? b.order.createdAt).compareTo(a.last?.createdAt ?? a.order.createdAt));
    return out;
  }

  @override
  Future<List<ChatMsg>> allMessages() async => List<ChatMsg>.from(_msgs);

  List<AppNotification> _myNotifs() =>
      _notifs.where((x) => x['user'] == _uid).map((x) => x['n'] as AppNotification).toList();

  @override
  Stream<List<AppNotification>> watchNotifications() async* {
    yield _myNotifs();
    await for (final _ in _changes.stream) {
      yield _myNotifs();
    }
  }

  @override
  Future<void> markNotificationsRead() async {
    for (final x in _notifs) {
      if (x['user'] == _uid) {
        final n = x['n'] as AppNotification;
        if (n.readAt == null) {
          x['n'] = AppNotification(id: n.id, type: n.type, title: n.title, body: n.body, link: n.link, readAt: DateTime.now(), createdAt: n.createdAt);
        }
      }
    }
    _emit();
  }

  // ---- الإعدادات
  @override
  Future<CompanySettings> getSettings() async => _settings;

  @override
  Future<void> saveSettings(CompanySettings s) async {
    _settings = s;
    _emit();
  }

  @override
  Future<List<PriceTier>> getTiers() async => List<PriceTier>.from(_tiers);

  @override
  Future<void> saveTier(String code, int price) async {
    final i = _tiers.indexWhere((x) => x.code == code);
    if (i >= 0) _tiers[i].price = price;
    _emit();
  }

  @override
  Future<List<BriefQuestion>> getBriefQuestions() async => List<BriefQuestion>.from(_brief);

  @override
  Future<void> saveBriefQuestion(BriefQuestion q) async {
    final i = _brief.indexWhere((x) => x.key == q.key);
    if (i >= 0) _brief[i] = q;
    _emit();
  }

  @override
  Future<List<AuditRow>> listAudit() async => List<AuditRow>.from(_audit);

  // ---- طلبات التعديل والإلغاء
  @override
  Future<List<ChangeRequest>> listChangeRequests({String? orderId}) async =>
      _changeReqs.where((c) => orderId == null || c.orderId == orderId).toList().reversed.toList();

  @override
  Future<void> createChangeRequest(String orderId, String kind, String note) async {
    _changeReqs.add(ChangeRequest(id: _nid(), orderId: orderId, kind: kind, note: note, status: 'pending', feeMad: 0, createdAt: DateTime.now()));
    _notifyRole(false, 'system', kind == 'cancel' ? 'طلب إلغاء' : 'طلب تعديل', 'طلب جديد على $orderId', '/orders/$orderId');
    _emit();
  }

  @override
  Future<void> resolveChangeRequest(String id, bool approve, int fee) async {
    final i = _changeReqs.indexWhere((c) => c.id == id);
    final c = _changeReqs[i];
    if (c.isCancel && !_isAdmin) throw Exception('Not allowed');
    _changeReqs[i] = ChangeRequest(id: c.id, orderId: c.orderId, kind: c.kind, note: c.note, status: approve ? 'approved' : 'rejected', feeMad: fee, createdAt: c.createdAt);
    if (approve) {
      if (c.isCancel) {
        _setOrder(_ord(c.orderId).copyWith(status: 'cancelled'));
        if (fee > 0) _payments.add(Payment(id: _nid(), orderId: c.orderId, kind: 'fine', method: 'bank', amount: fee, createdAt: DateTime.now()));
      } else if (fee > 0) {
        _payments.add(Payment(id: _nid(), orderId: c.orderId, kind: 'modification', method: 'bank', amount: fee, createdAt: DateTime.now()));
      }
    }
    _notify(_ord(c.orderId).clientId, 'system', 'تحديث طلبك', 'تم البتّ في ${c.kindText} على ${c.orderId}', '/orders/${c.orderId}');
    _emit();
  }

  // ---- المحاسبة والنقاط
  @override
  Future<List<Expense>> listExpenses() async => List<Expense>.from(_expenses)..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<void> addExpense({required DateTime date, required String account, required String description, required int amount, required String method}) async {
    _expenses.add(Expense(id: _nid(), accountCode: account, description: description, method: method, date: date, amount: amount));
    _emit();
  }

  @override
  Future<List<ScoreRow>> leaderboard() async {
    final out = <ScoreRow>[];
    for (final p in _profiles.where((p) => p.role == 'staff' || p.role == 'admin')) {
      final s = _scores.where((x) => x.employeeId == p.id).toList();
      if (s.isEmpty) continue;
      final mgr = s.where((x) => x.managerRating != null).toList();
      final cl = s.where((x) => x.clientRating != null).toList();
      out.add(ScoreRow(
        employeeId: p.id, fullName: p.fullName, contracts: s.length, points: s.length,
        avgManager: mgr.isEmpty ? 0 : mgr.fold<int>(0, (a, b) => a + b.managerRating!) / mgr.length,
        avgClient: cl.isEmpty ? 0 : cl.fold<int>(0, (a, b) => a + b.clientRating!) / cl.length,
      ));
    }
    out.sort((a, b) => b.points.compareTo(a.points));
    return out;
  }

  @override
  Future<List<ScoreEntry>> scoresFor(String orderId) async => _scores.where((s) => s.orderId == orderId).toList();

  @override
  Future<void> setManagerRating(String orderId, String employeeId, int rating) async {
    final i = _scores.indexWhere((s) => s.orderId == orderId && s.employeeId == employeeId);
    if (i < 0) return;
    final s = _scores[i];
    if (s.managerRating != null) throw Exception('Manager rating cannot be changed');
    _scores[i] = ScoreEntry(employeeId: employeeId, orderId: orderId, managerRating: rating, clientRating: s.clientRating);
    _emit();
  }

  @override
  Future<void> rateEmployee(String orderId, String employeeId, int rating) async {
    final i = _scores.indexWhere((s) => s.orderId == orderId && s.employeeId == employeeId);
    if (i < 0) throw Exception('Score record not found');
    final s = _scores[i];
    _scores[i] = ScoreEntry(employeeId: employeeId, orderId: orderId, managerRating: s.managerRating, clientRating: rating);
    _emit();
  }

  @override
  Future<List<Assignment>> assignments(String orderId) async => _assign.where((a) => a.orderId == orderId).toList();

  @override
  Future<List<TeamMember>> orderTeam(String orderId) async {
    final out = <TeamMember>[];
    for (final a in _assign.where((a) => a.orderId == orderId)) {
      final sc = _scores.where((s) => s.orderId == orderId && s.employeeId == a.employeeId).toList();
      out.add(TeamMember(
        employeeId: a.employeeId, name: _p(a.employeeId).fullName, role: a.role,
        clientRating: sc.isEmpty ? null : sc.first.clientRating,
        managerRating: (sc.isEmpty || !_isStaff) ? null : sc.first.managerRating,
      ));
    }
    return out;
  }

  @override
  Future<void> assignEmployee(String orderId, String employeeId, String role) async {
    if (_assign.any((a) => a.orderId == orderId && a.employeeId == employeeId)) return;
    _assign.add(Assignment(employeeId: employeeId, orderId: orderId, role: role));
    _emit();
  }
}
