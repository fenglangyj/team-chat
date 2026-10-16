import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
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
  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  late final AppState _app = context.read<AppState>();
  late final ChatController _chat =
      ChatController(_app, widget.conversation.id);
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  Timer? _keyRetryTimer;

  @override
  void initState() {
    super.initState();
    _chat.init();
    _scroll.addListener(_onScroll);
    _app.conversations?.addListener(_onConversationsChanged);
    // 等待密钥期间每 30 秒自动重新请求一次（对方上线后能马上收到）
    _keyRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_chat.waitingKey) return;
      _app.conversations?.requestKeyFor(widget.conversation.id);
    });
  }

  @override
  void dispose() {
    _keyRetryTimer?.cancel();
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
      final picked = await FilePicker.pickFile(
        type: image ? FileType.image : FileType.any,
        dialogTitle: image ? '选择图片' : '选择文件',
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法读取所选文件')));
        }
        return;
      }
      final file = File(path);
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
        size: await picked.length() ?? await file.length(),
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

  // ---------- 粘贴发送（桌面端） ----------

  /// 处理 Ctrl/Cmd+V：优先发送复制的文件，其次发送剪贴板图片（含截图），
  /// 都没有时按普通文本粘贴。
  Future<void> _handlePaste() async {
    if (_isDesktop) {
      try {
        final files = await Pasteboard.files();
        final valid = files.where((p) => File(p).existsSync()).toList();
        if (valid.isNotEmpty) {
          await _sendPastedFiles(valid);
          return;
        }
      } catch (_) {}
      try {
        final bytes = await Pasteboard.image;
        if (bytes != null && bytes.isNotEmpty) {
          await _sendPastedImage(bytes);
          return;
        }
      } catch (_) {}
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        _insertAtCursor(text);
      }
    } catch (_) {}
  }

  void _insertAtCursor(String text) {
    final value = _input.value;
    final base = value.text;
    var start = value.selection.isValid ? value.selection.start : base.length;
    var end = value.selection.isValid ? value.selection.end : base.length;
    if (start < 0 || start > base.length) start = base.length;
    if (end < start || end > base.length) end = start;
    final newText = base.replaceRange(start, end, text);
    _input.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  Future<void> _sendPastedImage(Uint8List bytes) async {
    if (_chat.waitingKey) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('会话密钥未就绪，请稍候再试')));
      return;
    }
    if (_chat.sending) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}paste_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);
      final name = '截图_${_stamp()}.png';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在加密上传 $name …')),
      );
      final err = await _chat.sendFile(
        file: file,
        name: name,
        mime: 'image/png',
        size: bytes.length,
        isImage: true,
      );
      try {
        await file.delete();
      } catch (_) {}
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('粘贴发送失败：$e')));
    }
  }

  Future<void> _sendPastedFiles(List<String> paths) async {
    if (_chat.waitingKey) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('会话密钥未就绪，请稍候再试')));
      return;
    }
    if (_chat.sending) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('正在发送中，请稍候再试')));
      return;
    }
    const maxCount = 10;
    final list = paths.take(maxCount).toList();
    if (paths.length > maxCount && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('一次最多发送 10 个文件，已取前 10 个')),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在加密上传 ${list.length} 个文件…')),
    );
    var failed = 0;
    for (final path in list) {
      final file = File(path);
      final name = path.split(RegExp(r'[\\/]')).last;
      final mime = lookupMimeType(name) ?? 'application/octet-stream';
      try {
        final err = await _chat.sendFile(
          file: file,
          name: name,
          mime: mime,
          size: await file.length(),
          isImage: mime.startsWith('image/'),
        );
        if (err != null) failed++;
      } catch (_) {
        failed++;
      }
    }
    if (mounted && failed > 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$failed 个文件发送失败')));
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
                    const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                        () {
                      if (ready) _handlePaste();
                    },
                    const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                        () {
                      if (ready) _handlePaste();
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
