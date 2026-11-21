import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/charts.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../orders/order_detail.dart';
import '../orders/order_workflow.dart' show askForm, AskField;
import '../staff/staff_pages.dart' show PricesPage;

// ------------------------------------------------------------------
// النظرة العامة
// ------------------------------------------------------------------
class _AdminData {
  final List<Order> orders;
  final List<Payment> payments;
  final List<Quote> quotes;
  final List<Expense> expenses;
  _AdminData(this.orders, this.payments, this.quotes, this.expenses);
}

class AdminOverview extends StatelessWidget {
  final void Function(String page) go;
  const AdminOverview({super.key, required this.go});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<_AdminData>(
      load: () async => _AdminData(await repo.listOrders(), await repo.listPayments(), await repo.listQuotes(), await repo.listExpenses()),
      builder: (context, d) {
        final confirmed = d.payments.where((x) => x.confirmed).toList();
        final revenue = confirmed.fold<int>(0, (a, b) => a + b.amount);
        final spent = d.expenses.fold<int>(0, (a, b) => a + b.amount);
        final active = d.orders.where((o) => !o.isClosed).length;
        final approvals = d.quotes.where((q) => q.status == 'pending_approval').length;
        final toConfirm = d.payments.where((x) => !x.confirmed).length;

        final now = DateTime.now();
        final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i, 1));
        final monthly = months.map((m) => confirmed.where((x) => x.confirmedAt != null && x.confirmedAt!.year == m.year && x.confirmedAt!.month == m.month).fold<int>(0, (a, b) => a + b.amount).toDouble()).toList();

