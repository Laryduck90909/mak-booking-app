import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/core/utils/formatters.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/shared/widgets/common.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(requestsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin'))),
      body: SafeArea(
        child: requests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorState(
              error: error, onRetry: () => ref.invalidate(requestsProvider)),
          data: (items) {
            final active = items
                .where(
                    (item) => !['completed', 'cancelled'].contains(item.status))
                .length;
            final completed =
                items.where((item) => item.status == 'completed').length;
            final value =
                items.fold<double>(0, (sum, item) => sum + item.total);
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                PageIntro(
                    title: context.tr('dashboard'),
                    description: context.tr('appName')),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width > 900 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio:
                      MediaQuery.sizeOf(context).width > 900 ? 1.35 : 1.15,
                  children: [
                    _Metric(
                        icon: Icons.folder_copy_outlined,
                        label: context.tr('totalRequests'),
                        value: '${items.length}'),
                    _Metric(
                        icon: Icons.bolt_rounded,
                        label: context.tr('activeRequests'),
                        value: '$active'),
                    _Metric(
                        icon: Icons.check_circle_outline_rounded,
                        label: context.tr('completed'),
                        value: '$completed'),
                    _Metric(
                        icon: Icons.payments_outlined,
                        label: context.tr('revenue'),
                        value: money(value, context.localeCode)),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                        child: Text(context.tr('latestRequests'),
                            style: Theme.of(context).textTheme.titleLarge)),
                    TextButton(
                        onPressed: () => context.push('/requests'),
                        child: Text(context.tr('viewRequests'))),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  EmptyState(
                      icon: Icons.inbox_outlined,
                      title: context.tr('emptyRequests'),
                      description: context.tr('emptyRequestsDesc'))
                else
                  ...items.take(8).map((request) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 8),
                            onTap: () =>
                                context.push('/requests/${request.id}'),
                            leading: const CircleAvatar(
                                backgroundColor: MakColors.tealLight,
                                child: Icon(Icons.design_services_outlined)),
                            title: Text(request.displayNumber),
                            subtitle: Text(context.tr(request.status)),
                            trailing: Text(
                                money(request.total, context.localeCode),
                                style: const TextStyle(color: MakColors.peach)),
                          ),
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: MakColors.peach),
              const Spacer(),
              FittedBox(
                  child: Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900))),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 2,
                  style: const TextStyle(color: MakColors.muted, fontSize: 12)),
            ],
          ),
        ),
      );
}
