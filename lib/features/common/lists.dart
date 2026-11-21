import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../data/repo.dart' show ConvPreview;
import '../../models/models.dart';
import '../orders/contract_view.dart';
import '../orders/order_detail.dart';
import '../orders/pdf_service.dart';

// ------------------------------------------------------------------
// قائمة الطلبات (بحث + تصفية)
// ------------------------------------------------------------------
class OrdersListPage extends StatefulWidget {
  final bool mine; // true: طلبات العميل فقط
  final String scope; // active | closed | all
  final String? title;
  const OrdersListPage({super.key, this.mine = false, this.scope = 'all', this.title});
  @override
  State<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends State<OrdersListPage> {
  final _q = TextEditingController();
  String _status = '';
  String _section = '';
  bool _action = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _needsStaff(Order o) => o.status == 'new' || o.status == 'accepted' || o.status == 'paid' || o.status == 'in_progress';

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final staff = appState.role != 'client';
    return AsyncData<List<Order>>(
      load: () => widget.mine ? repo.listMyOrders() : repo.listOrders(),
      builder: (context, all) {
        var list = all.where((o) {
          if (widget.scope == 'active' && o.isClosed) return false;
          if (widget.scope == 'closed' && !o.isClosed) return false;
          if (_status.isNotEmpty && o.status != _status) return false;
          if (_section.isNotEmpty && o.section != _section) return false;
          if (_action && !_needsStaff(o)) return false;
          final q = _q.text.trim().toLowerCase();
          if (q.isNotEmpty && !('${o.id} ${o.title} ${o.clientName}'.toLowerCase().contains(q))) return false;
          return true;
        }).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(widget.title ?? t('الطلبات', 'Orders'), subtitle: '${list.length} ${t('طلب', 'orders')}'),
          MakField(controller: _q, hint: t('بحث بالرقم أو العنوان أو العميل…', 'Search by id, title or client…'), onChanged: (_) => setState(() {}), suffix: Icon(Icons.search, size: 18, color: p.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (staff && widget.scope != 'closed') SelectChip(t('يحتاج إجراء', 'Needs action'), selected: _action, icon: Icons.bolt, onTap: () => setState(() => _action = !_action)),
            SelectChip(t('كل الأقسام', 'All sections'), selected: _section.isEmpty, onTap: () => setState(() => _section = '')),
            for (final s in const ['design', 'web', 'writing']) SelectChip(sectionLabel(s), selected: _section == s, onTap: () => setState(() => _section = _section == s ? '' : s)),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SelectChip(t('كل الحالات', 'All statuses'), selected: _status.isEmpty, onTap: () => setState(() => _status = '')),
              for (final s in orderStatuses) Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: SelectChip(statusLabel(s), selected: _status == s, onTap: () => setState(() => _status = _status == s ? '' : s))),
            ]),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty) EmptyState(t('لا توجد طلبات', 'No orders')) else ...list.map((o) => OrderTile(order: o, showClient: staff, onTap: () => openOrder(context, o.id))),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// المحادثات
// ------------------------------------------------------------------
class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<ConvPreview>>(
      load: () => repo.conversations(),
      builder: (context, list) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('المحادثات', 'Chats')),
          if (list.isEmpty) EmptyState(t('لا توجد محادثات', 'No chats'), icon: Icons.chat_bubble_outline),
          ...list.map((c) {
            final m = c.last;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openOrder(context, c.order.id, tab: 2),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                child: Row(children: [
                  Avatar(appState.role == 'client' ? 'M' : c.order.clientName, size: 38),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.order.title.isEmpty ? c.order.id : c.order.title, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(m == null ? t('لا رسائل بعد', 'No messages yet') : (m.body.isEmpty ? t('📎 مرفق', '📎 Attachment') : m.body), style: ts(p, size: 12, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  if (m != null) Text(relTime(m.createdAt), style: ts(p, size: 10.5, color: p.subtle)),
                ]),
              ),
            );
          }),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// العقود
// ------------------------------------------------------------------
class ContractsListPage extends StatelessWidget {
  const ContractsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<({List<Contract> c, List<Order> o})>(
      load: () async {
        final c = await repo.listContracts();
        final o = appState.role == 'client' ? await repo.listMyOrders() : await repo.listOrders();
        return (c: c, o: o);
      },
      builder: (context, d) {
        final byId = {for (final o in d.o) o.id: o};
        final list = d.c.where((c) => c.status != 'void' || appState.role != 'client').toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('العقود', 'Contracts'), subtitle: '${list.length}'),
          if (list.isEmpty) EmptyState(t('لا توجد عقود', 'No contracts'), icon: Icons.description_outlined),
          ...list.map((c) {
            final o = byId[c.orderId];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showContractDialog(context, c),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                child: Row(children: [
                  Icon(c.isAddendum ? Icons.post_add : Icons.description_outlined, color: p.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.id}${o == null ? '' : ' — ${o.title}'}', style: ts(p, size: 13, w: FontWeight.w700, color: p.fg), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${c.orderId}${o != null && appState.role != 'client' ? ' · ${o.clientName}' : ''} · ${fmtDate(c.createdAt)}', style: ts(p, size: 11, color: p.muted)),
                  ])),
                  Pill(c.statusText, color: contractColor(p, c.status)),
                ]),
              ),
            );
          }),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// الفواتير
