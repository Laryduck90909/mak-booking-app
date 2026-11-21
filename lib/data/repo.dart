import 'dart:typed_data';
import '../models/models.dart';

enum SignUpResult { signedIn, needsEmailConfirm }

class ConvPreview {
  final Order order;
  final ChatMsg? last;
  ConvPreview(this.order, this.last);
}

/// واجهة موحّدة: SupabaseRepo (حقيقي) و DemoRepo (تجريبي).
abstract class Repo {
  /// يُطلق عند أي تغيير في البيانات لتحديث الشاشات.
  Stream<void> get changes;
  String? get userId;
  bool get isDemo;

  // ---- المصادقة ----
  Future<SignUpResult> signUp(String email, String password, String fullName);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> resendConfirmation(String email);
  Future<Profile?> currentProfile();
  Future<void> demoSignIn(String role);

  // ---- الملفات الشخصية والصلاحيات ----
  Future<List<Profile>> listProfiles();
  Future<void> setRole(String userId, String role);
  Future<void> setActive(String userId, bool active);
  Future<void> updateMyProfile({required String fullName, String? phone});
  Future<Map<String, bool>> staffPermissions();
  Future<void> setCanEditPrices(String employeeId, bool v);
  Future<bool> myCanEditPrices();

  // ---- الطلبات ----
  Future<List<Order>> listOrders();
  Future<List<Order>> listMyOrders();
  Future<Order> getOrder(String id);
  Future<Order?> createOrder({required String section, required String title, required Map<String, dynamic> payload});
  Future<void> setOrderStatus(String id, String status);
  Future<void> setDeposit(String id, int depositMad);

  // ---- الملفات ----
  Future<String> uploadFile(String bucket, String orderId, String name, Uint8List bytes);
  Future<List<FileRef>> listFiles(String bucket, String orderId);
  Future<String> fileUrl(String bucket, String path);

  // ---- عروض الأسعار ----
  Future<List<Quote>> listQuotes({String? orderId});
  Future<void> proposeQuote({required String orderId, required int base, required int delta, required String note, required bool send});
  Future<void> approveQuote(String quoteId);
  Future<void> rejectProposal(String quoteId);
  Future<bool> acceptQuote(String quoteId);
  Future<void> rejectQuote(String quoteId);
  Future<void> expireQuotes();

  // ---- العقود ----
  Future<List<Contract>> listContracts({String? orderId});
  Future<List<ContractTemplate>> listTemplates();
  Future<void> saveTemplate(String id, String ar, String en);
  Future<Contract> createContract({required String orderId, required String ar, required String en, String? parentId, String? templateId});
  Future<void> updateContractText(String id, String ar, String en);
  Future<void> sendContractToClient(String id);
  Future<void> voidContract(String id);
  Future<void> signAsClient(String id, String signature);
  Future<void> signAsAdmin(String id, String signature);

  // ---- الدفع والفواتير ----
  Future<List<Payment>> listPayments({String? orderId});
  Future<void> submitPayment({required String orderId, required String kind, required int amount, String? receiptPath});
  Future<void> confirmPayment(String id);
  Future<void> addFine(String orderId, int amount);
  Future<List<Invoice>> listInvoices({String? orderId});

  // ---- المحادثة والإشعارات ----
  Stream<List<ChatMsg>> watchMessages(String orderId);
  Future<void> sendMessage(String orderId, String body, {String? attachmentPath});
  Future<List<ConvPreview>> conversations();
  Future<List<ChatMsg>> allMessages();
  Stream<List<AppNotification>> watchNotifications();
  Future<void> markNotificationsRead();

  // ---- الإعدادات ----
  Future<CompanySettings> getSettings();
  Future<void> saveSettings(CompanySettings s);
  Future<List<PriceTier>> getTiers();
  Future<void> saveTier(String code, int price);
  Future<List<BriefQuestion>> getBriefQuestions();
  Future<void> saveBriefQuestion(BriefQuestion q);
  Future<List<AuditRow>> listAudit();

  // ---- طلبات التعديل والإلغاء ----
  Future<List<ChangeRequest>> listChangeRequests({String? orderId});
  Future<void> createChangeRequest(String orderId, String kind, String note);
  Future<void> resolveChangeRequest(String id, bool approve, int fee);

  // ---- المحاسبة والنقاط ----
  Future<List<Expense>> listExpenses();
  Future<void> addExpense({required DateTime date, required String account, required String description, required int amount, required String method});
  Future<List<ScoreRow>> leaderboard();
  Future<List<ScoreEntry>> scoresFor(String orderId);
  Future<void> setManagerRating(String orderId, String employeeId, int rating);
  Future<void> rateEmployee(String orderId, String employeeId, int rating);
  Future<List<Assignment>> assignments(String orderId);
  Future<List<TeamMember>> orderTeam(String orderId);
  Future<void> assignEmployee(String orderId, String employeeId, String role);
}
