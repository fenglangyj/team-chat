import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';
import '../widgets/avatar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _changeNickname(BuildContext context) async {
    final app = context.read<AppState>();
    final controller = TextEditingController(text: app.session?.me.nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final err = await app.changeNickname(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? '昵称已更新')));
  }

  Future<void> _changePassword(BuildContext context) async {
    final app = context.read<AppState>();
    final oldPw = TextEditingController();
    final newPw = TextEditingController();
    final newPw2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码（至少 6 位）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newPw2,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('修改'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (newPw.text != newPw2.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('两次输入的新密码不一致')));
      return;
    }
    final err = await app.changePassword(oldPw.text, newPw.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? '密码已修改')));
  }

  Future<void> _resetServer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更换服务器配置'),
        content: const Text(
          '将退出当前账号并重新填写 SUPABASE_URL / ANON_KEY。\n切换后将进入新的团队，当前内存中的聊天记录会被清空。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('更换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    context.read<AppState>().resetConfig();
  }

  void _about(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppInfo.fullName,
      applicationVersion: 'v${AppInfo.version}',
      applicationIcon: const Icon(Icons.forum_outlined, size: 40),
      children: const [
        SizedBox(height: 8),
        Text(
          '面向团队内部的端到端加密聊天工具。\n'
          '消息与文件在设备端加密，服务端（Supabase）只保存密文；\n'
          '聊天记录 24 小时自动销毁，客户端不落盘。\n\n'
          '开源仓库：${AppInfo.repoUrl}',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final me = app.session?.me;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(child: ProfileAvatar(name: me?.nickname ?? '?', radius: 32)),
          const SizedBox(height: 10),
          Center(
            child: Text(
              me?.nickname ?? '',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '@${me?.account ?? ''}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('修改昵称'),
            subtitle: Text(me?.nickname ?? ''),
            onTap: () => _changeNickname(context),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('修改密码'),
            subtitle: const Text('密码同时用于加密你的密钥'),
            onTap: () => _changePassword(context),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器配置'),
            subtitle: Text(app.config?.url ?? '未配置',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _resetServer(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('v${AppInfo.version} · MIT 开源'),
            onTap: () => _about(context),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.tonal(
              onPressed: () => _confirmSignOut(context),
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新输入账号密码登录，聊天记录（内存缓存）将被清空。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).popUntil((r) => r.isFirst);
              context.read<AppState>().signOut();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}
