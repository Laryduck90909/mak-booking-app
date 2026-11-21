import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../data/catalog.dart';
import '../../data/contract_builder.dart';
import '../../models/models.dart';
import 'contract_view.dart';
import 'order_files.dart';

bool get _isStaffSide => appState.role == 'staff' || appState.role == 'admin';
bool get _isAdminView => appState.role == 'admin';
bool get _isClientView => appState.role == 'client';

// ------------------------------------------------------------------
// نموذج حوار عام: حقول نصية/رقمية تُعاد كخريطة
// ------------------------------------------------------------------
class AskField {
  final String key, label, initial, hint;
  final bool number, enabled;
  final int lines;
  const AskField(this.key, this.label, {this.initial = '', this.hint = '', this.number = false, this.lines = 1, this.enabled = true});
}

Future<Map<String, String>?> askForm(
  BuildContext context, {
  required String title,
  required List<AskField> fields,
  String? intro,
  String? okLabel,
}) {
  return showPanelDialog<Map<String, String>>(
    context,
    title: title,
    width: 460,
    builder: (ctx) => _AskForm(fields: fields, intro: intro, okLabel: okLabel ?? t('حفظ', 'Save')),
  );
}

class _AskForm extends StatefulWidget {
  final List<AskField> fields;
  final String? intro;
  final String okLabel;
  const _AskForm({required this.fields, this.intro, required this.okLabel});
  @override
  State<_AskForm> createState() => _AskFormState();
}

class _AskFormState extends State<_AskForm> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.intro != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.intro!, style: ts(p, size: 12, color: p.muted, height: 1.6))),
      for (final f in widget.fields) ...[
        MakField(
          controller: _c[f.key]!, label: f.label, hint: f.hint.isEmpty ? null : f.hint, maxLines: f.lines, enabled: f.enabled,
          keyboard: f.number ? TextInputType.number : null,
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 4),
      MakButton(widget.okLabel, onPressed: () => Navigator.pop(context, {for (final e in _c.entries) e.key: e.value.text.trim()})),
    ]);
  }
}

