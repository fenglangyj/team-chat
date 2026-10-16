import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/conversations_controller.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'directory_screen.dart';
import 'settings_screen.dart';

/// 会话列表（桌面端：左侧列表 + 右侧聊天；移动端：列表 + 页面跳转）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedId;

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _openChat(BuildContext context, Conversation conversation) async {
    final app = context.read<AppState>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation),
      ),
    );
    await app.conversations?.refreshPreviews();
  }

  void _onConversationTap(
      BuildContext context, ConversationsController convos, Conversation conv,
      {required bool wide}) {
    if (wide) {
      setState(() => _selectedId = conv.id);
      return;
    }
    _openChat(context, conv);
  }

  /// 打开团队成员（通讯录）：发起私聊或新建群聊
  Future<void> _openDirectory(BuildContext context,
      {required bool wide}) async {
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => const DirectoryScreen(
          title: '团队成员',
          showGroupCreate: true,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final app = context.read<AppState>();
    final convos = app.conversations;
    if (convos == null) return;
    try {
      Conversation? conv;
      if (result is Conversation) {
        conv = result;
      } else if (result is MemberProfile) {
        conv = await convos.startDirect(result);
      }
      if (conv == null || !context.mounted) return;
      if (wide) {
        setState(() => _selectedId = conv!.id);
      } else {
        _openChat(context, conv);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败：$e')));
    }
  }

  Widget _buildDirectoryTile(BuildContext context, {required bool wide}) {
    return ListTile(
      leading: const Icon(Icons.people_alt_outlined),
      title: const Text('团队成员'),
      subtitle: const Text('发起私聊 / 新建群聊'),
      onTap: () => _openDirectory(context, wide: wide),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final convos = app.conversations;
    final scheme = Theme.of(context).colorScheme;

    final wide =
        _isDesktop && MediaQuery.sizeOf(context).width >= 820;

    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: Row(
                children: [
                  Icon(Icons.forum_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('团队通',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
          : ListenableBuilder(
              listenable: convos,
              builder: (context, _) => wide
                  ? _buildWide(context, convos)
                  : _buildNarrow(context, convos),
            ),
    );
  }

  Widget _buildNarrow(BuildContext context, ConversationsController convos) {
    return Column(
      children: [
        _buildDirectoryTile(context, wide: false),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _refresh(convos),
            child: _buildList(context, convos, wide: false),
          ),
        ),
      ],
    );
  }

  Widget _buildWide(BuildContext context, ConversationsController convos) {
    Conversation? selected;
    for (final c in convos.conversations) {
      if (c.id == _selectedId) {
        selected = c;
        break;
      }
    }

    return Row(
      children: [
        SizedBox(
          width: 320,
          child: _buildSidebar(context, convos),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const _ChatPlaceholder()
              : ChatScreen(
                  key: ValueKey(selected.id),
                  conversation: selected,
                ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, ConversationsController convos) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.forum_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('团队通',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                IconButton(
                  tooltip: '退出登录',
                  icon: const Icon(Icons.logout, size: 20),
                  onPressed: () => _confirmSignOut(context),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        _buildDirectoryTile(context, wide: true),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _refresh(convos),
            child: _buildList(context, convos, wide: true),
          ),
        ),
      ],
    );
  }

  Future<void> _refresh(ConversationsController convos) async {
    await convos.refreshProfiles();
    await convos.refreshConversations();
    await convos.refreshPreviews();
  }

  Widget _buildList(
      BuildContext context, ConversationsController convos,
      {required bool wide}) {
    final list = convos.sorted;
    final scheme = Theme.of(context).colorScheme;
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
        final unread = convos.unreadOf(conv.id);
        final selected = wide && conv.id == _selectedId;

        final isGroup = conv.kind == ConversationKind.group;
        return ListTile(
          selected: selected,
          selectedTileColor: scheme.primary.withValues(alpha: 0.08),
          leading: ProfileAvatar(
            name: name,
            // 群聊：群组图标（全员群使用特殊配色），私聊：昵称首字头像
            icon: isGroup ? Icons.groups : null,
            backgroundColor:
                conv.isDefaultGroup ? scheme.tertiaryContainer : null,
            foregroundColor:
                conv.isDefaultGroup ? scheme.onTertiaryContainer : null,
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
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else if (!hasKey)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.lock_clock,
                    size: 14,
                    color: scheme.outline,
                  ),
                ),
            ],
          ),
          onTap: () => _onConversationTap(context, convos, conv, wide: wide),
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

class _ChatPlaceholder extends StatelessWidget {
  const _ChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '选择左侧的会话开始聊天',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
