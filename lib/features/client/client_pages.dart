import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../orders/contract_view.dart';
import '../orders/order_detail.dart';
import '../wizard/wizard.dart';

class _ClientData {
  final List<Order> orders;
  final List<Quote> quotes;
  final List<Contract> contracts;
  _ClientData(this.orders, this.quotes, this.contracts);
}

/// الرئيسية: ما يحتاج إجراءً منك + آخر طلباتك.
class ClientHome extends StatelessWidget {
  final void Function(String page) go;
  const ClientHome({super.key, required this.go});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AsyncData<_ClientData>(
      load: () async => _ClientData(await repo.listMyOrders(), await repo.listQuotes(), await repo.listContracts()),
      builder: (context, d) {
        final active = d.orders.where((o) => !o.isClosed).toList();
        final quotesToAnswer = d.quotes.where((q) => q.status == 'sent' && !q.expired).toList();
        final toSign = d.contracts.where((c) => c.status == 'awaiting_client').toList();
        final previews = d.orders.where((o) => o.status == 'preview_sent').toList();
        final todo = quotesToAnswer.length + toSign.length + previews.length;
        final byId = {for (final o in d.orders) o.id: o};
        final recent = [...d.orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HeroCard(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 14, spacing: 14,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('مرحباً بعودتك', 'Welcome back'), style: ts(p, size: 12, w: FontWeight.w700, color: p.gold)),
                    const SizedBox(height: 4),
                    GradientText(appState.profile?.display ?? '', style: ts(p, size: 28, w: FontWeight.w800, display: true)),
                    const SizedBox(height: 6),
                    Text(t('كل طلباتك وعقودك ومحادثاتك في مكان واحد', 'All your orders, contracts and chats in one place'), style: ts(p, size: 13, color: p.muted)),
                  ]),
                ),
                MakButton(t('طلب جديد', 'New request'), icon: Icons.add, onPressed: () => startNewRequest(context)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdaptiveGrid(minWidth: 200, children: [
            KpiCard(label: t('طلبات نشطة', 'Active orders'), value: '${active.length}', icon: Icons.work_outline),
            KpiCard(label: t('بانتظار إجرائك', 'Needs your action'), value: '$todo', icon: Icons.notifications_active_outlined, color: todo > 0 ? p.amber : p.green),
            KpiCard(label: t('إجمالي الطلبات', 'Total orders'), value: '${d.orders.length}', icon: Icons.history),
          ]),
          const SizedBox(height: 16),
          if (todo > 0)
            Panel(
              title: t('يحتاج إجراءً منك', 'Needs your action'),
              accent: p.amber,
              child: Column(children: [
                ...quotesToAnswer.map((q) => _todo(context, p, Icons.request_quote, '${t('عرض سعر', 'Quote')} ${fmtMad(q.finalTotal)}', byId[q.orderId]?.title ?? q.orderId, () => openOrder(context, q.orderId, tab: 1))),
                ...toSign.map((c) => _todo(context, p, Icons.draw, t('عقد بانتظار توقيعك', 'Contract awaiting your signature'), byId[c.orderId]?.title ?? c.orderId, () => showContractDialog(context, c))),
                ...previews.map((o) => _todo(context, p, Icons.visibility, t('معاينة جاهزة', 'Preview ready'), o.title, () => openOrder(context, o.id, tab: 1))),
              ]),
            ),
          if (todo > 0) const SizedBox(height: 16),
          Panel(
            title: t('آخر طلباتك', 'Recent orders'),
            trailing: TextButton(onPressed: () => go('orders'), child: Text(t('عرض الكل', 'View all'), style: TextStyle(color: p.accent))),
            child: recent.isEmpty
                ? Column(children: [
                    EmptyState(t('لم تطلب شيئاً بعد', 'No orders yet'), icon: Icons.add_circle_outline),
                    MakButton(t('ابدأ طلبك الأول', 'Start your first request'), icon: Icons.add, onPressed: () => startNewRequest(context)),
                  ])
                : Column(children: recent.take(5).map((o) => OrderTile(order: o, showClient: false, onTap: () => openOrder(context, o.id))).toList()),
          ),
        ]);
      },
    );
  }

  Widget _todo(BuildContext context, Palette p, IconData icon, String title, String sub, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: p.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
            Text(sub, style: ts(p, size: 11.5, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Icon(isAr ? Icons.chevron_left : Icons.chevron_right, color: p.muted),
        ]),
      ),
    );
  }
}