int _toInt(String? s) => int.tryParse((s ?? '').replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;

// ------------------------------------------------------------------
// 1) عروض الأسعار
// ------------------------------------------------------------------
class QuotePanel extends StatelessWidget {
  final Order order;
  const QuotePanel({super.key, required this.order});

  bool get _canPropose => _isStaffSide && (order.status == 'new' || order.status == 'quoted' || order.status == 'rejected' || order.status == 'expired');

  Future<void> _propose(BuildContext context, Quote? last) async {
    final canBase = appState.canEditPrices;
    final startBase = last?.baseTotal ?? (order.totalMad > 0 ? order.totalMad : order.estimate);
    final r = await askForm(
      context,
      title: t('إرسال عرض سعر', 'Send a quote'),
      intro: canBase
          ? t('السعر الأساسي يُحسب من فئات الأسعار. "الفرق" للإضافات المتغيرة، وأي فرق غير صفري يحتاج اعتماد المدير قبل وصوله للعميل.',
              'Base price comes from tiers. "Delta" is for variable extras; any non-zero delta needs admin approval before the client sees it.')
          : t('ليست لديك صلاحية تعديل الأسعار: يُستعمل السعر الأساسي المحسوب فقط. يمكنك اقتراح فرق ليعتمده المدير.',
              'You cannot edit prices: only the computed base is used. You may propose a delta for admin approval.'),
      fields: [
        AskField('base', t('السعر الأساسي (د.م.)', 'Base price (MAD)'), initial: '$startBase', number: true, enabled: canBase),
        AskField('delta', t('الفرق المتغيّر (د.م.)', 'Variable delta (MAD)'), initial: '0', number: true),
        AskField('note', t('ملاحظة للعميل', 'Note to client'), lines: 3),
      ],
      okLabel: t('إرسال', 'Send'),
    );
    if (r == null) return;
    final base = _toInt(r['base']);
    final delta = _toInt(r['delta']);
    if (base <= 0 && delta <= 0) {
      if (context.mounted) toast(context, t('أدخل سعراً صالحاً', 'Enter a valid price'), error: true);
      return;
    }
    await repo.proposeQuote(orderId: order.id, base: base, delta: delta, note: r['note'] ?? '', send: true);
    if (context.mounted) {
      toast(context, (delta != 0 && !_isAdminView) ? t('أُرسل للمدير للاعتماد', 'Sent to admin for approval') : t('أُرسل العرض للعميل', 'Quote sent to client'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<Quote>>(
      load: () => repo.listQuotes(orderId: order.id),
      builder: (context, quotes) {
        final visible = _isClientView ? quotes.where((q) => q.status != 'pending_approval').toList() : quotes;
        final last = visible.isEmpty ? null : visible.first;
        return Panel(
          title: t('عرض السعر', 'Quote'),
          trailing: _canPropose ? MakButton(t('عرض جديد', 'New quote'), icon: Icons.request_quote, dense: true, onPressed: () => _propose(context, last)) : null,
          child: visible.isEmpty
              ? EmptyState(
                  order.needsManualPricing && order.estimate == 0
                      ? t('الأسعار مُعطّلة لهذه الخدمة — يُسعّرها الفريق يدوياً', 'Price is manual for this service — the team will quote it')
                      : t('لم يُرسل عرض بعد', 'No quote yet'),
                  icon: Icons.request_quote_outlined)
              : Column(children: visible.map((q) {
                  final canAct = _isClientView && q.status == 'sent' && !q.expired;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(fmtMad(q.finalTotal), style: ts(p, size: 18, w: FontWeight.w800, color: p.fg))),
                        Pill(q.statusText, color: q.status == 'accepted' ? p.green : (q.status == 'rejected' || q.status == 'expired' ? p.red : p.amber)),
                      ]),
                      if (!_isClientView && q.delta != 0)
                        Text('${t('أساسي', 'Base')} ${fmtMad(q.baseTotal)} + ${t('فرق', 'Delta')} ${fmtMad(q.delta)}', style: ts(p, size: 11.5, color: p.muted)),
                      if (q.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.note, style: ts(p, size: 12.5, color: p.text))),
                      if (q.validUntil != null) Text('${t('صالح حتى', 'Valid until')} ${fmtDate(q.validUntil)}', style: ts(p, size: 11, color: p.subtle)),
                      if (canAct) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: MakButton(t('قبول العرض', 'Accept'), icon: Icons.check, onPressed: () async {
                            final ok = await repo.acceptQuote(q.id);
                            if (context.mounted) toast(context, ok ? t('تم قبول العرض', 'Quote accepted') : t('انتهت صلاحية العرض', 'Quote expired'), error: !ok);
                          })),
                          const SizedBox(width: 8),
                          Expanded(child: MakButton(t('رفض', 'Reject'), kind: 'danger', onPressed: () async {
                            if (await confirmDialog(context, t('رفض هذا العرض؟', 'Reject this quote?'), danger: true)) await repo.rejectQuote(q.id);
                          })),
                        ]),
                      ],
                      if (_isAdminView && q.status == 'pending_approval') ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: MakButton(t('اعتماد وإرسال', 'Approve & send'), icon: Icons.verified, onPressed: () => repo.approveQuote(q.id))),
                          const SizedBox(width: 8),
                          Expanded(child: MakButton(t('رفض المقترح', 'Reject'), kind: 'danger', onPressed: () => repo.rejectProposal(q.id))),
                        ]),
                      ],
                    ]),
                  );
                }).toList()),
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// 2) العقود
// ------------------------------------------------------------------
class ContractsPanel extends StatelessWidget {
  final Order order;
  const ContractsPanel({super.key, required this.order});

  Future<void> _create(BuildContext context, List<Contract> existing) async {
    final templates = await repo.listTemplates();
    final settings = await repo.getSettings();
    ContractTemplate? tpl;
    for (final x in templates) {
      if (x.section == order.section) tpl = x;
    }
    if (tpl == null) {
      for (final x in templates) {
        if (x.section == 'general') tpl = x;
      }
    }
    final texts = buildContractTexts(
      order: order, settings: settings,
      templateAr: (tpl != null && tpl.bodyAr.trim().isNotEmpty) ? tpl.bodyAr : null,
      templateEn: (tpl != null && tpl.bodyEn.trim().isNotEmpty) ? tpl.bodyEn : null,
    );
    final c = await repo.createContract(orderId: order.id, ar: texts.ar, en: texts.en, templateId: tpl?.id);
    if (context.mounted) {
      toast(context, t('أُنشئت مسودة العقد — راجعها ثم أرسلها للعميل', 'Draft created — review then send to client'));
      await showContractDialog(context, c);
    }
  }

