import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../orders/order_detail.dart';
import '../orders/order_files.dart';

class _StaffData {
  final List<Order> orders;
  final List<Payment> payments;
  final List<Quote> quotes;
  _StaffData(this.orders, this.payments, this.quotes);
}

/// نظرة عامة للموظف: ما ينتظره الآن.
class StaffOverview extends StatelessWidget {
  final void Function(String page) go;
  const StaffOverview({super.key, required this.go});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<_StaffData>(
      load: () async => _StaffData(await repo.listOrders(), await repo.listPayments(), await repo.listQuotes()),
      builder: (context, d) {
        final fresh = d.orders.where((o) => o.status == 'new').toList();
        final toContract = d.orders.where((o) => o.status == 'accepted').toList();
        final working = d.orders.where((o) => o.status == 'in_progress' || o.status == 'preview_sent').toList();
        final pendingPay = d.payments.where((x) => !x.confirmed).toList();
        final overdue = fresh.where((o) => workingHoursBetween(o.createdAt, DateTime.now()) > AppConfig.slaWorkingHours).toList();
        final mine = d.quotes.where((q) => q.status == 'pending_approval' && q.proposedBy == repo.userId).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader('${t('مرحباً', 'Welcome')} ${appState.profile?.display ?? ''}', subtitle: t('لوحة الموظف — كل طلبات العملاء', 'Staff board — all client requests')),
          AdaptiveGrid(minWidth: 190, children: [
            KpiCard(label: t('طلبات جديدة', 'New requests'), value: '${fresh.length}', icon: Icons.fiber_new, color: p.blue),
            KpiCard(label: t('متأخرة عن SLA', 'Past SLA'), value: '${overdue.length}', sub: t('بلا عرض > ${AppConfig.slaWorkingHours} ساعات عمل', 'No quote > ${AppConfig.slaWorkingHours} work hrs'), icon: Icons.timer_outlined, color: overdue.isEmpty ? p.green : p.red),
            KpiCard(label: t('بانتظار عقد', 'Need contract'), value: '${toContract.length}', icon: Icons.description_outlined, color: p.violet),
            KpiCard(label: t('قيد التنفيذ', 'In progress'), value: '${working.length}', icon: Icons.build_outlined, color: p.teal),
            KpiCard(label: t('دفعات للتأكيد', 'Payments to confirm'), value: '${pendingPay.length}', icon: Icons.payments_outlined, color: p.amber),
            KpiCard(label: t('مقترحاتي عند المدير', 'My proposals pending'), value: '$mine', icon: Icons.hourglass_top, color: p.gold),
          ]),
          const SizedBox(height: 16),
          Panel(
            title: t('طلبات جديدة تنتظر التسعير', 'New requests awaiting a quote'),
            trailing: TextButton(onPressed: () => go('orders'), child: Text(t('كل الطلبات', 'All orders'), style: TextStyle(color: p.accent))),
            child: fresh.isEmpty
                ? EmptyState(t('لا توجد طلبات جديدة', 'No new requests'))
                : Column(children: fresh.take(6).map((o) => OrderTile(order: o, onTap: () => openOrder(context, o.id))).toList()),
          ),
          if (toContract.isNotEmpty) ...[
            const SizedBox(height: 16),
            Panel(
              title: t('قُبل عرضها — جهّز العقد', 'Quote accepted — prepare contract'),
              child: Column(children: toContract.take(6).map((o) => OrderTile(order: o, onTap: () => openOrder(context, o.id, tab: 1))).toList()),
            ),
          ],
        ]);
      },
    );
  }
}

