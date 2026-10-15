import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/avatar.dart';
import 'directory_screen.dart';

/// 会话信息：成员、密钥状态、清空记录
class ConversationInfoScreen extends StatefulWidget {
  final Conversation conversation;

  const ConversationInfoScreen({super.key, required this.conversation});

  @override
  State<ConversationInfoScreen> createState() =>
      _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<ConversationInfoScreen> {
  bool _busy = false;

  Future<void> _addMembers() async {
    final app = context.read<AppState>();
    final convos = app.conversations;
    if (convos == null) return;
    final existing =
        convos.membersOf(widget.conversation.id).map((m) => m.id).toSet();
    final picked = await Navigator.of(context).push<List<MemberProfile>>(
      MaterialPageRoute(
        builder: (_) => DirectoryScreen(
          title: '添加成员',
          multiSelect: true,
          excludeIds: existing,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final err = await convos.addMembers(widget.conversation.id, picked);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? '已添加 ${picked.length} 位成员')));
  }

  Future<void> _clearHistory() async {
    final app = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text(
          '将永久删除该会话的全部消息与文件，所有成员的设备上也会同步清除。\n\n此操作不可恢复，确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await app.session?.client
          .rpc('clear_conversation', params: {'conv': widget.conversation.id});
      await app.attachments.purgeConversation(widget.conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清空该会话的聊天记录')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('清空失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final convos = app.conversations;
    final conv = widget.conversation;
    final scheme = Theme.of(context).colorScheme;
    final name = convos?.displayName(conv) ?? '会话';
    final members = convos?.membersOf(conv.id) ?? const [];
    final hasKey = convos?.hasKeyFor(conv.id) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('会话信息')),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Center(
            child: ProfileAvatar(
              name: name,
              radius: 34,
              icon: conv.kind == ConversationKind.group &&
                      !conv.isDefaultGroup
                  ? Icons.groups
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasKey ? Icons.lock : Icons.lock_clock,
                  size: 14,
                  color: hasKey ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  hasKey ? '端到端加密已就绪' : '等待密钥分发',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasKey ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (conv.kind == ConversationKind.group)
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('添加成员'),
              enabled: !_busy && hasKey,
              onTap: _busy ? null : _addMembers,
            ),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: scheme.error),
            title: Text('清空聊天记录', style: TextStyle(color: scheme.error)),
            enabled: !_busy,
            onTap: _busy ? null : _clearHistory,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '成员（${members.length}）',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          ...members.map((m) {
            final isMe = m.id == app.session?.me.id;
            return ListTile(
              leading: ProfileAvatar(name: m.nickname, radius: 18),
              title: Text(
                isMe ? '${m.nickname}（我）' : m.nickname,
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: Text('@${m.account}', style: const TextStyle(fontSize: 12)),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