        final byStatus = <String, int>{};
        for (final o in d.orders) {
          byStatus[o.status] = (byStatus[o.status] ?? 0) + 1;
        }
        final slices = byStatus.entries.map((e) => Slice(statusLabel(e.key), e.value.toDouble(), statusColor(p, e.key))).toList();
        final secs = ['design', 'web', 'writing'];
        final secVals = secs.map((s) => d.orders.where((o) => o.section == s).length.toDouble()).toList();
        final recent = [...d.orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('لوحة المدير', 'Admin dashboard'), subtitle: t('الطبقة العليا: ترى كل شيء وتتحكم في كل شيء', 'Top layer: see and control everything')),
          AdaptiveGrid(minWidth: 190, children: [
            KpiCard(label: t('الإيرادات المؤكدة', 'Confirmed revenue'), value: fmtMad(revenue), icon: Icons.account_balance_wallet_outlined, color: p.green),
            KpiCard(label: t('المصروفات', 'Expenses'), value: fmtMad(spent), icon: Icons.trending_down, color: p.red),
            KpiCard(label: t('الربح', 'Profit'), value: fmtMad(revenue - spent), icon: Icons.savings_outlined, color: (revenue - spent) >= 0 ? p.green : p.red),
            KpiCard(label: t('طلبات نشطة', 'Active orders'), value: '$active', sub: '${d.orders.length} ${t('إجمالي', 'total')}', icon: Icons.work_outline),
            KpiCard(label: t('بانتظار اعتمادك', 'Awaiting your approval'), value: '${approvals + toConfirm}', sub: '$approvals ${t('أسعار', 'quotes')} · $toConfirm ${t('دفعات', 'payments')}', icon: Icons.fact_check_outlined, color: p.amber),
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 820;
            final rev = Panel(title: t('الإيرادات (آخر 6 أشهر)', 'Revenue (last 6 months)'), child: LineChartBox(values: monthly, labels: months.map((m) => '${m.month}').toList(), color: p.accent));
            final st = Panel(
              title: t('الطلبات حسب الحالة', 'Orders by status'),
              child: slices.isEmpty ? EmptyState(t('لا بيانات', 'No data')) : Row(children: [
                DonutBox(slices: slices, centerText: '${d.orders.length}'),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: slices.map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(s.label, style: ts(p, size: 11.5, color: p.text))),
                        Text('${s.value.round()}', style: ts(p, size: 11.5, w: FontWeight.w700, color: p.fg)),
                      ]),
                    )).toList())),
              ]),
            );
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: rev), const SizedBox(width: 12), Expanded(child: st)]);
            }
            return Column(children: [rev, const SizedBox(height: 12), st]);
          }),
          const SizedBox(height: 12),
          Panel(title: t('الطلبات حسب القسم', 'Orders by section'), child: BarChartBox(values: secVals, labels: secs.map(sectionLabel).toList(), color: p.gold, height: 150)),
          const SizedBox(height: 16),
          Panel(
            title: t('أحدث الطلبات', 'Latest orders'),
            trailing: TextButton(onPressed: () => go('orders'), child: Text(t('الكل', 'All'), style: TextStyle(color: p.accent))),
            child: recent.isEmpty ? EmptyState(t('لا طلبات', 'No orders')) : Column(children: recent.take(6).map((o) => OrderTile(order: o, onTap: () => openOrder(context, o.id))).toList()),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// الاعتمادات: أسعار بفرق متغيّر + طلبات إلغاء
// ------------------------------------------------------------------
class ApprovalsPage extends StatelessWidget {
  const ApprovalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<({List<Quote> q, List<Order> o, List<ChangeRequest> cr})>(
      load: () async => (q: await repo.listQuotes(), o: await repo.listOrders(), cr: await repo.listChangeRequests()),
      builder: (context, d) {
        final byId = {for (final o in d.o) o.id: o};
        final pend = d.q.where((q) => q.status == 'pending_approval').toList();
        final crs = d.cr.where((c) => c.status == 'pending').toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('الاعتمادات', 'Approvals'), subtitle: '${pend.length + crs.length} ${t('بانتظارك', 'waiting')}'),
          Panel(
            title: t('مقترحات الأسعار', 'Price proposals'),
            child: pend.isEmpty ? EmptyState(t('لا مقترحات', 'No proposals')) : Column(children: pend.map((q) {
              final o = byId[q.orderId];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () => openOrder(context, q.orderId, tab: 1),
                    child: Text('${o?.title ?? q.orderId} — ${o?.clientName ?? ''}', style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                  ),
                  const SizedBox(height: 4),
                  Text('${fmtMad(q.baseTotal)} + ${fmtMad(q.delta)} = ${fmtMad(q.finalTotal)}', style: ts(p, size: 15, w: FontWeight.w800, color: p.accent)),
                  if (q.note.isNotEmpty) Text(q.note, style: ts(p, size: 12, color: p.muted)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: MakButton(t('اعتماد وإرسال', 'Approve & send'), dense: true, onPressed: () => repo.approveQuote(q.id))),
                    const SizedBox(width: 8),
                    Expanded(child: MakButton(t('رفض', 'Reject'), dense: true, kind: 'danger', onPressed: () => repo.rejectProposal(q.id))),
                  ]),
                ]),
              );
            }).toList()),
          ),
          const SizedBox(height: 12),
          Panel(
            title: t('طلبات تعديل/إلغاء', 'Change / cancel requests'),
            child: crs.isEmpty ? EmptyState(t('لا طلبات', 'No requests')) : Column(children: crs.map((c) {
              final o = byId[c.orderId];
              return InkWell(
                onTap: () => openOrder(context, c.orderId, tab: 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(c.isCancel ? Icons.cancel_outlined : Icons.edit_note, color: c.isCancel ? p.red : p.amber),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c.kindText} — ${o?.title ?? c.orderId}', style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                      Text(c.note, style: ts(p, size: 11.5, color: p.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ])),
                    Icon(isAr ? Icons.chevron_left : Icons.chevron_right, color: p.muted),
                  ]),
                ),
              );
            }).toList()),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// إدارة الفريق والعملاء
