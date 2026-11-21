import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mak_booking/core/config/app_config.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/shared/widgets/brand_logo.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.signUp = false});
  final bool signUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit({bool demo = false}) async {
    if (!demo && !_form.currentState!.validate()) return;
    final email = demo ? 'demo@mak.design' : _email.text;
    final password = demo ? 'demo-password' : _password.text;
    if (widget.signUp && !demo) {
      await ref
          .read(authControllerProvider.notifier)
          .signUp(_name.text, email, password);
    } else {
      await ref.read(authControllerProvider.notifier).signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
    });
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(size: 72)),
                    const SizedBox(height: 32),
                    Text(
                      widget.signUp
                          ? context.tr('signup')
                          : context.tr('login'),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(context.tr('tagline'),
                        style: const TextStyle(color: MakColors.muted)),
                    const SizedBox(height: 32),
                    if (widget.signUp) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration:
                            InputDecoration(labelText: context.tr('fullName')),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                                ? context.tr('requiredField')
                                : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration:
                          InputDecoration(labelText: context.tr('email')),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return context.tr('requiredField');
                        }
                        return value.contains('@') && value.contains('.')
                            ? null
                            : context.tr('invalidEmail');
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: widget.signUp
                          ? TextInputAction.next
                          : TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: context.tr('password'),
                        suffixIcon: IconButton(
                          tooltip: context.tr('password'),
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 6
                          ? context.tr('passwordShort')
                          : null,
                      onFieldSubmitted: widget.signUp ? null : (_) => _submit(),
                    ),
                    if (widget.signUp) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmation,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                            labelText: context.tr('confirmPassword')),
                        validator: (value) => value != _password.text
                            ? context.tr('passwordMismatch')
                            : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: loading ? null : _submit,
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              context.tr(widget.signUp ? 'signup' : 'login')),
                    ),
                    if (!AppConfig.useBackend) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: loading ? null : () => _submit(demo: true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(context.tr('demoLogin')),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () =>
                              context.go(widget.signUp ? '/login' : '/signup'),
                      child: Text(context
                          .tr(widget.signUp ? 'haveAccount' : 'noAccount')),
                    ),
                    IconButton(
                      tooltip: context.tr('language'),
                      onPressed: () =>
                          ref.read(localeProvider.notifier).toggle(),
                      icon: const Icon(Icons.language_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
