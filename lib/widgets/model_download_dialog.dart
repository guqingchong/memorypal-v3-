import 'dart:io';
import 'package:flutter/material.dart';
import '../services/whisper_local_service.dart';

/// 模型下载对话框
///
/// 用于下载Whisper语音转写模型
class ModelDownloadDialog extends StatefulWidget {
  final VoidCallback? onDownloadComplete;

  const ModelDownloadDialog({super.key, this.onDownloadComplete});

  @override
  State<ModelDownloadDialog> createState() => _ModelDownloadDialogState();

  /// 显示下载对话框
  static Future<bool> show(BuildContext context, {VoidCallback? onComplete}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ModelDownloadDialog(onDownloadComplete: onComplete),
    );
    return result ?? false;
  }
}

class _ModelDownloadDialogState extends State<ModelDownloadDialog> {
  final _whisperService = WhisperLocalService();
  bool _isChecking = true;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    final isDownloaded = await _whisperService.isModelDownloaded();
    setState(() {
      _isDownloaded = isDownloaded;
      _isChecking = false;
    });

    if (isDownloaded) {
      // 自动关闭
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context, true);
          widget.onDownloadComplete?.call();
        }
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _error = null;
    });

    final success = await _whisperService.downloadModel(
      onProgress: (progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      },
    );

    if (mounted) {
      if (success) {
        setState(() {
          _isDownloaded = true;
          _isDownloading = false;
        });
        widget.onDownloadComplete?.call();
        // 延迟关闭
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context, true);
        });
      } else {
        setState(() {
          _isDownloading = false;
          _error = _whisperService.error ?? '下载失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('检查模型状态...'),
          ],
        ),
      );
    }

    if (_isDownloaded) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('模型已就绪'),
          ],
        ),
        content: const Text('Whisper语音转写模型已准备就绪，可以开始转写了。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('下载语音转写模型'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '首次使用语音转写需要下载AI模型文件（约244MB）。\n\n'
            '下载后所有转写将在本地完成，无需联网，保护隐私。',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(
              '下载进度: ${(_progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '错误: $_error',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
        if (_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('后台下载'),
          )
        else
          ElevatedButton.icon(
            onPressed: _downloadModel,
            icon: const Icon(Icons.download),
            label: const Text('开始下载'),
          ),
      ],
    );
  }
}
