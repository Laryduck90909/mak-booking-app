import '../core/config.dart';
import '../core/i18n.dart';

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}

double _n(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

DateTime? _d(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  return d?.toLocal();
}

String _s(dynamic v) => v == null ? '' : '$v';

Map<String, dynamic> _m(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _lm(dynamic v) {
  if (v is List) return v.map((e) => _m(e)).toList();
  return <Map<String, dynamic>>[];
}

// ------------------------------------------------------------------
// الحالات
// ------------------------------------------------------------------
const orderStatuses = [
  'new', 'quoted', 'accepted', 'rejected', 'expired', 'contract_pending',
  'in_progress', 'preview_sent', 'paid', 'delivered', 'completed', 'cancelled',
];

String statusLabel(String s) {
  switch (s) {
    case 'new': return t('جديد', 'New');
    case 'quoted': return t('تم التسعير', 'Quoted');
    case 'accepted': return t('تم القبول', 'Accepted');
    case 'rejected': return t('مرفوض', 'Rejected');
    case 'expired': return t('انتهى العرض', 'Expired');
    case 'contract_pending': return t('عقد بانتظار التوقيع', 'Contract pending');
    case 'in_progress': return t('قيد التنفيذ', 'In progress');
    case 'preview_sent': return t('تم إرسال المعاينة', 'Preview sent');
    case 'paid': return t('تم الدفع', 'Paid');
    case 'delivered': return t('تم التسليم', 'Delivered');
    case 'completed': return t('مكتمل', 'Completed');
    case 'cancelled': return t('ملغى', 'Cancelled');
    default: return s;
  }
}

String sectionLabel(String s) {
  switch (s) {
    case 'design': return 'MAK DESIGN';
    case 'web': return 'MAK WEBS';
    case 'writing': return 'MAK WRITINGS';
    default: return s;
  }
}

String sectionName(String s) {
  switch (s) {
    case 'design': return t('تصميم', 'Design');
    case 'web': return t('برمجة وويب', 'Web & Software');
    case 'writing': return t('كتابة وترجمة', 'Writing');
    default: return s;
  }
}

String roleLabel(String r) {
  switch (r) {
    case 'admin': return t('مدير', 'Admin');
    case 'staff': return t('موظف', 'Staff');
    default: return t('عميل', 'Client');
  }
}

// ------------------------------------------------------------------
class Profile {
  final String id, email, fullName, role;
  final String? phone, taxId;
  final bool active;
  final DateTime? createdAt;
  bool canEditPrices;

  Profile({
    required this.id, required this.email, required this.fullName, required this.role,
    this.phone, this.taxId, this.active = true, this.createdAt, this.canEditPrices = false,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: _s(j['id']), email: _s(j['email']), fullName: _s(j['full_name']),
        role: _s(j['role']).isEmpty ? 'client' : _s(j['role']),
        phone: j['phone'] as String?, taxId: j['tax_id'] as String?,
        active: j['active'] != false, createdAt: _d(j['created_at']),
      );

  String get display => fullName.trim().isEmpty ? email : fullName;
  bool get isStaffOrAdmin => role == 'staff' || role == 'admin';
}

// ------------------------------------------------------------------
class Order {
  final String id, clientId, section, title, status, verificationCode;
  final Map<String, dynamic> payload;
  final int totalMad, depositMad;
  final DateTime createdAt;
  final DateTime? updatedAt, executionStartedAt, cancelledAt, completedAt;
  final String clientName, clientEmail;

  Order({
    required this.id, required this.clientId, required this.section, required this.title,
    required this.status, required this.verificationCode, required this.payload,
    required this.totalMad, required this.depositMad, required this.createdAt,
    this.updatedAt, this.executionStartedAt, this.cancelledAt, this.completedAt,
    this.clientName = '', this.clientEmail = '',
  });

  factory Order.fromJson(Map<String, dynamic> j) {
    final c = j['client'];
    var name = '';
    var email = '';
    if (c is Map) {
      name = _s(c['full_name']);
      email = _s(c['email']);
    }
    return Order(
      id: _s(j['id']), clientId: _s(j['client_id']), section: _s(j['section']),
      title: _s(j['title']), status: _s(j['status']),
      verificationCode: _s(j['verification_code']), payload: _m(j['payload']),
      totalMad: _i(j['total_mad']), depositMad: _i(j['deposit_mad']),
      createdAt: _d(j['created_at']) ?? DateTime.now(), updatedAt: _d(j['updated_at']),
      executionStartedAt: _d(j['execution_started_at']), cancelledAt: _d(j['cancelled_at']),
      completedAt: _d(j['completed_at']),
      clientName: name.isEmpty ? email : name, clientEmail: email,
    );
  }

  Order copyWith({String? status, int? totalMad, int? depositMad, DateTime? executionStartedAt}) => Order(
        id: id, clientId: clientId, section: section, title: title,
        status: status ?? this.status, verificationCode: verificationCode, payload: payload,
        totalMad: totalMad ?? this.totalMad, depositMad: depositMad ?? this.depositMad,
        createdAt: createdAt, updatedAt: DateTime.now(),
        executionStartedAt: executionStartedAt ?? this.executionStartedAt,
        cancelledAt: cancelledAt, completedAt: completedAt,
        clientName: clientName, clientEmail: clientEmail,
      );

  List<Map<String, dynamic>> get items => _lm(payload['items']);
  List<Map<String, dynamic>> get colors => _lm(payload['colors']);
  List<String> get mockups => (payload['mockups'] is List) ? (payload['mockups'] as List).map((e) => '$e').toList() : <String>[];
  Map<String, dynamic> get briefAnswers => _m(payload['brief_answers']);
  int get estimate => _i(payload['estimate_total']);
  String get styleKey => _s(payload['style']);
  bool get needsManualPricing => payload['needs_manual_pricing'] == true;

  bool get isClosed => status == 'completed' || status == 'cancelled' || status == 'rejected' || status == 'expired';

  /// نافذة الثلاثة أيام تبدأ من بدء التنفيذ (توقيع العقد).
  bool get freeWindowOpen {
    final s = executionStartedAt;
    if (s == null) return true; // لم يبدأ التنفيذ بعد
    return DateTime.now().isBefore(s.add(const Duration(days: AppConfig.freeWindowDays)));
  }

  DateTime? get freeWindowEnds {
    final s = executionStartedAt;
    return s?.add(const Duration(days: AppConfig.freeWindowDays));
  }
}

// ------------------------------------------------------------------
class Quote {
  final String id, orderId, status, note;
  final int baseTotal, delta, finalTotal;
  final String? proposedBy, approvedBy;
  final DateTime? validUntil;
  final DateTime createdAt;

  Quote({
    required this.id, required this.orderId, required this.status, required this.note,
    required this.baseTotal, required this.delta, required this.finalTotal,
    this.proposedBy, this.approvedBy, this.validUntil, required this.createdAt,
  });

  factory Quote.fromJson(Map<String, dynamic> j) {
    final base = _i(j['base_total_mad']);
    final delta = _i(j['variable_delta_mad']);
    return Quote(
      id: _s(j['id']), orderId: _s(j['order_id']), status: _s(j['status']), note: _s(j['note']),
      baseTotal: base, delta: delta,
      finalTotal: j['final_total_mad'] == null ? base + delta : _i(j['final_total_mad']),
      proposedBy: j['proposed_by'] as String?, approvedBy: j['approved_by'] as String?,
      validUntil: _d(j['valid_until']), createdAt: _d(j['created_at']) ?? DateTime.now(),
    );
  }

  bool get expired {
    final v = validUntil;
    if (v == null) return false;
    final today = DateTime.now();
    return DateTime(v.year, v.month, v.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  String get statusText {
    switch (status) {
      case 'pending_approval': return t('بانتظار اعتماد المدير', 'Awaiting admin approval');
      case 'approved': return t('معتمد', 'Approved');
      case 'sent': return t('مُرسل للعميل', 'Sent to client');
      case 'accepted': return t('مقبول', 'Accepted');
      case 'rejected': return t('مرفوض', 'Rejected');
      case 'expired': return t('منتهٍ', 'Expired');
      default: return status;
    }
  }
}

// ------------------------------------------------------------------
class Contract {
  final String id, orderId, status, kind;
  final String rendered_ar, rendered_en;
  final String? clientSignature, adminSignature, parentId, templateId;
  final DateTime? signedAt;
  final DateTime createdAt;

  Contract({
    required this.id, required this.orderId, required this.status, required this.rendered_ar,
    required this.rendered_en, this.kind = 'main', this.clientSignature, this.adminSignature,
    this.parentId, this.templateId, this.signedAt, required this.createdAt,
  });

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: _s(j['id']), orderId: _s(j['order_id']), status: _s(j['status']),
        kind: _s(j['kind']).isEmpty ? 'main' : _s(j['kind']),
        rendered_ar: _s(j['rendered_ar']), rendered_en: _s(j['rendered_en']),
        clientSignature: j['client_signature'] as String?, adminSignature: j['admin_signature'] as String?,
        parentId: j['parent_contract_id'] as String?, templateId: j['template_id'] as String?,
        signedAt: _d(j['signed_at']), createdAt: _d(j['created_at']) ?? DateTime.now(),
      );

  bool get isAddendum => parentId != null && parentId!.isNotEmpty;
  bool get signed => status == 'signed';

  String get statusText {
    switch (status) {
      case 'draft': return t('مسودة', 'Draft');
      case 'awaiting_client': return t('بانتظار توقيع العميل', 'Awaiting client');
      case 'awaiting_admin': return t('بانتظار توقيع المدير', 'Awaiting admin');
      case 'signed': return t('موقّع', 'Signed');
      case 'void': return t('ملغى', 'Void');
      default: return status;
    }
  }
}

class ContractTemplate {
  final String id, section, title, bodyAr, bodyEn;
  ContractTemplate({required this.id, required this.section, required this.title, required this.bodyAr, required this.bodyEn});
  factory ContractTemplate.fromJson(Map<String, dynamic> j) => ContractTemplate(
        id: _s(j['id']), section: _s(j['section']), title: _s(j['title']),
        bodyAr: _s(j['body_ar']), bodyEn: _s(j['body_en']),
      );
}

// ------------------------------------------------------------------
class Payment {
  final String id, orderId, kind, method;
  final int amount;
  final String? receiptPath, confirmedBy;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  Payment({
    required this.id, required this.orderId, required this.kind, required this.method,
    required this.amount, this.receiptPath, this.confirmedBy, this.confirmedAt, required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: _s(j['id']), orderId: _s(j['order_id']), kind: _s(j['kind']),
        method: _s(j['method']).isEmpty ? 'bank' : _s(j['method']), amount: _i(j['amount_mad']),
        receiptPath: j['receipt_path'] as String?, confirmedBy: j['confirmed_by'] as String?,
        confirmedAt: _d(j['confirmed_at']), createdAt: _d(j['created_at']) ?? DateTime.now(),
      );

  bool get confirmed => confirmedAt != null;

  String get kindText {
    switch (kind) {
      case 'deposit': return t('عربون', 'Deposit');
      case 'full': return t('دفعة', 'Payment');
      case 'fine': return t('غرامة', 'Fine');
      case 'modification': return t('تعديل', 'Modification');
      default: return kind;
    }
  }
}

class Invoice {
  final String id, clientName, status;
  final String? orderId;
  final List<Map<String, dynamic>> lines;
  final int total;
  final DateTime issuedAt;

  Invoice({required this.id, required this.clientName, required this.status, this.orderId, required this.lines, required this.total, required this.issuedAt});

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: _s(j['id']), clientName: _s(j['client_name']), status: _s(j['status']),
        orderId: j['order_id'] as String?, lines: _lm(j['lines']), total: _i(j['total_mad']),
        issuedAt: _d(j['issued_at']) ?? DateTime.now(),
      );
}

// ------------------------------------------------------------------
class ChatMsg {
  final String id, orderId, senderId, body;
  final String? attachmentPath, senderName, senderRole;
  final DateTime createdAt;

  ChatMsg({required this.id, required this.orderId, required this.senderId, required this.body, this.attachmentPath, this.senderName, this.senderRole, required this.createdAt});

  factory ChatMsg.fromJson(Map<String, dynamic> j) {
    final s = j['sender'];
    return ChatMsg(
      id: _s(j['id']), orderId: _s(j['order_id']), senderId: _s(j['sender_id']), body: _s(j['body']),
      attachmentPath: j['attachment_path'] as String?, createdAt: _d(j['created_at']) ?? DateTime.now(),
      senderName: s is Map ? _s(s['full_name']) : null, senderRole: s is Map ? _s(s['role']) : null,
    );
  }
}

class AppNotification {
  final String id, type, title, body, link;
  final DateTime? readAt;
  final DateTime createdAt;
  AppNotification({required this.id, required this.type, required this.title, required this.body, required this.link, this.readAt, required this.createdAt});
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: _s(j['id']), type: _s(j['type']), title: _s(j['title']), body: _s(j['body']), link: _s(j['link']),
        readAt: _d(j['read_at']), createdAt: _d(j['created_at']) ?? DateTime.now(),
      );
}

class ChangeRequest {
  final String id, orderId, kind, note, status;
  final int feeMad;
  final DateTime createdAt;
  ChangeRequest({required this.id, required this.orderId, required this.kind, required this.note, required this.status, required this.feeMad, required this.createdAt});
  factory ChangeRequest.fromJson(Map<String, dynamic> j) => ChangeRequest(
        id: _s(j['id']), orderId: _s(j['order_id']), kind: _s(j['kind']), note: _s(j['note']),
        status: _s(j['status']), feeMad: _i(j['fee_mad']), createdAt: _d(j['created_at']) ?? DateTime.now(),
      );
  bool get isCancel => kind == 'cancel';
  String get kindText => isCancel ? t('طلب إلغاء', 'Cancellation') : t('طلب تعديل', 'Modification');
  String get statusText {
    switch (status) {
      case 'approved': return t('معتمد', 'Approved');
      case 'rejected': return t('مرفوض', 'Rejected');
      default: return t('قيد المراجعة', 'Pending');
    }
  }
}

class Expense {
  final String id, accountCode, description, method;
  final DateTime date;
  final int amount;
  Expense({required this.id, required this.accountCode, required this.description, required this.method, required this.date, required this.amount});
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: _s(j['id']), accountCode: _s(j['account_code']), description: _s(j['description']),
        method: _s(j['method']), date: _d(j['expense_date']) ?? DateTime.now(), amount: _i(j['amount_mad']),
      );
}

class ScoreRow {
  final String employeeId, fullName;
  final int contracts, points;
  final double avgManager, avgClient;
  ScoreRow({required this.employeeId, required this.fullName, required this.contracts, required this.points, required this.avgManager, required this.avgClient});
  factory ScoreRow.fromJson(Map<String, dynamic> j) => ScoreRow(
        employeeId: _s(j['id']), fullName: _s(j['full_name']), contracts: _i(j['contracts_done']),
        points: _i(j['points']), avgManager: _n(j['avg_manager']), avgClient: _n(j['avg_client']),
      );
}

class ScoreEntry {
  final String employeeId, orderId;
  final int? managerRating, clientRating;
  ScoreEntry({required this.employeeId, required this.orderId, this.managerRating, this.clientRating});
  factory ScoreEntry.fromJson(Map<String, dynamic> j) => ScoreEntry(
        employeeId: _s(j['employee_id']), orderId: _s(j['order_id']),
        managerRating: j['manager_rating'] == null ? null : _i(j['manager_rating']),
        clientRating: j['client_rating'] == null ? null : _i(j['client_rating']),
      );
}

class Assignment {
  final String employeeId, orderId, role;
  Assignment({required this.employeeId, required this.orderId, required this.role});
  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(employeeId: _s(j['employee_id']), orderId: _s(j['order_id']), role: _s(j['role']));
}

class TeamMember {
  final String employeeId, name, role;
  final int? clientRating, managerRating;
  TeamMember({required this.employeeId, required this.name, required this.role, this.clientRating, this.managerRating});
  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        employeeId: _s(j['employee_id']), name: _s(j['full_name']), role: _s(j['role']),
        clientRating: j['client_rating'] == null ? null : _i(j['client_rating']),
        managerRating: j['manager_rating'] == null ? null : _i(j['manager_rating']),
      );
}

class AuditRow {
  final String action, entity, entityId;
  final String? actorName;
  final DateTime createdAt;
  AuditRow({required this.action, required this.entity, required this.entityId, this.actorName, required this.createdAt});
  factory AuditRow.fromJson(Map<String, dynamic> j) {
    final a = j['actor'];
    return AuditRow(
      action: _s(j['action']), entity: _s(j['entity']), entityId: _s(j['entity_id']),
      actorName: a is Map ? _s(a['full_name']) : null, createdAt: _d(j['created_at']) ?? DateTime.now(),
    );
  }
}

class CompanySettings {
  String companyName, accountHolder, bankName, rib, taxId, email, phone, whatsapp, city;
  int depositPct, cancelFinePct, modifyFeePct, revisionRounds;

  CompanySettings({
    this.companyName = 'M.A.K', this.accountHolder = '', this.bankName = '', this.rib = '',
    this.taxId = '', this.email = '', this.phone = '', this.whatsapp = '', this.city = '',
    this.depositPct = 10, this.cancelFinePct = 10, this.modifyFeePct = 5, this.revisionRounds = 2,
  });

  factory CompanySettings.fromJson(Map<String, dynamic> j) => CompanySettings(
        companyName: _s(j['company_name']).isEmpty ? 'M.A.K' : _s(j['company_name']),
        accountHolder: _s(j['account_holder']), bankName: _s(j['bank_name']), rib: _s(j['rib']),
        taxId: _s(j['tax_id']), email: _s(j['support_email']), phone: _s(j['support_phone']),
        whatsapp: _s(j['whatsapp']), city: _s(j['city']),
        depositPct: j['deposit_percent'] == null ? 10 : _i(j['deposit_percent']),
        cancelFinePct: j['cancel_fine_percent'] == null ? 10 : _i(j['cancel_fine_percent']),
        modifyFeePct: j['modify_fee_percent'] == null ? 5 : _i(j['modify_fee_percent']),
        revisionRounds: j['revision_rounds'] == null ? 2 : _i(j['revision_rounds']),
      );

  Map<String, dynamic> toJson() => {
        'company_name': companyName, 'account_holder': accountHolder, 'bank_name': bankName, 'rib': rib,
        'tax_id': taxId.isEmpty ? null : taxId, 'support_email': email, 'support_phone': phone,
        'whatsapp': whatsapp, 'city': city, 'deposit_percent': depositPct,
        'cancel_fine_percent': cancelFinePct, 'modify_fee_percent': modifyFeePct,
        'revision_rounds': revisionRounds,
      };
}

class PriceTier {
  final String code, labelAr, labelEn;
  int price;
  PriceTier({required this.code, required this.labelAr, required this.labelEn, required this.price});
  factory PriceTier.fromJson(Map<String, dynamic> j) =>
      PriceTier(code: _s(j['code']), labelAr: _s(j['label_ar']), labelEn: _s(j['label_en']), price: _i(j['price_mad']));
  String get label => t(labelAr, labelEn);
}

class BriefQuestion {
  final String key, group, labelAr, labelEn, type;
  final List<String> options;
  bool active;
  final int sort;
  BriefQuestion({required this.key, required this.group, required this.labelAr, required this.labelEn, required this.type, required this.options, this.active = true, required this.sort});

  factory BriefQuestion.fromJson(Map<String, dynamic> j) => BriefQuestion(
        key: _s(j['key']), group: _s(j['grp'] ?? j['group']), labelAr: _s(j['label_ar'] ?? j['ar']), labelEn: _s(j['label_en'] ?? j['en']),
        type: _s(j['type']).isEmpty ? 'text' : _s(j['type']),
        options: (j['options'] is List) ? (j['options'] as List).map((e) => '$e').toList() : <String>[],
        active: j['active'] != false, sort: _i(j['sort']),
      );

  String get label => t(labelAr, labelEn.isEmpty ? labelAr : labelEn);
}

// ---- كتالوج الأصول (assets/data/*.json) ----
class CatalogItem {
  final String key, nameAr, nameEn, group;
  final String? tier; // null = بلا سعر معتمد (يُسعَّر يدوياً)
  CatalogItem({required this.key, required this.nameAr, required this.nameEn, required this.group, this.tier});
  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
        key: _s(j['key']), nameAr: _s(j['ar']), nameEn: _s(j['en']), group: _s(j['group']), tier: j['tier'] as String?,
      );
  String get name => t(nameAr, nameEn);
}

class SimpleDef {
  final String key, nameAr, nameEn;
  SimpleDef({required this.key, required this.nameAr, required this.nameEn});
  factory SimpleDef.fromJson(Map<String, dynamic> j) => SimpleDef(key: _s(j['key']), nameAr: _s(j['ar']), nameEn: _s(j['en']));
  String get name => t(nameAr, nameEn);
}

class FileRef {
  final String name, path, bucket;
  FileRef({required this.name, required this.path, required this.bucket});
}

class PnlRow {
  final DateTime month;
  final int income, expense;
  PnlRow(this.month, this.income, this.expense);
  int get profit => income - expense;
}

String briefGroupLabel(String g) {
  switch (g) {
    case 'brand': return t('الهوية والعلامة', 'Brand');
    case 'purpose': return t('الهدف', 'Purpose');
    case 'audience': return t('الجمهور', 'Audience');
    case 'visual': return t('الأسلوب البصري', 'Visual style');
    case 'content': return t('المحتوى', 'Content');
    case 'tech': return t('المواصفات التقنية', 'Technical');
    case 'process': return t('سير العمل والتسليم', 'Process & delivery');
    default: return g;
  }
}
