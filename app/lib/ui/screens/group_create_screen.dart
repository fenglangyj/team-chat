import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/avatar.dart';

/// 新建群聊：群名 + 勾选成员
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _name = TextEditingController();
  final Set<String> _selected = {};
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final app = context.read<AppState>();
    final convos = app.conversations;
    if (convos == null) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写群名称');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = '请至少选择一位成员');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final members = convos.profiles.values
          .where((p) => _selected.contains(p.id))
          .toList();
      final conv = await convos.createGroup(_name.text.trim(), members);
      if (!mounted) return;
      Navigator.of(context).pop(conv);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = '创建失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final convos = app.conversations;
    final scheme = Theme.of(context).colorScheme;
    final candidates = convos == null
        ? const <MemberProfile>[]
        : convos.profiles.values
            .where((p) => p.id != app.session?.me.id)
            .toList()
      ..sort((a, b) => a.nickname.compareTo(b.nickname));

    return Scaffold(
      appBar: AppBar(title: const Text('新建群聊')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '群名称（端到端加密存储）',
                hintText: '例如：项目小组',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '选择成员（${_selected.length}）',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: candidates.isEmpty
                ? const Center(
                    child: Text('团队里还没有其他成员',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final p = candidates[index];
                      final checked = _selected.contains(p.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) => setState(() {
                          if (!_selected.add(p.id)) {
                            _selected.remove(p.id);
                          }
                        }),
                        secondary: ProfileAvatar(name: p.nickname, radius: 18),
                        title: Text(p.nickname),
                        subtitle: Text('@${p.account}'),
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('创建群聊'),
            ),
          ),
        ],
      ),
    );
  }
}