// ------------------------------------------------------------------
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  String _role = '';
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<({List<Profile> profs, Map<String, bool> perms})>(
      load: () async => (profs: await repo.listProfiles(), perms: await repo.staffPermissions()),
      builder: (context, d) {
        final q = _q.text.trim().toLowerCase();
        final list = d.profs.where((x) => (_role.isEmpty || x.role == _role) && (q.isEmpty || '${x.fullName} ${x.email}'.toLowerCase().contains(q))).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('المستخدمون', 'Users'), subtitle: '${list.length}/${d.profs.length}'),
          MakField(controller: _q, hint: t('بحث بالاسم أو البريد…', 'Search name or email…'), onChanged: (_) => setState(() {}), suffix: Icon(Icons.search, size: 18, color: p.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            SelectChip(t('الكل', 'All'), selected: _role.isEmpty, onTap: () => setState(() => _role = '')),
            for (final r in const ['admin', 'staff', 'client']) SelectChip(roleLabel(r), selected: _role == r, onTap: () => setState(() => _role = r)),
          ]),
          const SizedBox(height: 14),
          ...list.map((u) {
            final me = u.id == repo.userId;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(u.display, size: 38),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u.display}${me ? ' ${t('(أنت)', '(you)')}' : ''}', style: ts(p, size: 13.5, w: FontWeight.w700, color: p.fg)),
                    Text('${u.email}${u.phone == null ? '' : ' · ${u.phone}'}', style: ts(p, size: 11, color: p.muted)),
                  ])),
                  Pill(roleLabel(u.role), color: u.role == 'admin' ? p.gold : (u.role == 'staff' ? p.teal : p.blue)),
                ]),
                if (!me) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final r in const ['client', 'staff', 'admin'])
                      SelectChip(roleLabel(r), selected: u.role == r, onTap: () async {
                        if (u.role == r) return;
                        if (await confirmDialog(context, t('تغيير دور ${u.display} إلى ${roleLabel(r)}؟', 'Change ${u.display} to ${roleLabel(r)}?'))) {
                          await repo.setRole(u.id, r);
                        }
                      }),
                    SelectChip(u.active ? t('نشط', 'Active') : t('موقوف', 'Suspended'), selected: u.active, icon: u.active ? Icons.check_circle : Icons.block, onTap: () async {
                      await repo.setActive(u.id, !u.active);
                    }),
                    if (u.role == 'staff')
                      SelectChip(t('يعدّل الأسعار', 'Can edit prices'), selected: d.perms[u.id] == true, icon: Icons.sell_outlined, onTap: () async {
                        await repo.setCanEditPrices(u.id, !(d.perms[u.id] == true));
                      }),
                  ]),
                ],
              ]),
            );
          }),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// النقاط والتقييمات
// ------------------------------------------------------------------
class ScoresPage extends StatelessWidget {
  const ScoresPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<ScoreRow>>(
      load: () => repo.leaderboard(),
      builder: (context, rows) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('لوحة الصدارة', 'Leaderboard'), subtitle: t('نقاط الموظفين من تقييم العميل (1–5) وتقييمك (1–10)', 'Staff points from client (1–5) and your (1–10) ratings')),
          if (rows.isEmpty) EmptyState(t('لا بيانات بعد', 'No data yet'), icon: Icons.emoji_events_outlined),
          for (var i = 0; i < rows.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: i == 0 ? p.gold : p.border)),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${i + 1}', style: ts(p, size: 18, w: FontWeight.w900, color: i == 0 ? p.gold : p.muted))),
                Avatar(rows[i].fullName, size: 36),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rows[i].fullName, style: ts(p, size: 13.5, w: FontWeight.w700, color: p.fg)),
                  Text('${rows[i].contracts} ${t('عقد منجز', 'completed')} · ${t('العميل', 'Client')} ${rows[i].avgClient.toStringAsFixed(1)}/5 · ${t('المدير', 'Manager')} ${rows[i].avgManager.toStringAsFixed(1)}/10', style: ts(p, size: 11, color: p.muted)),
                ])),
                Text('${rows[i].points}', style: ts(p, size: 18, w: FontWeight.w900, color: p.accent)),
              ]),
            ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// المحاسبة
// ------------------------------------------------------------------
class AccountingPage extends StatelessWidget {
  const AccountingPage({super.key});

