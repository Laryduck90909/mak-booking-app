import 'package:mak_booking/core/config/app_config.dart';
import 'package:mak_booking/data/remote/supabase_service.dart';
import 'package:mak_booking/models/app_user.dart';

class AuthRepository {
  static const demoUser = AppUser(
    id: '00000000-0000-4000-8000-000000000001',
    email: 'demo@mak.design',
    fullName: 'M.A.K Demo',
    role: UserRole.admin,
  );

  Future<AppUser?> currentUser() async {
    if (!AppConfig.useBackend) return null;
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) return null;
    return profile(session.user.id);
  }

  Future<AppUser> profile(String id) async {
    final authUser = SupabaseService.client.auth.currentUser;
    final row = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', id)
        .single();
    return AppUser.fromMap(row, authUser?.email ?? '');
  }

  Future<AppUser> signIn(String email, String password) async {
    if (!AppConfig.useBackend) return demoUser;
    final response = await SupabaseService.client.auth
        .signInWithPassword(email: email.trim(), password: password);
    final user = response.user;
    if (user == null) throw StateError('Sign-in returned no user');
    return profile(user.id);
  }

  Future<AppUser> signUp(String name, String email, String password) async {
    if (!AppConfig.useBackend) return demoUser;
    final response = await SupabaseService.client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': name.trim()},
    );
    final user = response.user;
    if (user == null) throw StateError('Sign-up returned no user');
    return profile(user.id);
  }

  Future<void> signOut() async {
    if (AppConfig.useBackend) await SupabaseService.client.auth.signOut();
  }
}
