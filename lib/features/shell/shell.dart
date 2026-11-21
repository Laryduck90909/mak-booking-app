import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../admin/admin_pages.dart';
import '../auth/session.dart';
import '../client/client_pages.dart';
import '../common/lists.dart';
import '../orders/contract_view.dart';
import '../orders/order_detail.dart';
import '../staff/staff_pages.dart';
import '../wizard/wizard.dart';

class _Nav {
  final String id;
  final IconData icon;
  final String label;
  const _Nav(this.id, this.icon, this.label);
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  late String _page = _home;
  int _unread = 0;
  List<AppNotification> _notifs = [];
  StreamSubscription<List<AppNotification>>? _sub;

  String get _role => appState.role;
  String get _home => _role == 'client' ? 'home' : 'overview';

  @override
  void initState() {
    super.initState();
    try {
      _sub = repo.watchNotifications().listen((l) {
        if (!mounted) return;
        setState(() {
          _notifs = l;
          _unread = l.where((n) => n.readAt == null).length;
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<_Nav> _items() {
    switch (_role) {
      case 'admin':
        return [
          _Nav('overview', Icons.dashboard_outlined, t('نظرة عامة', 'Overview')),
          _Nav('orders', Icons.inbox_outlined, t('كل الطلبات', 'All orders')),
          _Nav('approvals', Icons.fact_check_outlined, t('الاعتمادات', 'Approvals')),
          _Nav('chats', Icons.chat_bubble_outline, t('المحادثات', 'Chats')),
          _Nav('contracts', Icons.description_outlined, t('العقود', 'Contracts')),
          _Nav('payments', Icons.payments_outlined, t('الدفعات', 'Payments')),
          _Nav('invoices', Icons.receipt_long_outlined, t('الفواتير', 'Invoices')),
          _Nav('users', Icons.people_outline, t('المستخدمون', 'Users')),
          _Nav('scores', Icons.emoji_events_outlined, t('التقييمات', 'Scores')),
          _Nav('accounting', Icons.account_balance_outlined, t('المحاسبة', 'Accounting')),
          _Nav('templates', Icons.article_outlined, t('قوالب العقود', 'Templates')),
          _Nav('archive', Icons.archive_outlined, t('الأرشيف', 'Archive')),
          _Nav('settings', Icons.settings_outlined, t('الإعدادات', 'Settings')),
          _Nav('profile', Icons.person_outline, t('ملفي', 'Profile')),
        ];
      case 'staff':
        return [
          _Nav('overview', Icons.dashboard_outlined, t('نظرة عامة', 'Overview')),
          _Nav('orders', Icons.inbox_outlined, t('طلبات العملاء', 'Client requests')),
          _Nav('chats', Icons.chat_bubble_outline, t('المحادثات', 'Chats')),
          _Nav('contracts', Icons.description_outlined, t('العقود', 'Contracts')),
          _Nav('payments', Icons.payments_outlined, t('الدفعات', 'Payments')),
          if (appState.canEditPrices) _Nav('prices', Icons.sell_outlined, t('الأسعار', 'Prices')),
          _Nav('invoices', Icons.receipt_long_outlined, t('الفواتير', 'Invoices')),
          _Nav('profile', Icons.person_outline, t('ملفي', 'Profile')),
        ];
      default:
        return [
          _Nav('home', Icons.home_outlined, t('الرئيسية', 'Home')),
          _Nav('orders', Icons.work_outline, t('طلباتي', 'My orders')),
          _Nav('chats', Icons.chat_bubble_outline, t('المحادثات', 'Chats')),
          _Nav('contracts', Icons.description_outlined, t('عقودي', 'Contracts')),
          _Nav('invoices', Icons.receipt_long_outlined, t('فواتيري', 'Invoices')),
          _Nav('profile', Icons.person_outline, t('ملفي', 'Profile')),
        ];
    }
  }

  Widget _body() {
    void go(String id) => setState(() => _page = id);
    switch (_page) {
      case 'home': return ClientHome(go: go);
      case 'overview': return _role == 'admin' ? AdminOverview(go: go) : StaffOverview(go: go);
      case 'orders': return OrdersListPage(mine: _role == 'client', scope: _role == 'admin' ? 'active' : 'all', title: _role == 'client' ? t('طلباتي', 'My orders') : t('طلبات العملاء', 'Client requests'));
      case 'archive': return OrdersListPage(scope: 'closed', title: t('الأرشيف', 'Archive'));
      case 'approvals': return const ApprovalsPage();
      case 'chats': return const ChatsPage();
      case 'contracts': return const ContractsListPage();
      case 'payments': return const PaymentsPage();
      case 'invoices': return const InvoicesListPage();
      case 'users': return const UsersPage();
      case 'scores': return const ScoresPage();
      case 'accounting': return const AccountingPage();
      case 'templates': return const TemplatesPage();
      case 'settings': return const SettingsPage();
      case 'prices': return const PricesPage();
      case 'profile': return const ProfilePage();
      default: return const SizedBox();
    }
  }

  Future<void> _openLink(String link) async {
    // الروابط: /orders/ID أو /contracts/ID
    final parts = link.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return;
    try {
      if (parts[0] == 'orders') {
        await openOrder(context, parts[1]);
      } else if (parts[0] == 'contracts') {
        final l = await repo.listContracts();
        for (final c in l) {
          if (c.id == parts[1]) {
            if (mounted) await showContractDialog(context, c);
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _showNotifs() async {
    repo.markNotificationsRead();
    await showPanelDialog<void>(
      context,
      title: t('الإشعارات', 'Notifications'),
      width: 460,
      builder: (ctx) {
        final p = P(ctx);
        if (_notifs.isEmpty) return EmptyState(t('لا إشعارات', 'No notifications'), icon: Icons.notifications_none);
        return Column(children: _notifs.take(30).map((n) {
          return InkWell(
            onTap: () {
              Navigator.pop(ctx);
              if (n.link.isNotEmpty) _openLink(n.link);
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: n.readAt == null ? p.accent.fade(0.1) : p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
                if (n.body.isNotEmpty) Text(n.body, style: ts(p, size: 12, color: p.muted)),
                Text(relTime(n.createdAt), style: ts(p, size: 10, color: p.subtle)),
              ]),
            ),
          );
        }).toList());
      },
    );
  }

  Widget _topBar(Palette p, bool wide, List<_Nav> nav) {
    final title = nav.firstWhere((n) => n.id == _page, orElse: () => nav.first).label;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: p.sidebar.fade(0.92), border: Border(bottom: BorderSide(color: p.borderSoft))),
      child: Row(children: [
        if (!wide) IconBtn(Icons.menu, onTap: () => _scaffold.currentState?.openDrawer()),
        if (!wide) const SizedBox(width: 10),
        Expanded(child: Text(title, style: ts(p, size: 16, w: FontWeight.w800, color: p.fg, display: true), overflow: TextOverflow.ellipsis)),
        if (appState.realRole == 'admin' && wide) ...[_viewSwitch(p), const SizedBox(width: 10)],
        IconBtn(Icons.translate, tooltip: 'AR / EN', onTap: () => appState.setLang(appState.lang == 'ar' ? 'en' : 'ar')),
        const SizedBox(width: 6),
        IconBtn(appState.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, onTap: appState.toggleTheme),
        const SizedBox(width: 6),
        IconBtn(Icons.notifications_none, badge: _unread, onTap: _showNotifs),
        if (wide) ...[
          const SizedBox(width: 10),
          Avatar(appState.profile?.display ?? '?', size: 32),
        ],
      ]),
    );
  }

  Widget _viewSwitch(Palette p) {
    Widget chip(String id, String label) => SelectChip(label, selected: appState.viewAs == id, onTap: () {
          appState.setViewAs(id);
        });
    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip('', t('المدير', 'Admin')),
      const SizedBox(width: 6),
      chip('staff', t('كموظف', 'As staff')),
      const SizedBox(width: 6),
      chip('client', t('كعميل', 'As client')),
    ]);
  }

  Widget _sidebar(Palette p, List<_Nav> nav, {bool inDrawer = false}) {
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: p.sidebar,
        border: BorderDirectional(end: BorderSide(color: p.borderSoft)),
      ),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const MakLogo(size: 38),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('M.A.K', style: ts(p, size: 17, w: FontWeight.w900, color: p.fg, display: true)),
                Text(roleLabel(_role) + (appState.viewAs.isNotEmpty ? ' (${t('عرض', 'view')})' : ''), style: ts(p, size: 11, color: p.accent, w: FontWeight.w700)),
              ])),
            ]),
          ),
          if (appState.realRole == 'admin' && inDrawer)
            Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: Wrap(spacing: 6, runSpacing: 6, children: [
              SelectChip(t('المدير', 'Admin'), selected: appState.viewAs.isEmpty, onTap: () => appState.setViewAs('')),
              SelectChip(t('كموظف', 'As staff'), selected: appState.viewAs == 'staff', onTap: () => appState.setViewAs('staff')),
              SelectChip(t('كعميل', 'As client'), selected: appState.viewAs == 'client', onTap: () => appState.setViewAs('client')),
            ])),
          if (_role == 'client')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: MakButton(t('طلب جديد', 'New request'), icon: Icons.add, onPressed: () {
                if (inDrawer) Navigator.pop(context);
                startNewRequest(context);
              }),
            ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: nav.map((n) {
              final sel = n.id == _page;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (inDrawer) Navigator.pop(context);
                  setState(() => _page = n.id);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: sel ? LinearGradient(colors: [p.accent.fade(0.20), p.accent.fade(0.04)], begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd) : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? p.accent.fade(0.30) : Colors.transparent),
                  ),
                  child: Row(children: [
                    Icon(n.icon, size: 19, color: sel ? p.accent : p.muted),
                    const SizedBox(width: 12),
                    Expanded(child: Text(n.label, style: ts(p, size: 13, w: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? p.accent : p.text))),
                  ]),
                ),
              );
            }).toList()),
          ),
          Divider(height: 1, color: p.border),
          InkWell(
            onTap: () async {
              if (await confirmDialog(context, t('تسجيل الخروج؟', 'Sign out?'))) await logout();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Avatar(appState.profile?.display ?? '?', size: 30),
                const SizedBox(width: 10),
                Expanded(child: Text(appState.profile?.display ?? '', style: ts(p, size: 12.5, color: p.fg), overflow: TextOverflow.ellipsis)),
                Icon(Icons.logout, size: 18, color: p.red),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final wide = isWide(context);
    final nav = _items();
    if (!nav.any((n) => n.id == _page)) _page = nav.first.id;
    final content = GlowBackground(child: Column(children: [
      _topBar(p, wide, nav),
      if (appState.viewAs.isNotEmpty)
        Container(
          width: double.infinity,
          color: p.amber.fade(0.18),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Text(
            t('وضع العرض: أنت تشاهد واجهة ${roleLabel(appState.viewAs)}. الصلاحيات الفعلية لحسابك كمدير تبقى كما هي.', 'View mode: you are seeing the ${roleLabel(appState.viewAs)} interface. Your real admin permissions are unchanged.'),
            style: ts(p, size: 11.5, color: p.amber, w: FontWeight.w700),
          ),
        ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(anim), child: child),
          ),
          child: SingleChildScrollView(
            key: ValueKey('page-$_page-$_role'),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: Align(alignment: Alignment.topCenter, child: _body())),
            ),
          ),
        ),
      ),
    ]));
    return Scaffold(
      key: _scaffold,
      backgroundColor: p.bg,
      drawer: wide ? null : Drawer(backgroundColor: p.sidebar, child: _sidebar(p, nav, inDrawer: true)),
      floatingActionButton: (_role == 'client' && !wide)
          ? FloatingActionButton.extended(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              onPressed: () => startNewRequest(context),
              icon: const Icon(Icons.add),
              label: Text(t('طلب جديد', 'New request'), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: wide ? Row(children: [_sidebar(p, nav), Expanded(child: content)]) : content,
    );
  }
}
