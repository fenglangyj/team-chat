import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final String? senderName;
  final AppState app;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor =
        isMine ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final textColor =
        isMine ? scheme.onPrimaryContainer : scheme.onSurface;

    Widget content;
    switch (message.kind) {
      case MessageKind.text:
        if (message.payload == null) {
          content = Text('🔒 消息解密中…', style: TextStyle(color: textColor));
        } else {
          content = SelectableText(
            message.text,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
          );
        }
      case MessageKind.image:
        content = _ImageCard(message: message, app: app, isMine: isMine);
      case MessageKind.file:
        content = _FileCard(message: message, app: app);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (senderName != null && !isMine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                senderName!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isMine ? 14 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 14),
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: content,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              formatTime(message.createdAt),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends StatefulWidget {
  final Message message;
  final AppState app;
  final bool isMine;

  const _ImageCard({
    required this.message,
    required this.app,
    required this.isMine,
  });

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard> {
  Uint8List? _bytes;
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final attachmentId = widget.message.attachmentId;
    if (attachmentId == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.app.attachments.downloadImageBytes(
        conversationId: widget.message.conversationId,
        attachmentId: attachmentId,
      );
      if (!mounted) return;
      setState(() => _bytes = bytes);
      _showPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '下载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPreview() {
    final bytes = _bytes;
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final attachmentId = widget.message.attachmentId;
    if (attachmentId == null) return;
    try {
      final file = await widget.app.attachments.downloadDecrypted(
        conversationId: widget.message.conversationId,
        attachmentId: attachmentId,
        suggestedName: widget.message.fileName,
      );
      final path =
          await widget.app.attachments.saveAs(file, widget.message.fileName);
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已保存到：$path')));
        await OpenFilex.open(path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_bytes != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _showPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _bytes!,
                width: 220,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _showPreview,
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('查看'),
              ),
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('保存'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.payload == null
                      ? '加密图片'
                      : widget.message.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  widget.message.payload == null
                      ? '点击下载并解密'
                      : formatBytes(widget.message.fileSize),
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(4),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.download, size: 16),
            label: Text(_error ?? '下载并查看'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ),
      ],
    );
  }
}

class _FileCard extends StatefulWidget {
  final Message message;
  final AppState app;

  const _FileCard({required this.message, required this.app});

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _downloading = false;
  String? _savedPath;
  String? _error;

  Future<void> _download() async {
    final attachmentId = widget.message.attachmentId;
    if (attachmentId == null || _downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final file = await widget.app.attachments.downloadDecrypted(
        conversationId: widget.message.conversationId,
        attachmentId: attachmentId,
        suggestedName: widget.message.fileName,
      );
      final path =
          await widget.app.attachments.saveAs(file, widget.message.fileName);
      if (!mounted) return;
      setState(() => _savedPath = path);
      if (path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已保存到：$path')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.payload == null
                        ? '加密文件'
                        : widget.message.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.message.payload == null
                        ? '点击下载并解密'
                        : formatBytes(widget.message.fileSize),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_downloading)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('下载解密中…'),
            ],
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download, size: 16),
                label: Text(_savedPath == null ? '下载' : '重新下载'),
              ),
              if (_savedPath != null)
                TextButton.icon(
                  onPressed: () => OpenFilex.open(_savedPath!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开'),
                ),
            ],
          ),
        if (_error != null)
          Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
      ],
    );
  }
}
