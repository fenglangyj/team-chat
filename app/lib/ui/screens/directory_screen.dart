import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/avatar.dart';
import 'group_create_screen.dart';

/// 团队通讯录：单选（发起私聊）或多选（加群成员）
class DirectoryScreen extends StatefulWidget {
  final String title;
  final bool multiSelect;
  final Set<String> excludeIds;

  /// 是否在顶部显示「新建群聊」入口（单选模式下）
  final bool showGroupCreate;

  const DirectoryScreen({
    super.key,
    required this.title,
    this.multiSelect = false,
    this.excludeIds = const {},
    this.showGroupCreate = false,
  });

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MemberProfile> _members(AppState app) {
    final convos = app.conversations;
    if (convos == null) return const [];
    final meId = app.session?.me.id;
    final list = convos.profiles.values
        .where((p) =>
            p.id != meId &&
            !widget.excludeIds.contains(p.id) &&
            _matches(p))
        .toList();
    list.sort((a, b) => a.nickname.compareTo(b.nickname));
    return list;
  }

  bool _matches(MemberProfile p) {
    if (_keyword.isEmpty) return true;
    final k = _keyword.toLowerCase();
    return p.nickname.toLowerCase().contains(k) ||
        p.account.toLowerCase().contains(k);
  }

  void _onTap(MemberProfile profile) {
    if (!widget.multiSelect) {
      Navigator.of(context).pop(profile);
      return;
    }
    setState(() {
      if (!_selected.add(profile.id)) {
        _selected.remove(profile.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final members = _members(app);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.multiSelect)
            TextButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final picked = members
                          .where((m) => _selected.contains(m.id))
                          .toList();
                      Navigator.of(context).pop(picked);
                    },
              child: Text('确定（${_selected.length}）'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _keyword = v.trim()),
              decoration: const InputDecoration(
                hintText: '搜索昵称或账号',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (widget.showGroupCreate && !widget.multiSelect) ...[
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.group_add_outlined,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                    ),
                    title: const Text('新建群聊'),
                    subtitle: const Text('选择成员创建新的群组'),
                    onTap: () async {
                      final conv = await Navigator.of(context)
                          .push<Conversation>(
                        MaterialPageRoute(
                          builder: (_) => const GroupCreateScreen(),
                        ),
                      );
                      if (conv != null && context.mounted) {
                        Navigator.of(context).pop(conv);
                      }
                    },
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  child: members.isEmpty
                      ? const Center(
                          child: Text('没有可选的成员\n（让同事用相同的 URL 和 KEY 注册即可加入）',
                              textAlign: TextAlign.center),
                        )
                      : ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final p = members[index];
                            final checked = _selected.contains(p.id);
                            return ListTile(
                              leading: ProfileAvatar(name: p.nickname),
                              title: Text(p.nickname),
                              subtitle: Text('@${p.account}'),
                              trailing: widget.multiSelect
                                  ? Checkbox(
                                      value: checked,
                                      onChanged: (_) => _onTap(p),
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: () => _onTap(p),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
