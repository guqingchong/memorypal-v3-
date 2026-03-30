import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// 权限管理器 - 处理所有权限请求
class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  // 检查所有必要权限
  Future<Map<Permission, PermissionStatus>> checkAllPermissions() async {
    return await [
      Permission.microphone,
      Permission.storage,
      Permission.location,
      Permission.notification,
    ].request();
  }

  // 检查麦克风权限
  Future<bool> checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;

    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  // 检查存储权限
  Future<bool> checkStoragePermission() async {
    final status = await Permission.storage.status;
    if (status.isGranted) return true;

    final result = await Permission.storage.request();
    return result.isGranted;
  }

  // 检查位置权限
  Future<bool> checkLocationPermission() async {
    final status = await Permission.location.status;
    if (status.isGranted) return true;

    final result = await Permission.location.request();
    return result.isGranted;
  }

  // 检查后台位置权限
  Future<bool> checkBackgroundLocationPermission() async {
    final status = await Permission.locationAlways.status;
    if (status.isGranted) return true;

    final result = await Permission.locationAlways.request();
    return result.isGranted;
  }

  // 检查通知权限
  Future<bool> checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  // 检查是否所有必要权限都已获得
  Future<bool> hasAllEssentialPermissions() async {
    final microphone = await Permission.microphone.isGranted;
    final storage = await Permission.storage.isGranted;
    return microphone && storage;
  }

  // 打开应用设置
  Future<void> openAppSettings() async {
    await openAppSettings();
  }

  // 显示权限解释对话框
  Future<bool> showPermissionExplanation(
    BuildContext context,
    String title,
    String content,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('拒绝'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('允许'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // 请求所有必要权限（带解释）
  Future<bool> requestAllPermissions(BuildContext context) async {
    // 麦克风权限解释
    final micAllowed = await showPermissionExplanation(
      context,
      '需要麦克风权限',
      'MemoryPal需要访问您的麦克风来录制音频，以便记录您的生活和工作信息。录音仅在您授权的情况下进行。',
    );
    if (!micAllowed) return false;

    final micGranted = await checkMicrophonePermission();
    if (!micGranted) {
      _showPermissionDeniedDialog(context, '麦克风');
      return false;
    }

    // 存储权限解释
    final storageAllowed = await showPermissionExplanation(
      context,
      '需要存储权限',
      'MemoryPal需要访问存储来保存录音文件和相关数据。',
    );
    if (!storageAllowed) return false;

    final storageGranted = await checkStoragePermission();
    if (!storageGranted) {
      _showPermissionDeniedDialog(context, '存储');
      return false;
    }

    // 位置权限（可选）
    final locationAllowed = await showPermissionExplanation(
      context,
      '需要位置权限（可选）',
      'MemoryPal可以记录位置信息来帮助您回忆当时的情境。此功能完全可选，不会影响核心功能。',
    );
    if (locationAllowed) {
      await checkLocationPermission();
    }

    // 通知权限（可选）
    final notificationAllowed = await showPermissionExplanation(
      context,
      '需要通知权限（可选）',
      'MemoryPal需要发送通知来提醒您待办事项和重要信息。',
    );
    if (notificationAllowed) {
      await checkNotificationPermission();
    }

    return true;
  }

  void _showPermissionDeniedDialog(BuildContext context, String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionName权限被拒绝'),
        content: Text('您拒绝了$permissionName权限，这会影响MemoryPal的正常使用。请在设置中手动开启。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
