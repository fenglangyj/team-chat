import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/conversations_controller.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'directory_screen.dart';
import 'group_create_screen.dart';
import 'settings_screen.dart';

/// 会话列表
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openChat(BuildContext context, Conversation conversation) async {
    final app = context.read<AppState>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation),
      ),
    );
    // 返回后刷新预览
    await app.conversations?.refreshPreviews();
  }

  void _showNewConversationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('发起私聊'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final result = await Navigator.of(context).push<MemberProfile>(
                  MaterialPageRoute(
                    builder: (_) => const DirectoryScreen(title: '发起私聊'),
                  ),
                );
                if (result == null || !context.mounted) return;
                final app = context.read<AppState>();
                final convos = app.conversations;
                if (convos == null) return;
                try {
                  final conv = await convos.startDirect(result);
                  if (!context.mounted) return;
                  _openChat(context, conv);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('创建失败：$e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('新建群聊'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final conv = await Navigator.of(context).push<Conversation>(
                  MaterialPageRoute(
                    builder: (_) => const GroupCreateScreen(),
                  ),
                );
                if (conv == null || !context.mounted) return;
                _openChat(context, conv);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final convos = app.conversations;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.forum_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('团队通', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context),
          ),
        ],
      ),
      body: convos == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await convos.refreshProfiles();
                await convos.refreshConversations();
                await convos.refreshPreviews();
              },
              child: _buildList(context, app, convos),
            ),
      floatingActionButton: convos == null
          ? null
          : FloatingActionButton(
              onPressed: () => _showNewConversationSheet(context),
              tooltip: '新会话',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildList(
      BuildContext context, AppState app, ConversationsController convos) {
    final list = convos.sorted;
    if (list.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 160),
          Center(
            child: Text(
              '暂无会话\n点击右下角 + 开始聊天',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final conv = list[index];
        final name = convos.displayName(conv);
        final last = convos.lastMessages[conv.id];
        final hasKey = convos.hasKeyFor(conv.id);
        return ListTile(
          leading: ProfileAvatar(
            name: name,
            icon: conv.kind == ConversationKind.group &&
                    !conv.isDefaultGroup
                ? Icons.groups
                : null,
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            conv.isDefaultGroup && last == null
                ? '团队全员都在这里'
                : (last?.previewText ?? '暂无消息'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (last != null)
                Text(
                  formatTime(last.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (!hasKey)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.lock_clock,
                    size: 14,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
          onTap: () => _openChat(context, conv),
        );
      },
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
              context.read<AppState>().signOut();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}