  Future<void> _addendum(BuildContext context, Contract parent) async {
    final r = await askForm(
      context,
      title: t('ملحق عقد', 'Contract addendum'),
      intro: t('الملحق يعدّل العقد الأصلي ولا يسري إلا بتوقيع الطرفين.', 'An addendum amends the original and takes effect only when both parties sign.'),
      fields: [
        AskField('title', t('العنوان', 'Title'), initial: t('تعديل نطاق العمل', 'Scope change')),
        AskField('body', t('نص الملحق (السعر والمدة والتغيير)', 'Addendum text (price, duration, change)'), lines: 6),
      ],
      okLabel: t('إنشاء الملحق', 'Create'),
    );
    if (r == null || (r['body'] ?? '').isEmpty) return;
    final settings = await repo.getSettings();
    final texts = buildContractTexts(order: order, settings: settings, addendumTitle: r['title'], addendumBody: r['body']);
    final c = await repo.createContract(orderId: order.id, ar: texts.ar, en: texts.en, parentId: parent.id);
    if (context.mounted) await showContractDialog(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<Contract>>(
      load: () => repo.listContracts(orderId: order.id),
      builder: (context, all) {
        final list = all.where((c) => c.status != 'void' || _isStaffSide).toList();
        final mainActive = all.where((c) => !c.isAddendum && c.status != 'void').toList();
        final signedMain = mainActive.where((c) => c.signed).toList();
        final canCreate = _isStaffSide && mainActive.isEmpty && (order.status == 'accepted' || order.status == 'contract_pending');
        return Panel(
          title: t('العقد', 'Contract'),
          trailing: Wrap(spacing: 6, children: [
            if (canCreate) MakButton(t('إنشاء العقد', 'Create contract'), icon: Icons.description, dense: true, onPressed: () => _create(context, all)),
            if (_isStaffSide && signedMain.isNotEmpty && !order.isClosed)
              MakButton(t('ملحق', 'Addendum'), icon: Icons.post_add, kind: 'ghost', dense: true, onPressed: () => _addendum(context, signedMain.first)),
          ]),
          child: list.isEmpty
              ? EmptyState(
                  order.status == 'accepted' || order.status == 'contract_pending'
                      ? t('بانتظار إعداد العقد من الفريق', 'Waiting for the team to prepare the contract')
                      : t('يُنشأ العقد بعد قبول العرض', 'The contract is created after the quote is accepted'),
                  icon: Icons.description_outlined)
              : Column(children: list.map((c) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showContractDialog(context, c),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
                      child: Row(children: [
                        Icon(c.isAddendum ? Icons.post_add : Icons.description_outlined, color: p.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.id, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                          Text('${c.isAddendum ? t('ملحق', 'Addendum') : t('عقد رئيسي', 'Main contract')} · ${fmtDate(c.createdAt)}', style: ts(p, size: 11, color: p.muted)),
                        ])),
                        Pill(c.statusText, color: contractColor(p, c.status)),
                      ]),
                    ),
                  );
                }).toList()),
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// 3) الدفع
// ------------------------------------------------------------------
class PaymentsPanel extends StatelessWidget {
  final Order order;
  const PaymentsPanel({super.key, required this.order});

