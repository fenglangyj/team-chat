import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/avatar.dart';

/// 已有登录会话时：用密码解锁本地私钥（密码不会被保存）
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() => _error = null);
    final app = context.read<AppState>();
    final err = await app.unlock(_password.text);
    if (!mounted) return;
    if (err != null) setState(() => _error = err);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final profile = app.unlockProfile;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                ProfileAvatar(name: profile?.nickname ?? '?', radius: 34),
                const SizedBox(height: 14),
                Text(
                  profile?.nickname ?? '',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${profile?.account ?? ''}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  onSubmitted: (_) => app.busy ? null : _unlock(),
                  decoration: const InputDecoration(
                    labelText: '输入密码解锁',
                    hintText: '密码仅用于本机解密，不会被保存',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: scheme.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: app.busy ? null : _unlock,
                    child: app.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('解锁'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed:
                      app.busy ? null : () => context.read<AppState>().signOut(),
                  child: const Text('切换账号 / 退出登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
