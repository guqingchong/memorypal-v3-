import 'dart:async';
import 'package:flutter/services.dart';

/// 分享接收服务 - 处理从其他应用分享的内容
///
/// 支持接收：
/// - 文本分享
/// - 链接分享
/// - 图片分享
/// - PDF文档分享
/// - 多张图片分享
class ShareReceiverService {
  static const MethodChannel _channel = MethodChannel('com.memorypal/share');
  static final ShareReceiverService _instance = ShareReceiverService._internal();

  factory ShareReceiverService() => _instance;
  ShareReceiverService._internal();

  // 分享内容流
  final _shareController = StreamController<ShareData>.broadcast();
  Stream<ShareData> get onShareReceived => _shareController.stream;

  // 是否有待处理的分享数据
  bool _hasPendingShare = false;
  bool get hasPendingShare => _hasPendingShare;

  /// 初始化分享接收服务
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);

    // 检查是否有待处理的分享数据（应用从分享启动）
    await _checkPendingShare();
  }

  /// 处理原生层回调
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onShareReceived':
        final data = call.arguments as Map<dynamic, dynamic>?;
        if (data != null) {
          _handleShareData(data);
        }
        break;
      default:
        break;
    }
  }

  /// 检查是否有待处理的分享数据
  Future<void> _checkPendingShare() async {
    try {
      final data = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPendingShareData');
      if (data != null) {
        _hasPendingShare = true;
        _handleShareData(data);
      }
    } catch (e) {
      print('检查待处理分享数据失败: $e');
    }
  }

  /// 处理分享数据
  void _handleShareData(Map<dynamic, dynamic> data) {
    final shareData = ShareData.fromMap(data);
    _shareController.add(shareData);
    _hasPendingShare = true;
    print('收到分享内容: ${shareData.type} - ${shareData.preview}');
  }

  /// 清除待处理的分享数据
  Future<void> clearPendingShare() async {
    try {
      await _channel.invokeMethod('clearPendingShareData');
      _hasPendingShare = false;
    } catch (e) {
      print('清除分享数据失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _shareController.close();
  }
}

/// 分享数据模型
class ShareData {
  final ShareType type;
  final String? text;
  final String? subject;
  final String? uri;
  final List<String>? uris;
  final String? url;
  final DateTime timestamp;

  ShareData({
    required this.type,
    this.text,
    this.subject,
    this.uri,
    this.uris,
    this.url,
    required this.timestamp,
  });

  factory ShareData.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'unknown';
    return ShareData(
      type: ShareType.fromString(typeStr),
      text: map['text'] as String?,
      subject: map['subject'] as String?,
      uri: map['uri'] as String?,
      uris: (map['uris'] as List<dynamic>?)?.cast<String>(),
      url: map['url'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 获取内容预览
  String get preview {
    switch (type) {
      case ShareType.text:
        return text?.substring(0, text!.length.clamp(0, 100)) ?? '无内容';
      case ShareType.link:
        return url ?? '无链接';
      case ShareType.image:
        return '图片: ${uri?.split('/').last ?? '未知'}';
      case ShareType.multipleImages:
        return '${uris?.length ?? 0} 张图片';
      case ShareType.pdf:
        return 'PDF: ${uri?.split('/').last ?? '未知'}';
      case ShareType.unknown:
        return '未知类型';
    }
  }

  /// 获取标题
  String get title {
    if (subject != null && subject!.isNotEmpty) {
      return subject!;
    }
    switch (type) {
      case ShareType.text:
        return '分享的文本';
      case ShareType.link:
        return '分享的链接';
      case ShareType.image:
        return '分享的图片';
      case ShareType.multipleImages:
        return '分享的多张图片';
      case ShareType.pdf:
        return '分享的PDF文档';
      case ShareType.unknown:
        return '分享的内容';
    }
  }
}

enum ShareType {
  text,
  link,
  image,
  multipleImages,
  pdf,
  unknown;

  factory ShareType.fromString(String value) {
    switch (value) {
      case 'text':
        return ShareType.text;
      case 'link':
        return ShareType.link;
      case 'image':
        return ShareType.image;
      case 'multiple_images':
        return ShareType.multipleImages;
      case 'pdf':
        return ShareType.pdf;
      default:
        return ShareType.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case ShareType.text:
        return '文本';
      case ShareType.link:
        return '链接';
      case ShareType.image:
        return '图片';
      case ShareType.multipleImages:
        return '多张图片';
      case ShareType.pdf:
        return 'PDF文档';
      case ShareType.unknown:
        return '未知';
    }
  }

  IconData get icon {
    switch (this) {
      case ShareType.text:
        return Icons.text_fields;
      case ShareType.link:
        return Icons.link;
      case ShareType.image:
        return Icons.image;
      case ShareType.multipleImages:
        return Icons.collections;
      case ShareType.pdf:
        return Icons.picture_as_pdf;
      case ShareType.unknown:
        return Icons.help_outline;
    }
  }
}

// 导入图标
import 'package:flutter/material.dart';