/// الدفعات: وصولات بانتظار تأكيد الفريق.
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<({List<Payment> pay, List<Order> orders})>(
      load: () async => (pay: await repo.listPayments(), orders: await repo.listOrders()),
      builder: (context, d) {
        final byId = {for (final o in d.orders) o.id: o};
        final list = [...d.pay]..sort((a, b) {
            if (a.confirmed != b.confirmed) return a.confirmed ? 1 : -1;
            return b.createdAt.compareTo(a.createdAt);
          });
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('الدفعات', 'Payments'), subtitle: '${list.where((x) => !x.confirmed).length} ${t('بانتظار التأكيد', 'to confirm')}'),
          if (list.isEmpty) EmptyState(t('لا توجد دفعات', 'No payments'), icon: Icons.payments_outlined),
          ...list.map((x) {
            final o = byId[x.orderId];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              child: Row(children: [
                Expanded(child: InkWell(
                  onTap: () => openOrder(context, x.orderId, tab: 1),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${x.kindText} — ${fmtMad(x.amount)}', style: ts(p, size: 13.5, w: FontWeight.w800, color: p.fg)),
                    Text('${o?.clientName ?? ''} · ${x.orderId} · ${fmtDateTime(x.createdAt)}', style: ts(p, size: 11, color: p.muted)),
                  ]),
                )),
                if (x.receiptPath != null) IconBtn(Icons.receipt_long, tooltip: t('الوصل', 'Receipt'), onTap: () => openStoredFile(context, 'receipts', x.receiptPath!)),
                const SizedBox(width: 8),
                if (x.confirmed)
                  Pill(t('مؤكَّد', 'Confirmed'), color: p.green)
                else
                  MakButton(t('تأكيد', 'Confirm'), dense: true, onPressed: () async {
                    if (await confirmDialog(context, t('تأكيد استلام ${fmtMad(x.amount)}؟ لا يمكن التراجع.', 'Confirm receipt of ${fmtMad(x.amount)}? Cannot be undone.'))) {
                      await repo.confirmPayment(x.id);
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

/// الأسعار: تعديل فئات الأسعار (للمدير أو الموظف الذي يملك الصلاحية).
class PricesPage extends StatelessWidget {
  const PricesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    if (!appState.canEditPrices) {
      return EmptyState(t('ليست لديك صلاحية تعديل الأسعار', 'You cannot edit prices'), icon: Icons.lock_outline);
    }
    return AsyncData<List<PriceTier>>(
      load: () => repo.getTiers(),
      builder: (context, tiers) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(t('فئات الأسعار', 'Price tiers'), subtitle: t('تُطبَّق على الطلبات الجديدة فقط. الخدمات غير المسعّرة تبقى يدوية.', 'Applies to new requests only. Unpriced services stay manual.')),
          AdaptiveGrid(minWidth: 220, children: tiers.map((x) => _TierCard(tier: x)).toList()),
          const SizedBox(height: 12),
          Text(t('ملاحظة: تغيير فئة سعر لا يغيّر الطلبات القائمة ولا عروضها.', 'Note: changing a tier does not change existing orders or quotes.'), style: ts(p, size: 11.5, color: p.muted)),
        ]);
      },
    );
  }
}

class _TierCard extends StatefulWidget {
  final PriceTier tier;
  const _TierCard({required this.tier});
  @override
  State<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends State<_TierCard> {
  late final _ctl = TextEditingController(text: '${widget.tier.price}');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Panel(
      title: widget.tier.label,
      kicker: widget.tier.code.toUpperCase(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MakField(controller: _ctl, label: t('السعر (د.م.)', 'Price (MAD)'), keyboard: TextInputType.number),
        const SizedBox(height: 10),
        MakButton(t('حفظ', 'Save'), dense: true, onPressed: () async {
          final v = int.tryParse(_ctl.text.trim()) ?? -1;
          if (v < 0) {
            toast(context, t('سعر غير صالح', 'Invalid price'), error: true);
            return;
          }
          await repo.saveTier(widget.tier.code, v);
          if (context.mounted) toast(context, t('تم الحفظ', 'Saved'));
        }),
        const SizedBox(height: 4),
        Text('${t('الحالي', 'Current')}: ${fmtMad(widget.tier.price)}', style: ts(p, size: 11, color: p.muted)),
      ]),
    );
  }
}
