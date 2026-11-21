import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/state.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/session.dart';
import 'features/shell/shell.dart';

class MakApp extends StatelessWidget {
  const MakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final role = appState.signedIn ? appState.role : 'brand';
        final pal = Palette.build(dark: appState.dark, role: role);
        return MaterialApp(
          key: ValueKey(appState.lang),
          title: 'M.A.K Booking',
          debugShowCheckedModeBanner: false,
          locale: Locale(appState.lang),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(pal),
          builder: (context, child) => PalScope(palette: pal, lang: appState.lang, child: child ?? const SizedBox()),
          home: const Root(),
        );
      },
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.booting) {
          return Scaffold(
            backgroundColor: p.bg,
            body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const MakLogo(size: 72),
              const SizedBox(height: 20),
              CircularProgressIndicator(color: p.accent, strokeWidth: 2.5),
            ])),
          );
        }
        if (!appState.signedIn) return const AuthScreen();
        return Shell(key: ValueKey('shell-${appState.role}'));
      },
    );
  }
}
