import 'dart:convert';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/todo_list_screen.dart';
import '../screens/recording_list_screen.dart';
import '../screens/recording_detail_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../models/recording.dart';
import 'database_service.dart';

/// 通知路由处理器
///
/// 处理通知点击后的页面跳转
/// 支持格式：
/// - todo: 打开待办列表
/// - recording:id 打开录音播放页
/// - chat: 打开AI对话
/// - settings: 打开设置
/// - proactive:type 处理主动消息
class NotificationRouter {
  static final NotificationRouter _instance = NotificationRouter._internal();
  factory NotificationRouter() => _instance;
  NotificationRouter._internal();

  final DatabaseService _databaseService = DatabaseService();

  GlobalKey<NavigatorState>? _navigatorKey;

  /// 设置导航键
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 处理通知点击
  Future<void> handleNotificationTap(String payload) async {
    debugPrint('通知路由: 处理payload = $payload');

    if (_navigatorKey?.currentState == null) {
      debugPrint('通知路由: 导航器未就绪');
      return;
    }

    final navigator = _navigatorKey!.currentState!;

    // 解析payload
    final parts = payload.split(':');
    final type = parts[0];
    final id = parts.length > 1 ? parts[1] : null;

    switch (type) {
      case 'todo':
        await _navigateToTodoList(navigator);
        break;

      case 'recording':
        if (id != null) {
          await _navigateToRecordingPlayer(navigator, int.tryParse(id));
        } else {
          await _navigateToRecordingList(navigator);
        }
        break;

      case 'chat':
        await _navigateToChat(navigator);
        break;

      case 'settings':
        await _navigateToSettings(navigator);
        break;

      case 'proactive':
        await _handleProactiveMessage(navigator, id);
        break;

      case 'daily_summary':
        await _navigateToDailySummary(navigator);
        break;

      default:
        debugPrint('通知路由: 未知类型 $type');
        await _navigateToHome(navigator);
    }
  }

  /// 跳转到待办列表
  Future<void> _navigateToTodoList(NavigatorState navigator) async {
    // 先返回首页
    navigator.popUntil((route) => route.isFirst);

    // 延迟后跳转，确保首页已加载
    await Future.delayed(const Duration(milliseconds: 100));

    navigator.push(
      MaterialPageRoute(
        builder: (context) => const TodoListScreen(),
      ),
    );
  }

  /// 跳转到录音列表
  Future<void> _navigateToRecordingList(NavigatorState navigator) async {
    navigator.popUntil((route) => route.isFirst);

    await Future.delayed(const Duration(milliseconds: 100));

    navigator.push(
      MaterialPageRoute(
        builder: (context) => const RecordingListScreen(),
      ),
    );
  }

  /// 跳转到录音播放页
  Future<void> _navigateToRecordingPlayer(
    NavigatorState navigator,
    int? recordingId,
  ) async {
    if (recordingId == null) {
      await _navigateToRecordingList(navigator);
      return;
    }

    // 获取录音信息
    final recordings = await _databaseService.getRecordings(limit: 1000);
    final recording = recordings.firstWhere(
      (r) => r.id == recordingId,
      orElse: () => null as Recording,
    );

    if (recording == null) {
      await _navigateToRecordingList(navigator);
      return;
    }

    navigator.popUntil((route) => route.isFirst);

    await Future.delayed(const Duration(milliseconds: 100));

    navigator.push(
      MaterialPageRoute(
        builder: (context) => RecordingDetailScreen(recording: recording),
      ),
    );
  }

  /// 跳转到AI对话
  Future<void> _navigateToChat(NavigatorState navigator) async {
    navigator.popUntil((route) => route.isFirst);

    await Future.delayed(const Duration(milliseconds: 100));

    navigator.push(
      MaterialPageRoute(
        builder: (context) => const ChatScreen(),
      ),
    );
  }

  /// 跳转到设置
  Future<void> _navigateToSettings(NavigatorState navigator) async {
    navigator.popUntil((route) => route.isFirst);

    await Future.delayed(const Duration(milliseconds: 100));

    navigator.push(
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  /// 跳转到首页
  Future<void> _navigateToHome(NavigatorState navigator) async {
    navigator.popUntil((route) => route.isFirst);
  }

  /// 跳转到每日摘要
  Future<void> _navigateToDailySummary(NavigatorState navigator) async {
    navigator.popUntil((route) => route.isFirst);

    // 可以在首页显示一个摘要对话框或卡片
    // 暂时跳转到首页
  }

  /// 处理主动消息
  Future<void> _handleProactiveMessage(
    NavigatorState navigator,
    String? subtype,
  ) async {
    switch (subtype) {
      case 'morningGreeting':
      case 'eveningSummary':
      case 'goalReminder':
      case 'emotionalCheck':
        // 主动消息都打开AI对话
        await _navigateToChat(navigator);
        break;

      case 'habitPrompt':
        // 习惯提醒打开录音页面
        await _navigateToRecordingList(navigator);
        break;

      case 'importantDate':
        await _navigateToTodoList(navigator);
        break;

      default:
        await _navigateToHome(navigator);
    }
  }
}

/// 通知payload构建器
class NotificationPayloadBuilder {
  static String todo() => 'todo';

  static String recording([int? id]) => id != null ? 'recording:$id' : 'recording';

  static String chat() => 'chat';

  static String settings() => 'settings';

  static String proactive(String type) => 'proactive:$type';

  static String dailySummary() => 'daily_summary';
}
