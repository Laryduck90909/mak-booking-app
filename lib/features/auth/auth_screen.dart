import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../data/repo.dart';
import 'session.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;
  bool _confirmPending = false;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return t('أدخل بريداً إلكترونياً صحيحاً', 'Enter a valid email');
    if (_pass.text.length < 8) return t('كلمة المرور 8 أحرف على الأقل', 'Password must be at least 8 characters');
    if (_register) {
      if (_name.text.trim().length < 2) return t('أدخل اسمك الكامل', 'Enter your full name');
      if (_pass.text != _pass2.text) return t('كلمتا المرور غير متطابقتين', 'Passwords do not match');
    }
    return null;
  }

  Future<void> _submit() async {
    final v = _validate();
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() => _error = null);
    try {
      if (_register) {
        final r = await repo.signUp(_email.text.trim(), _pass.text, _name.text.trim());
        if (r == SignUpResult.needsEmailConfirm) {
          setState(() => _confirmPending = true);
          return;
        }
        await completeLogin();
      } else {
        await repo.signIn(_email.text.trim(), _pass.text);
        await completeLogin();
      }
    } catch (e) {
      setState(() => _error = errMsg(e));
    }
  }

  Future<void> _demo(String role) async {
    await repo.demoSignIn(role);
    await completeLogin();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final demo = AppConfig.demoOnly;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const MakLogo(size: 84),
                  const SizedBox(height: 14),
                  Text('M.A.K Booking', style: ts(p, size: 26, w: FontWeight.w900, color: p.fg)),
                  const SizedBox(height: 4),
                  Text(t('احجز خدمات التصميم والمواقع والكتابة', 'Book design, web and writing services'),
                      style: ts(p, size: 13, color: p.muted), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_confirmPending) _confirmCard(p) else if (demo) _demoCard(p) else _formCard(p),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 8, left: 12, right: 12,
            child: Row(children: [
              const Spacer(),
              IconBtn(Icons.language, tooltip: t('اللغة', 'Language'), onTap: () => appState.setLang(isAr ? 'en' : 'ar')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _confirmCard(Palette p) {
    return Panel(
      child: Column(children: [
        Icon(Icons.mark_email_read_outlined, size: 44, color: p.accent),
        const SizedBox(height: 10),
        Text(t('تحقق من بريدك', 'Check your email'), style: ts(p, size: 18, w: FontWeight.w800, color: p.fg)),
        const SizedBox(height: 6),
        Text(
          t('أرسلنا رسالة تأكيد إلى ${_email.text.trim()}. افتحها واضغط الرابط، ثم عد وسجّل الدخول.',
              'We sent a confirmation email to ${_email.text.trim()}. Open it, tap the link, then come back and sign in.'),
          style: ts(p, size: 13, color: p.muted), textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        MakButton(t('أعد إرسال رسالة التأكيد', 'Resend confirmation'), kind: 'ghost', onPressed: () async {
          await repo.resendConfirmation(_email.text.trim());
          if (mounted) toast(context, t('تم إرسال الرسالة', 'Email sent'));
        }),
        const SizedBox(height: 8),
        MakButton(t('أكّدتُ بريدي — تسجيل الدخول', 'I confirmed — sign in'), onPressed: () {
          setState(() {
            _confirmPending = false;
            _register = false;
          });
        }),
      ]),
    );
  }

  Widget _demoCard(Palette p) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Pill(t('الوضع التجريبي', 'Demo mode'), color: p.accent, icon: Icons.science_outlined),
        const SizedBox(height: 10),
        Text(
          t('لم تُربط قاعدة البيانات بعد، لذلك يعمل التطبيق ببيانات تجريبية. اختر اللوحة التي تريد تجربتها:',
              'No database is connected yet, so the app runs on sample data. Pick a dashboard to try:'),
          style: ts(p, size: 13, color: p.text, height: 1.6),
        ),
        const SizedBox(height: 16),
        MakButton(t('تجربة لوحة العميل', 'Try client dashboard'), icon: Icons.person_outline, onPressed: () => _demo('client')),
        const SizedBox(height: 8),
        MakButton(t('تجربة لوحة الموظف', 'Try staff dashboard'), icon: Icons.badge_outlined, kind: 'soft', onPressed: () => _demo('staff')),
        const SizedBox(height: 8),
        MakButton(t('تجربة لوحة المدير', 'Try admin dashboard'), icon: Icons.shield_outlined, kind: 'ghost', onPressed: () => _demo('admin')),
      ]),
    );
  }

  Widget _formCard(Palette p) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: SelectChip(t('تسجيل الدخول', 'Sign in'), selected: !_register, onTap: () => setState(() { _register = false; _error = null; }))),
          const SizedBox(width: 8),
          Expanded(child: SelectChip(t('حساب جديد', 'New account'), selected: _register, onTap: () => setState(() { _register = true; _error = null; }))),
        ]),
        const SizedBox(height: 16),
        if (_register) ...[
          MakField(controller: _name, label: t('الاسم الكامل', 'Full name')),
          const SizedBox(height: 12),
        ],
        MakField(controller: _email, label: t('البريد الإلكتروني', 'Email'), keyboard: TextInputType.emailAddress, dir: TextDirection.ltr),
        const SizedBox(height: 12),
        MakField(controller: _pass, label: t('كلمة المرور', 'Password'), obscure: true, dir: TextDirection.ltr),
        if (_register) ...[
          const SizedBox(height: 12),
          MakField(controller: _pass2, label: t('تأكيد كلمة المرور', 'Confirm password'), obscure: true, dir: TextDirection.ltr),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.red.fade(0.14), borderRadius: BorderRadius.circular(8), border: Border.all(color: p.red.fade(0.4))),
            child: Row(children: [
              Icon(Icons.error_outline, size: 16, color: p.red),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: ts(p, size: 12.5, color: p.red))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        MakButton(_register ? t('إنشاء الحساب', 'Create account') : t('دخول', 'Sign in'), onPressed: _submit),
        if (_register) ...[
          const SizedBox(height: 10),
          Text(
            t('سيصلك بريد لتأكيد الحساب. أول حساب يُنشأ في النظام يصبح مديراً تلقائياً.',
                'You will get an email to confirm your account. The first account ever created becomes the admin.'),
            style: ts(p, size: 11.5, color: p.subtle, height: 1.5),
          ),
        ],
      ]),
    );
  }
}
