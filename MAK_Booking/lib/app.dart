import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/router/app_router.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/providers/connectivity_provider.dart';

class MakApp extends ConsumerStatefulWidget {
  const MakApp({super.key});
  @override
  ConsumerState<MakApp> createState() => _MakAppState();
}

class _MakAppState extends ConsumerState<MakApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(requestRepositoryProvider).syncPending());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(onlineProvider, (previous, next) {
      if (next.valueOrNull == true) {
        ref.read(requestRepositoryProvider).syncPending().then((count) {
          ref.invalidate(pendingSyncProvider);
          if (count > 0) ref.invalidate(requestsProvider);
        });
      }
    });
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'M.A.K Booking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
