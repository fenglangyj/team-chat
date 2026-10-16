import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/constants.dart';
import 'state/app_state.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/unlock_screen.dart';
import 'ui/theme.dart';
import 'ui/windows/image_preview_window.dart';

bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端子窗口分流（图片预览等独立窗口）
  if (isDesktopPlatform) {
    try {
      await windowManager.ensureInitialized();
      final controller = await WindowController.fromCurrentEngine();
      final raw = controller.arguments;
      if (raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map && data['type'] == 'image_preview') {
          runApp(ImagePreviewApp(
            path: data['path'] as String,
            title: (data['title'] as String?) ?? '图片预览',
          ));
          return;
        }
      }
    } catch (_) {
      // 多窗口不可用时按普通启动流程走
    }
  }

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