  Future<void> _submit(BuildContext context, int remaining, int deposit, bool depositPaid) async {
    final kind = depositPaid ? 'full' : 'deposit';
    final suggested = depositPaid ? remaining : (deposit > 0 ? deposit : remaining);
    final r = await askForm(
      context,
      title: depositPaid ? t('دفع المبلغ المتبقي', 'Pay the remaining balance') : t('دفع العربون', 'Pay the deposit'),
      intro: t('حوّل المبلغ إلى الحساب البنكي المعروض، ثم أدخل المبلغ وارفع صورة الوصل.', 'Transfer to the bank account shown, then enter the amount and upload the receipt.'),
      fields: [AskField('amount', t('المبلغ المحوَّل (د.م.)', 'Amount transferred (MAD)'), initial: '$suggested', number: true)],
      okLabel: t('اختيار الوصل ورفعه', 'Choose receipt & submit'),
    );
    if (r == null) return;
    final amount = _toInt(r['amount']);
    if (amount <= 0) {
      if (context.mounted) toast(context, t('أدخل مبلغاً صالحاً', 'Enter a valid amount'), error: true);
      return;
    }
    if (!context.mounted) return;
    final files = await pickFiles(context, multiple: false, ext: const ['png', 'jpg', 'jpeg', 'pdf', 'webp']);
    String? path;
    if (files.isNotEmpty) path = await repo.uploadFile('receipts', order.id, files.first.name, files.first.bytes);
    await repo.submitPayment(orderId: order.id, kind: kind, amount: amount, receiptPath: path);
    if (context.mounted) toast(context, t('أُرسل الوصل — بانتظار تأكيد الفريق', 'Receipt sent — awaiting confirmation'));
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<Payment>>(
      load: () => repo.listPayments(orderId: order.id),
      builder: (context, pays) {
        final paid = pays.where((x) => x.confirmed && (x.kind == 'deposit' || x.kind == 'full')).fold<int>(0, (a, b) => a + b.amount);
        final depositPaid = pays.any((x) => x.confirmed && x.kind == 'deposit') || paid >= order.depositMad && paid > 0;
        final remaining = (order.totalMad - paid) < 0 ? 0 : order.totalMad - paid;
        final canPay = _isClientView && order.totalMad > 0 && remaining > 0 && order.status != 'cancelled' && order.status != 'new' && order.status != 'quoted' && order.status != 'accepted';
        return Panel(
          title: t('الدفع', 'Payments'),
          trailing: canPay ? MakButton(depositPaid ? t('دفع المتبقي', 'Pay balance') : t('دفع العربون', 'Pay deposit'), icon: Icons.payments, dense: true, onPressed: () => _submit(context, remaining, order.depositMad, depositPaid)) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (order.totalMad > 0)
              Wrap(spacing: 16, runSpacing: 6, children: [
                _mini(p, t('الإجمالي', 'Total'), fmtMad(order.totalMad)),
                _mini(p, t('العربون', 'Deposit'), fmtMad(order.depositMad)),
                _mini(p, t('المدفوع', 'Paid'), fmtMad(paid)),
                _mini(p, t('المتبقي', 'Remaining'), fmtMad(remaining)),
              ]),
            if (_isClientView && order.totalMad > 0 && remaining > 0) ...[
              const SizedBox(height: 10),
              const _BankInfo(),
            ],
            const SizedBox(height: 10),
            if (pays.isEmpty)
              EmptyState(t('لا توجد دفعات', 'No payments'), icon: Icons.payments_outlined)
            else
              ...pays.map((x) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${x.kindText} — ${fmtMad(x.amount)}', style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                        Text(fmtDateTime(x.createdAt), style: ts(p, size: 11, color: p.muted)),
                      ])),
                      if (x.receiptPath != null)
                        IconBtn(Icons.receipt_long, tooltip: t('الوصل', 'Receipt'), onTap: () => openStoredFile(context, 'receipts', x.receiptPath!)),
                      const SizedBox(width: 8),
                      if (x.confirmed)
                        Pill(t('مؤكَّد', 'Confirmed'), color: p.green)
                      else if (_isStaffSide)
                        MakButton(t('تأكيد الاستلام', 'Confirm'), dense: true, onPressed: () async {
                          if (await confirmDialog(context, t('تأكيد استلام ${fmtMad(x.amount)}؟ لا يمكن التراجع.', 'Confirm receipt of ${fmtMad(x.amount)}? This cannot be undone.'))) {
                            await repo.confirmPayment(x.id);
                          }
                        })
                      else
                        Pill(t('بانتظار التأكيد', 'Pending'), color: p.amber),
                    ]),
                  )),
            if (_isAdminView && !order.isClosed) ...[
              const SizedBox(height: 4),
              MakButton(t('إضافة غرامة', 'Add fine'), icon: Icons.gavel, kind: 'danger', dense: true, onPressed: () async {
                final r = await askForm(context, title: t('غرامة على الطلب', 'Fine on order'), fields: [AskField('amount', t('المبلغ (د.م.)', 'Amount (MAD)'), number: true)]);
                if (r == null) return;
                final a = _toInt(r['amount']);
                if (a > 0) await repo.addFine(order.id, a);
              }),
            ],
          ]),
        );
      },
    );
  }

  Widget _mini(Palette p, String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: ts(p, size: 10.5, color: p.muted)),
        Text(v, style: ts(p, size: 14, w: FontWeight.w800, color: p.fg)),
      ]);
}

