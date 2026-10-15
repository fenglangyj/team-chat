import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

/// 首次运行：配置 Supabase 后端
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _obscureKey = true;
  String? _localError;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final app = context.read<AppState>();
    var url = _urlController.text.trim();
    final key = _keyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() => _localError = '请填写两项配置');
      return;
    }
    if (!url.startsWith('http')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    setState(() => _localError = null);
    final err = await app.connect(AppConfig(url: url, anonKey: key));
    if (!mounted || err == null) return;
    setState(() => _localError = err);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.forum_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                const Text(
                  AppInfo.fullName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '连接你的团队服务器',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'SUPABASE_URL',
                    hintText: 'https://xxxx.supabase.co',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'SUPABASE_ANON_KEY',
                    hintText: 'sb_publishable_... 或 eyJ...',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                if (_localError != null) ...[
                  const SizedBox(height: 12),
                  Text(_localError!,
                      style: TextStyle(color: scheme.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: app.busy ? null : _connect,
                  child: app.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('连接'),
                ),
                const SizedBox(height: 16),
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('如何获取这两个值？', style: TextStyle(fontSize: 14)),
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '1. 打开 supabase.com 注册并创建一个免费项目\n'
                        '2. 在 Project Settings → API Keys 复制 Project URL 和 '
                        'Publishable key（或 Legacy 里的 anon public key）\n'
                        '3. 在 SQL Editor 中执行仓库 supabase/migrations 下的两个 '
                        'SQL 文件\n'
                        '4. 关闭 Authentication 里的 Confirm email\n\n'
                        '完整图文教程见仓库 docs/setup-supabase.md。\n'
                        '把这两个值发给同事，他们就能加入同一个团队。',
                        style: TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
