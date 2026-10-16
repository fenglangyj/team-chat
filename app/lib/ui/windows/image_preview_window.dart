import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

/// 在主窗口中调用：打开一个独立的图片预览窗口。
/// 返回 true 表示窗口创建成功；false 时调用方可回退到应用内弹窗。
Future<bool> openImagePreviewWindow({
  required String path,
  required String title,
}) async {
  try {
    await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'image_preview',
          'path': path,
          'title': title,
        }),
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// 独立预览窗口的应用（运行在单独的 Flutter 引擎中）
class ImagePreviewApp extends StatefulWidget {
  final String path;
  final String title;

  const ImagePreviewApp({super.key, required this.path, required this.title});

  @override
  State<ImagePreviewApp> createState() => _ImagePreviewAppState();
}

class _ImagePreviewAppState extends State<ImagePreviewApp> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _setupWindow();
  }

  Future<void> _setupWindow() async {
    try {
      await windowManager.setTitle(widget.title);
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(1000, 720),
          center: true,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (_) {
      // 窗口管理不可用时交由系统默认行为
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final file = File(widget.path);
      final bytes = await file.readAsBytes();
      final uri = await FilePicker.saveFile(
        fileName: widget.title,
        bytes: bytes,
        dialogTitle: '保存图片',
      );
      if (mounted && uri != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已保存到：${uri.toFilePath()}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontSize: 15)),
          actions: [
            IconButton(
              tooltip: '保存图片',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
            ),
          ],
        ),
        body: InteractiveViewer(
          minScale: 0.2,
          maxScale: 8,
          child: Center(
            child: Image.file(
              File(widget.path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
                '无法加载图片',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
