import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/chat_controller.dart';
import '../widgets/message_bubble.dart';
import 'conversation_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final AppState _app = context.read<AppState>();
  late final ChatController _chat =
      ChatController(_app, widget.conversation.id);
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _chat.init();
    _scroll.addListener(_onScroll);
    _app.conversations?.addListener(_onConversationsChanged);
  }

  @override
  void dispose() {
    _app.conversations?.removeListener(_onConversationsChanged);
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    _chat.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _chat.loadMore();
    }
  }

  void _onConversationsChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_chat.waitingKey) {
      _chat.retryDecrypt();
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    final err = await _chat.sendText(text);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _pickAndSend({required bool image}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: image ? FileType.image : FileType.any,
        withData: false,
      );
      final picked = result?.files.singleOrNull;
      if (picked == null || picked.path == null) return;
      final file = File(picked.path!);
      final name = picked.name;
      final mime = lookupMimeType(name) ??
          (image ? 'image/jpeg' : 'application/octet-stream');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在加密上传 $name …')),
      );
      final err = await _chat.sendFile(
        file: file,
        name: name,
        mime: mime,
        size: await file.length(),
        isImage: image,
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('选择文件失败：$e')));
    }
  }

  Future<void> _clearHistory() async {
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
    final err = await _chat.clearHistory();
    if (err == null) {
      await _app.conversations?.refreshPreviews();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '已清空该会话的聊天记录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final convos = _app.conversations;
    final name = convos?.displayName(widget.conversation) ?? '会话';
    final memberCount = convos?.membersOf(widget.conversation.id).length ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 17)),
            if (widget.conversation.kind == ConversationKind.group)
              Text(
                '$memberCount 位成员',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '会话信息',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ConversationInfoScreen(conversation: widget.conversation),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clearHistory();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('清空聊天记录')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_chat.waitingKey) _buildWaitingBanner(scheme),
          Expanded(
            child: AnimatedBuilder(
              animation: _chat,
              builder: (context, _) => _buildMessageList(scheme),
            ),
          ),
          AnimatedBuilder(
            animation: _chat,
            builder: (context, _) => _buildComposer(scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingBanner(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.lock_clock, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在等待其他成员分发会话密钥，暂时无法收发消息',
              style:
                  TextStyle(fontSize: 13, color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(
            onPressed: () =>
                _app.conversations?.requestKeyFor(widget.conversation.id),
            child: const Text('重新请求'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ColorScheme scheme) {
    final messages = _chat.messages;
    if (messages.isEmpty) {
      if (_chat.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          _chat.error ?? '还没有消息\n发一条打个招呼吧',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
        ),
      );
    }

    final hasMoreRow = _chat.hasMore;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: messages.length + (hasMoreRow ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final msg = messages[messages.length - 1 - index];
        final isMine = msg.senderId == _app.session?.me.id;
        final sender = isMine
            ? null
            : _app.conversations?.profiles[msg.senderId]?.nickname;
        return MessageBubble(
          message: msg,
          isMine: isMine,
          senderName:
              widget.conversation.kind == ConversationKind.group && !isMine
                  ? sender
                  : null,
          app: _app,
        );
      },
    );
  }

  Widget _buildComposer(ColorScheme scheme) {
    final ready = !_chat.waitingKey;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_chat.uploadProgress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: LinearProgressIndicator(value: _chat.uploadProgress),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '发送图片',
                onPressed:
                    ready && !_chat.sending ? () => _pickAndSend(image: true) : null,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: '发送文件',
                onPressed:
                    ready && !_chat.sending ? () => _pickAndSend(image: false) : null,
                icon: const Icon(Icons.attach_file),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (ready && !_chat.sending) _send();
                    },
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    enabled: ready,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: ready ? '输入消息…' : '等待密钥…',
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: '发送',
                onPressed:
                    ready && !_chat.sending ? _send : null,
                icon: _chat.sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