class _BankInfo extends StatelessWidget {
  const _BankInfo();

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<CompanySettings>(
      load: () => repo.getSettings(),
      builder: (context, s) {
        Widget row(String k, String v, {bool copy = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 90, child: Text(k, style: ts(p, size: 11.5, color: p.muted))),
                Expanded(child: SelectableText(v.isEmpty ? '—' : v, style: ts(p, size: 12.5, w: FontWeight.w700, color: p.fg))),
                if (copy && v.isNotEmpty)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: v));
                      toast(context, t('تم النسخ', 'Copied'));
                    },
                    child: Icon(Icons.copy, size: 16, color: p.accent),
                  ),
              ]),
            );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.accent.fade(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.accent.fade(0.3))),
          child: Column(children: [
            row(t('المستفيد', 'Beneficiary'), s.accountHolder),
            row(t('البنك', 'Bank'), s.bankName),
            row('RIB', s.rib, copy: true),
          ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// 4) إجراءات الحالة (للفريق)
// ------------------------------------------------------------------
class StatusActions extends StatelessWidget {
  final Order order;
  const StatusActions({super.key, required this.order});

  List<(String, String)> _next() {
    switch (order.status) {
      case 'in_progress':
        return [('preview_sent', t('إرسال المعاينة للعميل', 'Send preview to client'))];
      case 'preview_sent':
        return [('in_progress', t('العودة للتنفيذ (مراجعة)', 'Back to work (revision)'))];
      case 'paid':
        return [('delivered', t('تسليم النسخة النهائية', 'Deliver final version'))];
      case 'delivered':
        return [('completed', t('إغلاق الطلب كمكتمل', 'Mark as completed'))];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final next = _next();
    if (!_isStaffSide || next.isEmpty) return const SizedBox();
    return Panel(
      title: t('الخطوة التالية', 'Next step'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (order.status == 'in_progress')
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(t('ارفع ملفات المعاينة أولاً (قسم المعاينات)، ثم أرسلها.', 'Upload preview files first (Previews section), then send.'), style: ts(p, size: 12, color: p.muted)),
          ),
        Wrap(spacing: 8, runSpacing: 8, children: next.map((n) {
          return MakButton(n.$2, icon: Icons.arrow_forward, onPressed: () async {
            await repo.setOrderStatus(order.id, n.$1);
            if (context.mounted) toast(context, t('تم تحديث الحالة', 'Status updated'));
          });
        }).toList()),
      ]),
    );
  }
}

// ------------------------------------------------------------------
// 5) طلبات التعديل والإلغاء
// ------------------------------------------------------------------
class ChangeRequestsPanel extends StatelessWidget {
  final Order order;
  const ChangeRequestsPanel({super.key, required this.order});

  bool get _clientCanAsk =>
      _isClientView && (order.status == 'in_progress' || order.status == 'preview_sent' || order.status == 'contract_pending' || order.status == 'paid');

  Future<void> _ask(BuildContext context) async {
    final s = await repo.getSettings();
    if (!context.mounted) return;
    final free = order.freeWindowOpen;
    final r = await showPanelDialog<(String, String)>(
      context,
      title: t('طلب تعديل أو إلغاء', 'Request change or cancellation'),
      width: 480,
      builder: (ctx) => _ChangeForm(free: free, ends: order.freeWindowEnds, s: s),
    );
    if (r == null) return;
    await repo.createChangeRequest(order.id, r.$1, r.$2);
    if (context.mounted) toast(context, t('أُرسل طلبك للفريق', 'Request sent'));
  }

  Future<void> _resolve(BuildContext context, ChangeRequest cr, bool approve) async {
    final s = await repo.getSettings();
    var fee = 0;
    if (approve) {
      if (!order.freeWindowOpen) fee = cr.isCancel ? pct(order.totalMad, s.cancelFinePct) : pct(order.totalMad, s.modifyFeePct);
      if (!context.mounted) return;
      final r = await askForm(
        context,
        title: approve ? t('اعتماد الطلب', 'Approve request') : t('رفض', 'Reject'),
        intro: cr.isCancel
            ? t('اطلب من العميل رمز التحقق (5 أرقام) وأدخله هنا قبل اعتماد الإلغاء.', 'Ask the client for the 5-digit order code and enter it before approving a cancellation.')
            : t('حدّد الرسوم (0 داخل نافذة الأيام الثلاثة).', 'Set the fee (0 inside the 3-day window).'),
        fields: [
          AskField('fee', cr.isCancel ? t('غرامة الإلغاء (د.م.)', 'Cancellation fine (MAD)') : t('رسوم التعديل (د.م.)', 'Modification fee (MAD)'), initial: '$fee', number: true),
          if (cr.isCancel) AskField('code', t('رمز التحقق', 'Verification code'), number: true),
        ],
        okLabel: t('اعتماد', 'Approve'),
      );
      if (r == null) return;
      if (cr.isCancel && (r['code'] ?? '') != order.verificationCode) {
        if (context.mounted) toast(context, t('رمز التحقق غير صحيح', 'Wrong verification code'), error: true);
        return;
      }
      fee = _toInt(r['fee']);
    }
    await repo.resolveChangeRequest(cr.id, approve, fee);
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<ChangeRequest>>(
      load: () => repo.listChangeRequests(orderId: order.id),
      builder: (context, list) {
        if (list.isEmpty && !_clientCanAsk) return const SizedBox();
        return Panel(
          title: t('التعديل والإلغاء', 'Changes & cancellation'),
          trailing: _clientCanAsk ? MakButton(t('طلب جديد', 'New request'), icon: Icons.edit_note, dense: true, kind: 'soft', onPressed: () => _ask(context)) : null,
          child: list.isEmpty
              ? EmptyState(t('لا توجد طلبات', 'No requests'), icon: Icons.edit_note)
              : Column(children: list.map((cr) {
                  final pending = cr.status == 'pending';
                  final canResolve = pending && _isStaffSide && (!cr.isCancel || _isAdminView);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(cr.kindText, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg))),
                        Pill(cr.statusText, color: cr.status == 'approved' ? p.green : (cr.status == 'rejected' ? p.red : p.amber)),
                      ]),
                      if (cr.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(cr.note, style: ts(p, size: 12.5, color: p.text))),
                      if (cr.feeMad > 0) Text('${t('الرسوم', 'Fee')}: ${fmtMad(cr.feeMad)}', style: ts(p, size: 11.5, color: p.amber)),
                      if (pending && _isStaffSide && cr.isCancel && !_isAdminView)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t('الإلغاء يعتمده المدير فقط', 'Only the admin approves cancellations'), style: ts(p, size: 11, color: p.muted))),
                      if (canResolve) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: MakButton(t('اعتماد', 'Approve'), dense: true, onPressed: () => _resolve(context, cr, true))),
                          const SizedBox(width: 8),
                          Expanded(child: MakButton(t('رفض', 'Reject'), dense: true, kind: 'danger', onPressed: () => _resolve(context, cr, false))),
                        ]),
                      ],
                    ]),
                  );
                }).toList()),
        );
      },
    );
  }
}

