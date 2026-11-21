import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/features/admin/admin_dashboard_screen.dart';
import 'package:mak_booking/features/auth/auth_screen.dart';
import 'package:mak_booking/features/chat/chat_screen.dart';
import 'package:mak_booking/features/coming_soon/coming_soon_screen.dart';
import 'package:mak_booking/features/contracts/contract_screen.dart';
import 'package:mak_booking/features/home/home_screen.dart';
import 'package:mak_booking/features/requests/request_details_screen.dart';
import 'package:mak_booking/features/requests/request_wizard_screen.dart';
import 'package:mak_booking/features/requests/requests_screen.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/shared/widgets/brand_logo.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      if (auth.isLoading) return location == '/splash' ? null : '/splash';
      if (location == '/splash') {
        return auth.hasValue && auth.value != null ? '/home' : '/login';
      }
      final loggedIn = auth.valueOrNull != null;
      final isAuthPage = location == '/login' || location == '/signup';
      if (!loggedIn && !isAuthPage) return '/login';
      if (loggedIn && isAuthPage) return '/home';
      if (location == '/admin' && auth.valueOrNull?.isAdmin != true) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
      GoRoute(
          path: '/signup', builder: (_, __) => const AuthScreen(signUp: true)),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/requests', builder: (_, __) => const RequestsScreen()),
      GoRoute(
          path: '/requests/new',
          builder: (_, __) => const RequestWizardScreen()),
      GoRoute(
        path: '/requests/:id',
        builder: (_, state) =>
            RequestDetailsScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/requests/:id/chat',
        builder: (_, state) =>
            ChatScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/requests/:id/contract',
        builder: (_, state) =>
            ContractScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(
          path: '/web',
          builder: (_, __) => const ComingSoonScreen(service: 'web')),
      GoRoute(
          path: '/writing',
          builder: (_, __) => const ComingSoonScreen(service: 'writing')),
    ],
    errorBuilder: (context, _) =>
        Scaffold(body: Center(child: Text(context.tr('genericError')))),
  );
});

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: BrandLogo(size: 72)),
      );
}