  static const _accounts = [('5100', 'مصاريف تشغيل', 'Operating'), ('5200', 'رواتب', 'Salaries'), ('5300', 'اشتراكات', 'Subscriptions'), ('5400', 'ضرائب', 'Taxes')];

  String _accName(String code) {
    for (final a in _accounts) {
      if (a.$1 == code) return t(a.$2, a.$3);
    }
    return code;
  }

  Future<void> _add(BuildContext context) async {
    final r = await showPanelDialog<Map<String, String>>(context, title: t('إضافة مصروف', 'Add expense'), width: 440, builder: (ctx) => const _ExpenseForm());
    if (r == null) return;
    final amount = int.tryParse(r['amount'] ?? '') ?? 0;
    if (amount <= 0) {
      if (context.mounted) toast(context, t('أدخل مبلغاً صالحاً', 'Enter a valid amount'), error: true);
      return;
    }
    await repo.addExpense(date: DateTime.now(), account: r['account'] ?? '5100', description: r['desc'] ?? '', amount: amount, method: r['method'] ?? 'bank');
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<({List<Payment> pay, List<Expense> exp})>(
      load: () async => (pay: await repo.listPayments(), exp: await repo.listExpenses()),
      builder: (context, d) {
        final inc = d.pay.where((x) => x.confirmed).toList();
        final income = inc.fold<int>(0, (a, b) => a + b.amount);
        final spent = d.exp.fold<int>(0, (a, b) => a + b.amount);
        final now = DateTime.now();
        final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i, 1));
        int incM(DateTime m) => inc.where((x) => x.confirmedAt != null && x.confirmedAt!.year == m.year && x.confirmedAt!.month == m.month).fold<int>(0, (a, b) => a + b.amount);
        int expM(DateTime m) => d.exp.where((x) => x.date.year == m.year && x.date.month == m.month).fold<int>(0, (a, b) => a + b.amount);
        final profit = months.map((m) => (incM(m) - expM(m)).toDouble()).toList();
        final salaries = d.exp.where((e) => e.accountCode == '5200').fold<int>(0, (a, b) => a + b.amount);

        String csv() {
          final b = StringBuffer('date,type,account,description,amount_mad\n');
          for (final x in inc) {
            b.writeln('${fmtDate(x.confirmedAt)},income,${x.kind},${x.orderId},${x.amount}');
          }
          for (final e in d.exp) {
            b.writeln('${fmtDate(e.date)},expense,${e.accountCode},"${e.description.replaceAll('"', "'")}",${e.amount}');
          }
          return b.toString();
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            t('المحاسبة', 'Accounting'),
            trailing: Wrap(spacing: 8, children: [
              MakButton(t('نسخ CSV', 'Copy CSV'), icon: Icons.copy, kind: 'ghost', dense: true, onPressed: () {
                Clipboard.setData(ClipboardData(text: csv()));
                toast(context, t('نُسخ — الصقه في Excel أو Google Sheets', 'Copied — paste into Excel or Google Sheets'));
              }),
              MakButton(t('مصروف', 'Expense'), icon: Icons.add, dense: true, onPressed: () => _add(context)),
            ]),
          ),
          AdaptiveGrid(minWidth: 190, children: [
            KpiCard(label: t('الدخل (مؤكَّد)', 'Income (confirmed)'), value: fmtMad(income), icon: Icons.trending_up, color: p.green),
            KpiCard(label: t('المصروفات', 'Expenses'), value: fmtMad(spent), icon: Icons.trending_down, color: p.red),
            KpiCard(label: t('الصافي', 'Net'), value: fmtMad(income - spent), icon: Icons.savings_outlined, color: income - spent >= 0 ? p.green : p.red),
            KpiCard(label: t('الرواتب', 'Salaries'), value: fmtMad(salaries), icon: Icons.groups_outlined, color: p.violet),
          ]),
          const SizedBox(height: 14),
          Panel(title: t('صافي الربح الشهري', 'Monthly net'), child: BarChartBox(values: profit.map((v) => v < 0 ? 0.0 : v).toList(), labels: months.map((m) => '${m.month}').toList(), color: p.accent, height: 160)),
          const SizedBox(height: 14),
          Panel(
            title: t('المصروفات', 'Expenses'),
            child: d.exp.isEmpty ? EmptyState(t('لا مصروفات', 'No expenses')) : Column(children: d.exp.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.description.isEmpty ? _accName(e.accountCode) : e.description, style: ts(p, size: 13, color: p.fg)),
                      Text('${_accName(e.accountCode)} · ${fmtDate(e.date)} · ${e.method == 'cash' ? t('نقداً', 'Cash') : t('بنك', 'Bank')}', style: ts(p, size: 11, color: p.muted)),
                    ])),
                    Text('-${fmtMad(e.amount)}', style: ts(p, size: 13, w: FontWeight.w700, color: p.red)),
                  ]),
                )).toList()),
          ),
        ]);
      },
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm();
  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  String _acc = '5100';
  String _method = 'bank';
  final _amount = TextEditingController();
  final _desc = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownBox<String>(
        label: t('الحساب', 'Account'),
        value: _acc,
        items: AccountingPage._accounts.map((a) => DropdownMenuItem(value: a.$1, child: Text('${a.$1} — ${t(a.$2, a.$3)}'))).toList(),
        onChanged: (v) => setState(() => _acc = v ?? '5100'),
      ),
      const SizedBox(height: 10),
      MakField(controller: _amount, label: t('المبلغ (د.م.)', 'Amount (MAD)'), keyboard: TextInputType.number),
      const SizedBox(height: 10),
      MakField(controller: _desc, label: t('الوصف', 'Description')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        SelectChip(t('بنك', 'Bank'), selected: _method == 'bank', onTap: () => setState(() => _method = 'bank')),
        SelectChip(t('نقداً', 'Cash'), selected: _method == 'cash', onTap: () => setState(() => _method = 'cash')),
      ]),
      const SizedBox(height: 14),
      MakButton(t('حفظ', 'Save'), onPressed: () => Navigator.pop(context, {'account': _acc, 'method': _method, 'amount': _amount.text.trim(), 'desc': _desc.text.trim()})),
    ]);
  }
}