class _ChangeForm extends StatefulWidget {
  final bool free;
  final DateTime? ends;
  final CompanySettings s;
  const _ChangeForm({required this.free, required this.ends, required this.s});
  @override
  State<_ChangeForm> createState() => _ChangeFormState();
}

class _ChangeFormState extends State<_ChangeForm> {
  String _kind = 'modify';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final info = widget.free
        ? t('أنت داخل نافذة الأيام الثلاثة المجانية${widget.ends != null ? ' (تنتهي ${fmtDateTime(widget.ends)})' : ''}.', 'You are inside the free 3-day window${widget.ends != null ? ' (ends ${fmtDateTime(widget.ends)})' : ''}.')
        : t('انتهت النافذة المجانية: التعديل بزيادة ${widget.s.modifyFeePct}% والإلغاء بغرامة ${widget.s.cancelFinePct}% (وفق العقد).', 'Free window ended: modifications cost ${widget.s.modifyFeePct}% extra, cancellation carries a ${widget.s.cancelFinePct}% fine (per contract).');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(info, style: ts(p, size: 12, color: widget.free ? p.green : p.amber, height: 1.6)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        SelectChip(t('طلب تعديل', 'Modification'), selected: _kind == 'modify', onTap: () => setState(() => _kind = 'modify')),
        SelectChip(t('طلب إلغاء', 'Cancellation'), selected: _kind == 'cancel', onTap: () => setState(() => _kind = 'cancel')),
      ]),
      const SizedBox(height: 12),
      MakField(controller: _note, label: t('التفاصيل', 'Details'), maxLines: 4),
      const SizedBox(height: 14),
      MakButton(t('إرسال الطلب', 'Send request'), onPressed: () {
        if (_note.text.trim().isEmpty) {
          toast(context, t('اكتب التفاصيل', 'Write the details'), error: true);
          return;
        }
        Navigator.pop(context, (_kind, _note.text.trim()));
      }),
    ]);
  }
}