// ------------------------------------------------------------------
class InvoicesListPage extends StatelessWidget {
  const InvoicesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<List<Invoice>>(
      load: () => repo.listInvoices(),
      builder: (context, list) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('الفواتير', 'Invoices'), subtitle: '${list.length}'),
          if (list.isEmpty) EmptyState(t('لا توجد فواتير', 'No invoices'), icon: Icons.receipt_long_outlined),
          ...list.map((v) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              child: Row(children: [
                Icon(Icons.receipt_long, color: p.accent),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${v.id} — ${fmtMad(v.total)}', style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                  Text('${v.clientName} · ${fmtDate(v.issuedAt)}${v.orderId == null ? '' : ' · ${v.orderId}'}', style: ts(p, size: 11, color: p.muted)),
                ])),
                Pill(v.status == 'paid' ? t('مدفوعة', 'Paid') : t('غير مدفوعة', 'Unpaid'), color: v.status == 'paid' ? p.green : p.amber),
                const SizedBox(width: 8),
                IconBtn(Icons.picture_as_pdf, tooltip: 'PDF', onTap: () async {
                  try {
                    final s = await repo.getSettings();
                    await shareInvoicePdf(v, s);
                  } catch (e) {
                    if (context.mounted) toast(context, errMsg(e), error: true);
                  }
                }),
              ]),
            );
          }),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------
// الملف الشخصي
// ------------------------------------------------------------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _name = TextEditingController(text: appState.profile?.fullName ?? '');
  late final _phone = TextEditingController(text: appState.profile?.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pr = appState.profile;
    if (pr == null) return const SizedBox();
    final p = P(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(t('ملفي الشخصي', 'My profile')),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(pr.display, size: 52),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pr.display, style: ts(p, size: 16, w: FontWeight.w800, color: p.fg)),
                Text(pr.email, style: ts(p, size: 12, color: p.muted)),
              ])),
              Pill(roleLabel(pr.role), color: p.accent),
            ]),
            const SizedBox(height: 16),
            MakField(controller: _name, label: t('الاسم الكامل', 'Full name')),
            const SizedBox(height: 10),
            MakField(controller: _phone, label: t('الهاتف', 'Phone'), keyboard: TextInputType.phone, dir: TextDirection.ltr),
            const SizedBox(height: 16),
            MakButton(t('حفظ', 'Save'), icon: Icons.save, onPressed: () async {
              if (_name.text.trim().isEmpty) {
                toast(context, t('الاسم مطلوب', 'Name is required'), error: true);
                return;
              }
              await repo.updateMyProfile(fullName: _name.text.trim(), phone: _phone.text.trim().isEmpty ? null : _phone.text.trim());
              final np = await repo.currentProfile();
              if (np != null) appState.refreshProfile(np);
              if (context.mounted) toast(context, t('تم الحفظ', 'Saved'));
            }),
          ]),
        ),
      ),
    ]);
  }
}