// ------------------------------------------------------------------
// قوالب العقود
// ------------------------------------------------------------------
class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<ContractTemplate>>(
      load: () => repo.listTemplates(),
      builder: (context, list) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('قوالب العقود', 'Contract templates'), subtitle: t('أي تغيير يسري على العقود الجديدة فقط', 'Changes apply to new contracts only')),
          Panel(
            child: Text('{{CONTRACT_ID}} {{ORDER_ID}} {{DATE}} {{COMPANY_NAME}} {{COMPANY_CITY}} {{COMPANY_EMAIL}} {{CLIENT_NAME}} {{CLIENT_EMAIL}} {{SCOPE}} {{SECTION_NOTE}} {{TOTAL}} {{DEPOSIT}} {{REVISIONS}} {{CANCEL_FINE}} {{MODIFY_FEE}}',
                style: ts(p, size: 11, color: p.muted, height: 1.8), textDirection: TextDirection.ltr),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty) EmptyState(t('لا قوالب — يُستعمل النص الافتراضي', 'No templates — default text is used'), icon: Icons.description_outlined),
          ...list.map((x) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                child: Row(children: [
                  Icon(Icons.description_outlined, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.title.isEmpty ? x.section : x.title, style: ts(p, size: 13.5, w: FontWeight.w700, color: p.fg)),
                    Text('${x.section} · ${x.bodyAr.length} / ${x.bodyEn.length} ${t('حرف', 'chars')}', style: ts(p, size: 11, color: p.muted)),
                  ])),
                  MakButton(t('تعديل', 'Edit'), icon: Icons.edit, dense: true, kind: 'soft', onPressed: () async {
                    final r = await showPanelDialog<(String, String)>(context, title: x.title, width: 820, builder: (ctx) => _TplEditor(tpl: x));
                    if (r == null) return;
                    await repo.saveTemplate(x.id, r.$1, r.$2);
                    if (context.mounted) toast(context, t('تم حفظ القالب', 'Template saved'));
                  }),
                ]),
              )),
        ]);
      },
    );
  }
}