// ------------------------------------------------------------------
// 6) الفريق والتقييم
// ------------------------------------------------------------------
class TeamPanel extends StatelessWidget {
  final Order order;
  const TeamPanel({super.key, required this.order});

  static const _roles = ['manager', 'designer', 'developer', 'writer', 'translator', 'reviewer'];

  String _roleName(String r) {
    switch (r) {
      case 'manager': return t('مدير مشروع', 'Manager');
      case 'designer': return t('مصمم', 'Designer');
      case 'developer': return t('مطوّر', 'Developer');
      case 'writer': return t('كاتب', 'Writer');
      case 'translator': return t('مترجم', 'Translator');
      case 'reviewer': return t('مراجع', 'Reviewer');
      default: return r;
    }
  }

  Future<void> _assign(BuildContext context) async {
    final profs = (await repo.listProfiles()).where((x) => x.isStaffOrAdmin && x.active).toList();
    if (!context.mounted) return;
    final r = await showPanelDialog<(String, String)>(
      context,
      title: t('إسناد موظف', 'Assign staff'),
      width: 420,
      builder: (ctx) => _AssignForm(profs: profs, roles: _roles, roleName: _roleName),
    );
    if (r == null) return;
    await repo.assignEmployee(order.id, r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<TeamMember>>(
      load: () => repo.orderTeam(order.id),
      builder: (context, team) {
        final canRate = order.status == 'completed' || order.status == 'delivered';
        if (team.isEmpty && !_isAdminView) return const SizedBox();
        return Panel(
          title: t('فريق العمل', 'Team'),
          trailing: _isAdminView ? MakButton(t('إسناد', 'Assign'), icon: Icons.person_add, dense: true, kind: 'soft', onPressed: () => _assign(context)) : null,
          child: team.isEmpty
              ? EmptyState(t('لم يُسنَد موظف بعد', 'No one assigned yet'), icon: Icons.groups_outlined)
              : Column(children: team.map((m) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
                    child: Row(children: [
                      Avatar(m.name, size: 34),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.name, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                        Text(_roleName(m.role), style: ts(p, size: 11, color: p.muted)),
                      ])),
                      if (_isClientView && canRate)
                        m.clientRating != null
                            ? _stars(p, m.clientRating!)
                            : _RateStars(onPick: (v) => repo.rateEmployee(order.id, m.employeeId, v))
                      else if (_isAdminView && canRate)
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          if (m.clientRating != null) Text('${t('العميل', 'Client')}: ${m.clientRating}/5', style: ts(p, size: 11, color: p.muted)),
                          m.managerRating != null
                              ? Text('${t('المدير', 'Manager')}: ${m.managerRating}/10', style: ts(p, size: 11, color: p.gold, w: FontWeight.w700))
                              : MakButton(t('تقييم المدير', 'Rate'), dense: true, kind: 'soft', onPressed: () async {
                                  final r = await askForm(context, title: t('تقييم الموظف (1–10)', 'Rate staff (1–10)'), fields: [AskField('v', t('التقييم', 'Rating'), number: true)]);
                                  if (r == null) return;
                                  final v = _toInt(r['v']);
                                  if (v < 1 || v > 10) {
                                    if (context.mounted) toast(context, t('من 1 إلى 10', '1 to 10'), error: true);
                                    return;
                                  }
                                  await repo.setManagerRating(order.id, m.employeeId, v);
                                }),
                        ]),
                    ]),
                  );
                }).toList()),
        );
      },
    );
  }

  Widget _stars(Palette p, int v) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => Icon(i < v ? Icons.star : Icons.star_border, size: 18, color: p.gold)));
}

