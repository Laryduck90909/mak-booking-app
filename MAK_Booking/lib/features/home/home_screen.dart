import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/providers/connectivity_provider.dart';
import 'package:mak_booking/shared/widgets/brand_logo.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final pending = ref.watch(pendingSyncProvider).valueOrNull ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const BrandLogo(size: 40),
        actions: [
          IconButton(
            tooltip: context.tr('language'),
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            icon: const Icon(Icons.language_rounded),
          ),
          IconButton(
            tooltip: context.tr('logout'),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!online || pending > 0) ...[
                      Material(
                        color: MakColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          leading: Icon(online
                              ? Icons.sync_rounded
                              : Icons.wifi_off_rounded),
                          title: Text(
                              context.tr(online ? 'pendingSync' : 'offline')),
                          subtitle: pending > 0 ? Text('$pending') : null,
                          trailing: pending > 0 && online
                              ? TextButton(
                                  onPressed: () async {
                                    await ref
                                        .read(requestRepositoryProvider)
                                        .syncPending();
                                    ref.invalidate(pendingSyncProvider);
                                    ref.invalidate(requestsProvider);
                                  },
                                  child: Text(context.tr('syncNow')),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      '${context.tr('welcome')}، ${user?.fullName.isNotEmpty == true ? user!.fullName : user?.email ?? ''}',
                      style: const TextStyle(color: MakColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('tagline'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.push('/requests/new'),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(context.tr('startRequest')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/requests'),
                          icon: const Icon(Icons.folder_outlined),
                          label: Text(context.tr('viewRequests')),
                        ),
                        if (user?.isAdmin == true)
                          OutlinedButton.icon(
                            onPressed: () => context.push('/admin'),
                            icon: const Icon(Icons.insights_rounded),
                            label: Text(context.tr('admin')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 430,
                  mainAxisExtent: 280,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                delegate: SliverChildListDelegate([
                  _ServiceCard(
                    service: 'design',
                    logo: 'assets/logos/mak_design.png',
                    onTap: () => context.push('/requests/new'),
                  ),
                  _ServiceCard(
                    service: 'web',
                    logo: 'assets/logos/mak_webs.png',
                    onTap: () => context.push('/web'),
                  ),
                  _ServiceCard(
                    service: 'writing',
                    logo: 'assets/logos/mak_writers.png',
                    onTap: () => context.push('/writing'),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard(
      {required this.service, required this.logo, required this.onTap});
  final String service;
  final String logo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDesign = service == 'design';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  logo,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                ),
              ),
              const Spacer(),
              Text(
                context.tr(service),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('${service}Desc'),
                style: const TextStyle(color: MakColors.muted, height: 1.6),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    context.tr(isDesign ? 'startRequest' : 'comingSoon'),
                    style: const TextStyle(
                        color: MakColors.peach, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded,
                      color: MakColors.peach),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