class _TplEditor extends StatefulWidget {
  final ContractTemplate tpl;
  const _TplEditor({required this.tpl});
  @override
  State<_TplEditor> createState() => _TplEditorState();
}

class _TplEditorState extends State<_TplEditor> {
  late final _ar = TextEditingController(text: widget.tpl.bodyAr);
  late final _en = TextEditingController(text: widget.tpl.bodyEn);

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MakField(controller: _ar, label: 'العربية', maxLines: 16, dir: TextDirection.rtl),
      const SizedBox(height: 10),
      MakField(controller: _en, label: 'English', maxLines: 16, dir: TextDirection.ltr),
      const SizedBox(height: 14),
      MakButton(t('حفظ القالب', 'Save template'), icon: Icons.save, onPressed: () => Navigator.pop(context, (_ar.text, _en.text))),
    ]);
  }
}

// ------------------------------------------------------------------
// الإعدادات: الشركة، الأسعار، الأسئلة، سجل التدقيق
// ------------------------------------------------------------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _tab = 'company';

  @override
  Widget build(BuildContext context) {
    final tabs = {
      'company': t('الشركة والبنك', 'Company & bank'),
      'rules': t('النِّسَب والغرامات', 'Percentages & fines'),
      'tiers': t('الأسعار', 'Prices'),
      'brief': t('أسئلة البريف', 'Brief questions'),
      'audit': t('سجل التدقيق', 'Audit log'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(t('الإعدادات', 'Settings')),
      Wrap(spacing: 8, runSpacing: 8, children: tabs.entries.map((e) => SelectChip(e.value, selected: _tab == e.key, onTap: () => setState(() => _tab = e.key))).toList()),
      const SizedBox(height: 14),
      if (_tab == 'company' || _tab == 'rules') _CompanyForm(key: ValueKey(_tab), rules: _tab == 'rules'),
      if (_tab == 'tiers') const PricesPage(),
      if (_tab == 'brief') const _BriefEditor(),
      if (_tab == 'audit') const _AuditList(),
    ]);
  }
}

class _CompanyForm extends StatefulWidget {
  final bool rules;
  const _CompanyForm({super.key, required this.rules});
  @override
  State<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends State<_CompanyForm> {
  final Map<String, TextEditingController> _c = {};
  CompanySettings? _s;

  TextEditingController _ctl(String k, String v) => _c.putIfAbsent(k, () => TextEditingController(text: v));

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncData<CompanySettings>(
      load: () => repo.getSettings(),
      builder: (context, s) {
        _s = s;
        Widget f(String k, String label, String v, {bool numeric = false, TextDirection? dir}) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MakField(controller: _ctl(k, v), label: label, keyboard: numeric ? TextInputType.number : null, dir: dir),
            );
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!widget.rules) ...[
                f('company', t('اسم الشركة', 'Company name'), s.companyName),
                f('city', t('المدينة (تظهر في العقد)', 'City (shown in contract)'), s.city),
                f('email', t('بريد الدعم', 'Support email'), s.email, dir: TextDirection.ltr),
                f('phone', t('هاتف الدعم', 'Support phone'), s.phone, dir: TextDirection.ltr),
                f('whatsapp', t('واتساب (بصيغة دولية بلا +)', 'WhatsApp (international, no +)'), s.whatsapp, dir: TextDirection.ltr),
                f('tax', t('ICE / المعرّف الضريبي', 'Tax ID'), s.taxId, dir: TextDirection.ltr),
                f('holder', t('صاحب الحساب البنكي', 'Account holder'), s.accountHolder),
                f('bank', t('البنك', 'Bank'), s.bankName),
                f('rib', 'RIB', s.rib, dir: TextDirection.ltr),
              ] else ...[
                f('deposit', t('نسبة العربون %', 'Deposit %'), '${s.depositPct}', numeric: true),
                f('cancel', t('غرامة الإلغاء بعد النافذة %', 'Cancellation fine after window %'), '${s.cancelFinePct}', numeric: true),
                f('modify', t('زيادة التعديل بعد النافذة %', 'Modification surcharge after window %'), '${s.modifyFeePct}', numeric: true),
                f('rev', t('جولات المراجعة المشمولة', 'Included revision rounds'), '${s.revisionRounds}', numeric: true),
              ],
              const SizedBox(height: 4),
              MakButton(t('حفظ', 'Save'), icon: Icons.save, onPressed: () async {
                final cur = _s!;
                String g(String k, String d) => _c.containsKey(k) ? _c[k]!.text.trim() : d;
                int gi(String k, int d) => _c.containsKey(k) ? (int.tryParse(_c[k]!.text.trim()) ?? d) : d;
                final n = CompanySettings(
                  companyName: g('company', cur.companyName), city: g('city', cur.city), email: g('email', cur.email),
                  phone: g('phone', cur.phone), whatsapp: g('whatsapp', cur.whatsapp), taxId: g('tax', cur.taxId),
                  accountHolder: g('holder', cur.accountHolder), bankName: g('bank', cur.bankName), rib: g('rib', cur.rib),
                  depositPct: gi('deposit', cur.depositPct), cancelFinePct: gi('cancel', cur.cancelFinePct),
                  modifyFeePct: gi('modify', cur.modifyFeePct), revisionRounds: gi('rev', cur.revisionRounds),
                );
                await repo.saveSettings(n);
                if (context.mounted) toast(context, t('تم الحفظ', 'Saved'));
              }),
            ]),
          ),
        );
      },
    );
  }
}