class _RateStars extends StatefulWidget {
  final Future<void> Function(int) onPick;
  const _RateStars({required this.onPick});
  @override
  State<_RateStars> createState() => _RateStarsState();
}

class _RateStarsState extends State<_RateStars> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
      return InkWell(
        onTap: () async {
          if (!await confirmDialog(context, t('تقييم ${i + 1} من 5؟ لا يمكن تغييره لاحقاً.', 'Rate ${i + 1} of 5? This cannot be changed.'))) return;
          setState(() => _v = i + 1);
          try {
            await widget.onPick(i + 1);
          } catch (e) {
            if (context.mounted) toast(context, errMsg(e), error: true);
          }
        },
        child: Icon(i < _v ? Icons.star : Icons.star_border, size: 22, color: p.gold),
      );
    }));
  }
}

class _AssignForm extends StatefulWidget {
  final List<Profile> profs;
  final List<String> roles;
  final String Function(String) roleName;
  const _AssignForm({required this.profs, required this.roles, required this.roleName});
  @override
  State<_AssignForm> createState() => _AssignFormState();
}

class _AssignFormState extends State<_AssignForm> {
  String? _emp;
  String _role = 'designer';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownBox<String>(
        label: t('الموظف', 'Employee'),
        value: _emp,
        items: widget.profs.map((x) => DropdownMenuItem(value: x.id, child: Text(x.display))).toList(),
        onChanged: (v) => setState(() => _emp = v),
      ),
      const SizedBox(height: 10),
      DropdownBox<String>(
        label: t('الدور', 'Role'),
        value: _role,
        items: widget.roles.map((r) => DropdownMenuItem(value: r, child: Text(widget.roleName(r)))).toList(),
        onChanged: (v) => setState(() => _role = v ?? 'designer'),
      ),
      const SizedBox(height: 14),
      MakButton(t('إسناد', 'Assign'), onPressed: _emp == null ? null : () => Navigator.pop(context, (_emp!, _role))),
    ]);
  }
}

// ------------------------------------------------------------------
// 7) المعاينات والتسليم
// ------------------------------------------------------------------
class DeliveryPanels extends StatelessWidget {
  final Order order;
  const DeliveryPanels({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final showPrev = order.status == 'in_progress' || order.status == 'preview_sent' || order.status == 'paid' || order.status == 'delivered' || order.status == 'completed';
    if (!showPrev) return const SizedBox();
    final showFinal = order.status == 'paid' || order.status == 'delivered' || order.status == 'completed';
    return Column(children: [
      FilesPanel(
        title: t('المعاينات (بعلامة مائية)', 'Previews (watermarked)'),
        bucket: 'previews', orderId: order.id,
        canUpload: _isStaffSide && !order.isClosed,
        uploadLabel: t('رفع معاينة', 'Upload preview'),
      ),
      if (showFinal || _isStaffSide) ...[
        const SizedBox(height: 12),
        FilesPanel(
          title: t('النسخة النهائية', 'Final files'),
          bucket: 'deliverables', orderId: order.id,
          canUpload: _isStaffSide && (order.status == 'paid' || order.status == 'delivered'),
          uploadLabel: t('رفع النسخة النهائية', 'Upload final'),
        ),
      ],
    ]);
  }
}

// يُستعمل في order_detail لعرض رسالة تذكير بحدود الألوان (ثابتة)
String colorsRule() => t('من ${AppConfig.minColors} إلى ${AppConfig.maxColors} ألوان', '${AppConfig.minColors}–${AppConfig.maxColors} colors');

// يُبقي استيراد Catalog مستخدماً حتى لو تغيّر الكود لاحقاً
String styleNameOf(Order o) => Catalog.style(o.styleKey)?.name ?? '';
