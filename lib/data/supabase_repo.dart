import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/util.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'repo.dart';

/// المستودع الحقيقي فوق Supabase (RLS يفرض الصلاحيات في قاعدة البيانات).
class SupabaseRepo implements Repo {
  SupabaseClient get sb => Supabase.instance.client;
  final _ctl = StreamController<void>.broadcast();
  Timer? _poll, _outboxTimer;
  RealtimeChannel? _chan;
  Map<String, Map<String, String>>? _names;

  static const _orderSelect = '*, client:profiles!client_id(full_name,email)';

  SupabaseRepo() {
    _startRealtime();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _ctl.add(null));
    _outboxTimer = Timer.periodic(const Duration(seconds: 25), (_) => flushOutbox());
  }

  void _startRealtime() {
    try {
      final c = sb.channel('mak-changes');
      for (final t in ['orders', 'quotes', 'contracts', 'payments', 'invoices', 'messages', 'order_change_requests']) {
        c.onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: t,
          callback: (payload) => _ctl.add(null),
        );
      }
      c.subscribe();
      _chan = c;
    } catch (_) {}
  }

  void _touch() => _ctl.add(null);

  @override
  Stream<void> get changes => _ctl.stream;
  @override
  String? get userId => sb.auth.currentUser?.id;
  @override
  bool get isDemo => false;

  // ------------------------------------------------------------ تخزين محلي (عمل دون إنترنت)
  Future<void> _saveCache(String key, List<Map<String, dynamic>> rows) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('cache:$key:$userId', jsonEncode(rows));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _loadCache(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('cache:$key:$userId');
      if (s == null) return null;
      return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _rows(String key, dynamic Function() q) async {
    try {
      final r = await q();
      final list = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _saveCache(key, list);
      return list;
    } catch (e) {
      if (looksOffline(e)) {
        final c = await _loadCache(key);
        if (c != null) return c;
      }
      rethrow;
    }
  }

  // صندوق الصادر: رسائل وطلبات كُتبت دون اتصال
  Future<List<Map<String, dynamic>>> _outbox() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('outbox:$userId');
      if (s == null) return [];
      return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveOutbox(List<Map<String, dynamic>> l) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('outbox:$userId', jsonEncode(l));
    } catch (_) {}
  }

  Future<void> _enqueue(Map<String, dynamic> item) async {
    final l = await _outbox();
    l.add(item);
    await _saveOutbox(l);
  }

  Future<void> flushOutbox() async {
    if (userId == null) return;
    final l = await _outbox();
    if (l.isEmpty) return;
    final rest = <Map<String, dynamic>>[];
    for (final it in l) {
      try {
        if (it['type'] == 'order') {
          await sb.from('orders').insert({
            'client_id': userId, 'section': it['section'], 'title': it['title'], 'payload': it['payload'],
            'status': 'new', 'total_mad': 0, 'deposit_mad': 0,
          });
        } else if (it['type'] == 'message') {
          await sb.from('messages').insert({'order_id': it['order_id'], 'sender_id': userId, 'body': it['body'], 'attachment_path': it['attachment_path']});
        }
      } catch (e) {
        if (looksOffline(e)) {
          rest.add(it);
        }
        // أخطاء أخرى (صلاحيات...) تُهمَل حتى لا تتكرر للأبد
      }
    }
    await _saveOutbox(rest);
    if (rest.length != l.length) _touch();
  }

  // ------------------------------------------------------------ المصادقة
  @override
  Future<SignUpResult> signUp(String email, String password, String fullName) async {
    final res = await sb.auth.signUp(email: email, password: password, data: {'full_name': fullName});
    if (res.session != null) return SignUpResult.signedIn;
    return SignUpResult.needsEmailConfirm;
  }

  @override
  Future<void> signIn(String email, String password) async {
    await sb.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    await sb.auth.signOut();
  }

  @override
  Future<void> resendConfirmation(String email) async {
    await sb.auth.resend(type: OtpType.signup, email: email);
  }

  @override
  Future<void> demoSignIn(String role) async {}

  @override
  Future<Profile?> currentProfile() async {
    final uid = userId;
    if (uid == null) return null;
    // الـ trigger ينشئ الملف عند إنشاء الحساب؛ نعيد المحاولة 3 مرات تحسباً للتأخر.
    for (var i = 0; i < 4; i++) {
      final r = await sb.from('profiles').select().eq('id', uid).maybeSingle();
      if (r != null) return Profile.fromJson(Map<String, dynamic>.from(r));
      await Future.delayed(Duration(milliseconds: 600 * (i + 1)));
    }
    return null;
  }

  // ------------------------------------------------------------ الملفات الشخصية
  @override
  Future<List<Profile>> listProfiles() async {
    final r = await sb.from('profiles').select().order('created_at');
    final perms = await staffPermissions();
    return (r as List).map((e) {
      final p = Profile.fromJson(Map<String, dynamic>.from(e as Map));
      p.canEditPrices = perms[p.id] ?? false;
      return p;
    }).toList();
  }

  @override
  Future<void> setRole(String userId, String role) async {
    await sb.from('profiles').update({'role': role}).eq('id', userId);
    _touch();
  }

  @override
  Future<void> setActive(String userId, bool active) async {
    await sb.from('profiles').update({'active': active}).eq('id', userId);
    _touch();
  }

  @override
  Future<void> updateMyProfile({required String fullName, String? phone}) async {
    await sb.from('profiles').update({'full_name': fullName, 'phone': phone}).eq('id', userId!);
    _touch();
  }

  @override
  Future<Map<String, bool>> staffPermissions() async {
    try {
      final r = await sb.from('staff_permissions').select();
      return {for (final e in (r as List)) '${(e as Map)['employee_id']}': e['can_edit_prices'] == true};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> setCanEditPrices(String employeeId, bool v) async {
    await sb.from('staff_permissions').upsert({'employee_id': employeeId, 'can_edit_prices': v});
    _touch();
  }

  @override
  Future<bool> myCanEditPrices() async {
    final me = await currentProfile();
    if (me?.role == 'admin') return true;
    try {
      final r = await sb.from('staff_permissions').select().eq('employee_id', userId!).maybeSingle();
      return r != null && r['can_edit_prices'] == true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ الطلبات
  @override
  Future<List<Order>> listOrders() async {
    final rows = await _rows('orders:all', () => sb.from('orders').select(_orderSelect).isFilter('deleted_at', null).order('created_at', ascending: false));
    return rows.map(Order.fromJson).toList();
  }

  @override
  Future<List<Order>> listMyOrders() async {
    final uid = userId;
    final rows = await _rows('orders:mine', () => sb.from('orders').select(_orderSelect).eq('client_id', uid!).isFilter('deleted_at', null).order('created_at', ascending: false));
    return rows.map(Order.fromJson).toList();
  }

  @override
  Future<Order> getOrder(String id) async {
    final r = await sb.from('orders').select(_orderSelect).eq('id', id).single();
    return Order.fromJson(Map<String, dynamic>.from(r));
  }

  @override
  Future<Order?> createOrder({required String section, required String title, required Map<String, dynamic> payload}) async {
    try {
      final r = await sb.from('orders').insert({
        'client_id': userId, 'section': section, 'title': title, 'payload': payload,
        'status': 'new', 'total_mad': 0, 'deposit_mad': 0,
      }).select(_orderSelect).single();
      _touch();
      return Order.fromJson(Map<String, dynamic>.from(r));
    } catch (e) {
      if (looksOffline(e)) {
        await _enqueue({'type': 'order', 'section': section, 'title': title, 'payload': payload});
        return null; // حُفظ كمسودة وسيُرسل عند عودة الاتصال
      }
      rethrow;
    }
  }

  @override
  Future<void> setOrderStatus(String id, String status) async {
    await sb.from('orders').update({'status': status}).eq('id', id);
    _touch();
  }

  @override
  Future<void> setDeposit(String id, int depositMad) async {
    await sb.from('orders').update({'deposit_mad': depositMad}).eq('id', id);
    _touch();
  }

  // ------------------------------------------------------------ الملفات
  @override
  Future<String> uploadFile(String bucket, String orderId, String name, Uint8List bytes) async {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$orderId/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await sb.storage.from(bucket).uploadBinary(path, bytes);
    _touch();
    return path;
  }

  @override
  Future<List<FileRef>> listFiles(String bucket, String orderId) async {
    try {
      final l = await sb.storage.from(bucket).list(path: orderId);
      return l.where((f) => !f.name.startsWith('.')).map((f) => FileRef(name: f.name, path: '$orderId/${f.name}', bucket: bucket)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> fileUrl(String bucket, String path) async {
    return sb.storage.from(bucket).createSignedUrl(path, 3600);
  }

  // ------------------------------------------------------------ عروض الأسعار
  String _dateOnly(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<Quote>> listQuotes({String? orderId}) async {
    final rows = await _rows('quotes:${orderId ?? 'all'}', () {
      var q = sb.from('quotes').select();
      if (orderId != null) q = q.eq('order_id', orderId);
      return q.order('created_at', ascending: false);
    });
    return rows.map(Quote.fromJson).toList();
  }

  Future<void> _reopenOrderIfNeeded(String orderId) async {
    final o = await sb.from('orders').select('status').eq('id', orderId).single();
    final s = '${o['status']}';
    if (s == 'rejected' || s == 'expired') {
      await sb.from('orders').update({'status': 'new'}).eq('id', orderId);
    }
  }

  @override
  Future<void> proposeQuote({required String orderId, required int base, required int delta, required String note, required bool send}) async {
    final me = await currentProfile();
    final isAdmin = me?.role == 'admin';
    final sendNow = send && (delta == 0 || isAdmin);
    if (sendNow) await _reopenOrderIfNeeded(orderId);
    await sb.from('quotes').insert({
      'order_id': orderId, 'base_total_mad': base, 'variable_delta_mad': delta, 'note': note, 'proposed_by': userId,
      'status': sendNow ? 'sent' : 'pending_approval',
      if (sendNow && isAdmin) 'approved_by': userId,
      if (sendNow) 'valid_until': _dateOnly(DateTime.now().add(const Duration(days: 7))),
    });
    _touch();
  }

  @override
  Future<void> approveQuote(String quoteId) async {
    final q = await sb.from('quotes').select('order_id').eq('id', quoteId).single();
    await _reopenOrderIfNeeded('${q['order_id']}');
    await sb.from('quotes').update({
      'status': 'sent', 'approved_by': userId, 'valid_until': _dateOnly(DateTime.now().add(const Duration(days: 7))),
    }).eq('id', quoteId);
    _touch();
  }

  @override
  Future<void> rejectProposal(String quoteId) async {
    await sb.from('quotes').update({'status': 'rejected'}).eq('id', quoteId);
    _touch();
  }

  @override
  Future<bool> acceptQuote(String quoteId) async {
    final r = await sb.rpc('accept_quote', params: {'p_quote_id': quoteId});
    _touch();
    return r == true;
  }

  @override
  Future<void> rejectQuote(String quoteId) async {
    await sb.rpc('reject_quote', params: {'p_quote_id': quoteId});
    _touch();
  }

  @override
  Future<void> expireQuotes() async {
    try {
      await sb.rpc('expire_quotes');
    } catch (_) {}
  }

  // ------------------------------------------------------------ العقود
  @override
  Future<List<Contract>> listContracts({String? orderId}) async {
    final rows = await _rows('contracts:${orderId ?? 'all'}', () {
      var q = sb.from('contracts').select().isFilter('deleted_at', null);
      if (orderId != null) q = q.eq('order_id', orderId);
      return q.order('created_at', ascending: false);
    });
    return rows.map(Contract.fromJson).toList();
  }

  @override
  Future<List<ContractTemplate>> listTemplates() async {
    final r = await sb.from('contract_templates').select().order('section');
    return (r as List).map((e) => ContractTemplate.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<void> saveTemplate(String id, String ar, String en) async {
    await sb.from('contract_templates').update({'body_ar': ar, 'body_en': en}).eq('id', id);
    _touch();
  }

  @override
  Future<Contract> createContract({required String orderId, required String ar, required String en, String? parentId, String? templateId}) async {
    final r = await sb.from('contracts').insert({
      'order_id': orderId, 'template_id': templateId, 'rendered_ar': ar, 'rendered_en': en, 'status': 'draft',
      if (parentId != null) 'parent_contract_id': parentId,
      if (parentId != null) 'kind': 'addendum',
    }).select().single();
    final id = '${r['id']}';
    final ar2 = ar.replaceAll('{{CONTRACT_ID}}', id);
    final en2 = en.replaceAll('{{CONTRACT_ID}}', id);
    await sb.from('contracts').update({'rendered_ar': ar2, 'rendered_en': en2}).eq('id', id);
    if (parentId == null) {
      final o = await getOrder(orderId);
      if (o.status == 'accepted') {
        final st = await getSettings();
        await sb.from('orders').update({'status': 'contract_pending', 'deposit_mad': pct(o.totalMad, st.depositPct)}).eq('id', orderId);
      }
    }
    _touch();
    final m = Map<String, dynamic>.from(r);
    m['rendered_ar'] = ar2;
    m['rendered_en'] = en2;
    return Contract.fromJson(m);
  }

  @override
  Future<void> updateContractText(String id, String ar, String en) async {
    await sb.from('contracts').update({'rendered_ar': ar, 'rendered_en': en}).eq('id', id);
    _touch();
  }

  @override
  Future<void> sendContractToClient(String id) async {
    await sb.from('contracts').update({'status': 'awaiting_client'}).eq('id', id);
    _touch();
  }

  @override
  Future<void> voidContract(String id) async {
    await sb.from('contracts').update({'status': 'void'}).eq('id', id);
    _touch();
  }

  @override
  Future<void> signAsClient(String id, String signature) async {
    await sb.rpc('sign_contract', params: {'p_contract_id': id, 'p_signature': signature});
    _touch();
  }

  @override
  Future<void> signAsAdmin(String id, String signature) async {
    await sb.rpc('admin_sign_contract', params: {'p_contract_id': id, 'p_signature': signature});
    _touch();
  }

  // ------------------------------------------------------------ الدفع
  @override
  Future<List<Payment>> listPayments({String? orderId}) async {
    final rows = await _rows('payments:${orderId ?? 'all'}', () {
      var q = sb.from('payments').select().isFilter('deleted_at', null);
      if (orderId != null) q = q.eq('order_id', orderId);
      return q.order('created_at', ascending: false);
    });
    return rows.map(Payment.fromJson).toList();
  }

  @override
  Future<void> submitPayment({required String orderId, required String kind, required int amount, String? receiptPath}) async {
    await sb.from('payments').insert({'order_id': orderId, 'kind': kind, 'amount_mad': amount, 'method': 'bank', 'receipt_path': receiptPath});
    _touch();
  }

  @override
  Future<void> confirmPayment(String id) async {
    await sb.from('payments').update({'confirmed_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    _touch();
  }

  @override
  Future<void> addFine(String orderId, int amount) async {
    await sb.from('payments').insert({'order_id': orderId, 'kind': 'fine', 'amount_mad': amount, 'method': 'bank'});
    _touch();
  }

  @override
  Future<List<Invoice>> listInvoices({String? orderId}) async {
    final rows = await _rows('invoices:${orderId ?? 'all'}', () {
      var q = sb.from('invoices').select().isFilter('deleted_at', null);
      if (orderId != null) q = q.eq('order_id', orderId);
      return q.order('issued_at', ascending: false);
    });
    return rows.map(Invoice.fromJson).toList();
  }

  // ------------------------------------------------------------ المحادثة
  Future<void> _loadNames() async {
    if (_names != null) return;
    try {
      final r = await sb.from('profiles').select('id,full_name,role');
      _names = {for (final e in (r as List)) '${(e as Map)['id']}': {'n': '${e['full_name']}', 'r': '${e['role']}'}};
    } catch (_) {
      _names = {};
    }
  }

  ChatMsg _toMsg(Map<String, dynamic> j) {
    final n = _names?['${j['sender_id']}'];
    final m = ChatMsg.fromJson(j);
    return ChatMsg(
      id: m.id, orderId: m.orderId, senderId: m.senderId, body: m.body, attachmentPath: m.attachmentPath,
      senderName: n?['n'], senderRole: n?['r'], createdAt: m.createdAt,
    );
  }

  @override
  Stream<List<ChatMsg>> watchMessages(String orderId) async* {
    await _loadNames();
    yield* sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map((r) => _toMsg(Map<String, dynamic>.from(r))).toList());
  }

  @override
  Future<void> sendMessage(String orderId, String body, {String? attachmentPath}) async {
    try {
      await sb.from('messages').insert({'order_id': orderId, 'sender_id': userId, 'body': body, 'attachment_path': attachmentPath});
      _touch();
    } catch (e) {
      if (looksOffline(e)) {
        await _enqueue({'type': 'message', 'order_id': orderId, 'body': body, 'attachment_path': attachmentPath});
        return;
      }
      rethrow;
    }
  }

  @override
  Future<List<ConvPreview>> conversations() async {
    final me = await currentProfile();
    final orders = me?.role == 'client' ? await listMyOrders() : await listOrders();
    await _loadNames();
    final rows = await _rows('lastmsgs', () => sb.from('messages').select('id,order_id,sender_id,body,created_at').order('created_at', ascending: false).limit(400));
    final last = <String, ChatMsg>{};
    for (final r in rows) {
      final id = '${r['order_id']}';
      if (!last.containsKey(id)) last[id] = _toMsg(r);
    }
    final out = orders.map((o) => ConvPreview(o, last[o.id])).toList();
    out.sort((a, b) => (b.last?.createdAt ?? b.order.createdAt).compareTo(a.last?.createdAt ?? a.order.createdAt));
    return out;
  }

  @override
  Future<List<ChatMsg>> allMessages() async {
    final r = await sb.from('messages').select('id,order_id,sender_id,body,created_at').order('created_at').limit(3000);
    await _loadNames();
    return (r as List).map((e) => _toMsg(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Stream<List<AppNotification>> watchNotifications() {
    final uid = userId;
    if (uid == null) return const Stream.empty();
    return sb
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(50)
        .map((rows) => rows.map((r) => AppNotification.fromJson(Map<String, dynamic>.from(r))).toList());
  }

  @override
  Future<void> markNotificationsRead() async {
    await sb.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('user_id', userId!).isFilter('read_at', null);
  }

  // ------------------------------------------------------------ الإعدادات
  @override
  Future<CompanySettings> getSettings() async {
    try {
      final r = await sb.from('company_settings').select().maybeSingle();
      return r == null ? CompanySettings() : CompanySettings.fromJson(Map<String, dynamic>.from(r));
    } catch (_) {
      return CompanySettings();
    }
  }

  @override
  Future<void> saveSettings(CompanySettings s) async {
    await sb.from('company_settings').update(s.toJson()).eq('id', true);
    _touch();
  }

  List<PriceTier> _defaultTiers() => [
        PriceTier(code: 'small', labelAr: 'صغير', labelEn: 'Small', price: 150),
        PriceTier(code: 'medium', labelAr: 'متوسط', labelEn: 'Medium', price: 350),
        PriceTier(code: 'large', labelAr: 'كبير', labelEn: 'Large', price: 700),
        PriceTier(code: 'premium', labelAr: 'مميّز', labelEn: 'Premium', price: 950),
      ];

  @override
  Future<List<PriceTier>> getTiers() async {
    try {
      final r = await sb.from('price_tiers').select().order('sort');
      final l = (r as List).map((e) => PriceTier.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      return l.isEmpty ? _defaultTiers() : l;
    } catch (_) {
      return _defaultTiers();
    }
  }

  @override
  Future<void> saveTier(String code, int price) async {
    await sb.from('price_tiers').update({'price_mad': price}).eq('code', code);
    _touch();
  }

  @override
  Future<List<BriefQuestion>> getBriefQuestions() async {
    try {
      final r = await sb.from('brief_questions').select().order('sort');
      final l = (r as List).map((e) => BriefQuestion.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      return l.isEmpty ? Catalog.briefQuestions : l;
    } catch (_) {
      return Catalog.briefQuestions;
    }
  }

  @override
  Future<void> saveBriefQuestion(BriefQuestion q) async {
    await sb.from('brief_questions').upsert({
      'key': q.key, 'grp': q.group, 'label_ar': q.labelAr, 'label_en': q.labelEn, 'type': q.type,
      'options': q.options, 'active': q.active, 'sort': q.sort,
    });
    _touch();
  }

  @override
  Future<List<AuditRow>> listAudit() async {
    final r = await sb.from('audit_log').select('*, actor:profiles!actor_id(full_name)').order('created_at', ascending: false).limit(200);
    return (r as List).map((e) => AuditRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  // ------------------------------------------------------------ طلبات التعديل والإلغاء
  @override
  Future<List<ChangeRequest>> listChangeRequests({String? orderId}) async {
    try {
      var q = sb.from('order_change_requests').select();
      if (orderId != null) q = q.eq('order_id', orderId);
      final r = await q.order('created_at', ascending: false);
      return (r as List).map((e) => ChangeRequest.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      if (looksOffline(e)) rethrow;
      return [];
    }
  }

  @override
  Future<void> createChangeRequest(String orderId, String kind, String note) async {
    await sb.from('order_change_requests').insert({'order_id': orderId, 'kind': kind, 'note': note, 'created_by': userId});
    _touch();
  }

  @override
  Future<void> resolveChangeRequest(String id, bool approve, int fee) async {
    final r = await sb.from('order_change_requests').select().eq('id', id).single();
    final c = ChangeRequest.fromJson(Map<String, dynamic>.from(r));
    await sb.from('order_change_requests').update({'status': approve ? 'approved' : 'rejected', 'fee_mad': fee, 'resolved_by': userId}).eq('id', id);
    if (approve) {
      if (c.isCancel) {
        await sb.from('orders').update({'status': 'cancelled'}).eq('id', c.orderId);
        if (fee > 0) await sb.from('payments').insert({'order_id': c.orderId, 'kind': 'fine', 'amount_mad': fee, 'method': 'bank'});
      } else if (fee > 0) {
        await sb.from('payments').insert({'order_id': c.orderId, 'kind': 'modification', 'amount_mad': fee, 'method': 'bank'});
      }
    }
    _touch();
  }

  // ------------------------------------------------------------ المحاسبة والنقاط
  @override
  Future<List<Expense>> listExpenses() async {
    final r = await sb.from('expenses').select().order('expense_date', ascending: false);
    return (r as List).map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<void> addExpense({required DateTime date, required String account, required String description, required int amount, required String method}) async {
    await sb.from('expenses').insert({
      'expense_date': _dateOnly(date), 'account_code': account, 'description': description, 'amount_mad': amount, 'method': method,
    });
    _touch();
  }

  @override
  Future<List<ScoreRow>> leaderboard() async {
    try {
      final r = await sb.from('v_employee_leaderboard').select();
      return (r as List).map((e) => ScoreRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ScoreEntry>> scoresFor(String orderId) async {
    try {
      final r = await sb.from('employee_scores').select().eq('order_id', orderId);
      return (r as List).map((e) => ScoreEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> setManagerRating(String orderId, String employeeId, int rating) async {
    await sb.from('employee_scores').update({'manager_rating': rating}).eq('order_id', orderId).eq('employee_id', employeeId);
    _touch();
  }

  @override
  Future<void> rateEmployee(String orderId, String employeeId, int rating) async {
    await sb.rpc('rate_employee', params: {'p_order_id': orderId, 'p_employee_id': employeeId, 'p_rating': rating});
    _touch();
  }

  @override
  Future<List<Assignment>> assignments(String orderId) async {
    try {
      final r = await sb.from('order_assignments').select().eq('order_id', orderId);
      return (r as List).map((e) => Assignment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<TeamMember>> orderTeam(String orderId) async {
    try {
      final r = await sb.rpc('order_team', params: {'p_order_id': orderId});
      return (r as List).map((e) => TeamMember.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> assignEmployee(String orderId, String employeeId, String role) async {
    await sb.from('order_assignments').upsert({'order_id': orderId, 'employee_id': employeeId, 'assigned_by': userId, 'role': role}, onConflict: 'order_id,employee_id');
    _touch();
  }

  void dispose() {
    _poll?.cancel();
    _outboxTimer?.cancel();
    _chan?.unsubscribe();
  }
}