class _BriefEditor extends StatelessWidget {
  const _BriefEditor();

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<BriefQuestion>>(
      load: () => repo.getBriefQuestions(),
      builder: (context, qs) {
        final list = [...qs]..sort((a, b) => a.sort.compareTo(b.sort));
        BriefQuestion copy(BriefQuestion q, {bool? active, String? ar, String? en}) => BriefQuestion(
              key: q.key, group: q.group, labelAr: ar ?? q.labelAr, labelEn: en ?? q.labelEn, type: q.type, options: q.options, active: active ?? q.active, sort: q.sort);
        return Panel(
          title: t('أسئلة البريف (${list.length})', 'Brief questions (${list.length})'),
          child: Column(children: list.map((q) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 38, child: Text(q.key, style: ts(p, size: 11, color: p.subtle))),
                  Expanded(child: Text(q.label, style: ts(p, size: 12.5, color: q.active ? p.fg : p.subtle))),
                  IconBtn(Icons.edit, onTap: () async {
                    final r = await askForm(context, title: q.key, fields: [AskField('ar', 'العربية', initial: q.labelAr, lines: 2), AskField('en', 'English', initial: q.labelEn, lines: 2)]);
                    if (r == null) return;
                    await repo.saveBriefQuestion(copy(q, ar: r['ar'], en: r['en']));
                  }),
                  const SizedBox(width: 6),
                  SelectChip(q.active ? t('مفعّل', 'On') : t('معطّل', 'Off'), selected: q.active, onTap: () async {
                    await repo.saveBriefQuestion(copy(q, active: !q.active));
                  }),
                ]),
              )).toList()),
        );
      },
    );
  }
}

class _AuditList extends StatelessWidget {
  const _AuditList();

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<AuditRow>>(
      load: () => repo.listAudit(),
      builder: (context, rows) {
        return Panel(
          title: t('آخر العمليات', 'Recent activity'),
          child: rows.isEmpty ? EmptyState(t('لا سجلات', 'No records')) : Column(children: rows.take(100).map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(fmtDateTime(r.createdAt), style: ts(p, size: 10.5, color: p.subtle))),
                  Expanded(child: Text('${r.actorName ?? '—'} · ${r.action} · ${r.entity} ${r.entityId}', style: ts(p, size: 12, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              )).toList()),
        );
      },
    );
  }
}
