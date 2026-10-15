import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'state/app_state.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/unlock_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeamChatApp());
}

class TeamChatApp extends StatelessWidget {
  const TeamChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..bootstrap(),
      child: MaterialApp(
        title: AppInfo.fullName,
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: const _RootPage(),
      ),
    );
  }
}

class _RootPage extends StatelessWidget {
  const _RootPage();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return switch (app.phase) {
      AppPhase.booting => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AppPhase.setup => const SetupScreen(),
      AppPhase.login => const LoginScreen(),
      AppPhase.unlock => const UnlockScreen(),
      AppPhase.ready => const HomeScreen(),
    };
  }
}
