import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';

/// 登录 / 注册
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _loginAccount = TextEditingController();
  final _loginPassword = TextEditingController();
  final _regAccount = TextEditingController();
  final _regPassword = TextEditingController();
  final _regPassword2 = TextEditingController();
  final _regNickname = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _tabs.dispose();
    _loginAccount.dispose();
    _loginPassword.dispose();
    _regAccount.dispose();
    _regPassword.dispose();
    _regPassword2.dispose();
    _regNickname.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _error = null);
    final app = context.read<AppState>();
    final err = await app.login(
      account: _loginAccount.text,
      password: _loginPassword.text,
    );
    if (!mounted) return;
    if (err != null) setState(() => _error = err);
  }

  Future<void> _register() async {
    setState(() => _error = null);
    if (_regPassword.text != _regPassword2.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    final app = context.read<AppState>();
    final err = await app.register(
      account: _regAccount.text,
      password: _regPassword.text,
      nickname: _regNickname.text,
    );
    if (!mounted) return;
    if (err != null) setState(() => _error = err);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final busy = app.busy;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Icon(Icons.forum_outlined, size: 52, color: scheme.primary),
                const SizedBox(height: 10),
                const Text(
                  AppInfo.fullName,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  app.config?.url ?? '',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TabBar(
                          controller: _tabs,
                          tabs: const [
                            Tab(text: '登录'),
                            Tab(text: '注册'),
                          ],
                          onTap: (_) => setState(() => _error = null),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 320,
                          child: TabBarView(
                            controller: _tabs,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _buildLoginForm(busy),
                              _buildRegisterForm(busy),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: scheme.error, fontSize: 13),
                            ),
                          ),
                        ],
                        if (busy) ...[
                          const SizedBox(height: 10),
                          const LinearProgressIndicator(),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: busy ? null : () => context.read<AppState>().resetConfig(),
                  child: const Text('重新配置服务器', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(bool busy) {
    return Column(
      children: [
        TextField(
          controller: _loginAccount,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: '账号'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPassword,
          obscureText: true,
          onSubmitted: (_) => busy ? null : _login(),
          decoration: const InputDecoration(labelText: '密码'),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : _login,
            child: const Text('登录'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '在任意设备用相同账号 + 密码登录即可收消息',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm(bool busy) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TextField(
            controller: _regAccount,
            decoration: const InputDecoration(
              labelText: '账号（3~32 位字母/数字/下划线，用于登录）',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码（至少 6 位）',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPassword2,
            obscureText: true,
            decoration: const InputDecoration(labelText: '确认密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regNickname,
            decoration:
                const InputDecoration(labelText: '昵称（展示给团队成员）'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : _register,
              child: const Text('注册并进入'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '密码同时用于加密你的密钥，请务必牢记；忘记后无法解密历史消息。',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
