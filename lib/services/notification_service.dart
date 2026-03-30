import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// 通知服务
/// 管理本地通知，包括待办提醒、每日摘要、AI建议等
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // 通知点击回调
  Function(String payload)? onNotificationTap;

  /// 初始化通知服务
  Future<void> initialize() async {
    if (_initialized) return;

    // 初始化时区数据
    tz_data.initializeTimeZones();

    // Android初始化设置
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS初始化设置
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response.payload ?? '');
      },
    );

    // 创建通知渠道（Android 8.0+）
    await _createNotificationChannels();

    _initialized = true;
  }

  /// 创建通知渠道
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // 待办提醒渠道
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'todo_reminders',
          '待办提醒',
          description: '重要待办事项的提醒通知',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // AI建议渠道
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'ai_suggestions',
          'AI建议',
          description: '基于您习惯的智能建议',
          importance: Importance.defaultImportance,
          playSound: true,
        ),
      );

      // 每日摘要渠道
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'daily_summary',
          '每日摘要',
          description: '每日记忆摘要推送',
          importance: Importance.defaultImportance,
        ),
      );

      // 事项追踪渠道
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'item_tracking',
          '事项追踪',
          description: '事项进展和停滞提醒',
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  /// 显示待办提醒
  Future<void> showTodoReminder({
    required int id,
    required String title,
    required String content,
    String? payload,
  }) async {
    await _showNotification(
      id: id,
      title: '🔔 待办提醒',
      body: '$title\n$content',
      channelId: 'todo_reminders',
      importance: Importance.high,
      payload: payload,
    );
  }

  /// 显示AI建议
  Future<void> showAISuggestion({
    required int id,
    required String title,
    required String suggestion,
    String? payload,
  }) async {
    await _showNotification(
      id: id,
      title: '💡 助理建议',
      body: '$title\n$suggestion',
      channelId: 'ai_suggestions',
      importance: Importance.defaultImportance,
      payload: payload,
    );
  }

  /// 显示每日摘要
  Future<void> showDailySummary({
    required int id,
    required String summary,
  }) async {
    await _showNotification(
      id: id,
      title: '📋 今日记忆摘要',
      body: summary,
      channelId: 'daily_summary',
      importance: Importance.defaultImportance,
      style: BigTextStyleInformation(summary),
    );
  }

  /// 显示事项追踪提醒
  Future<void> showItemTracking({
    required int id,
    required String itemName,
    required String message,
    String? payload,
  }) async {
    await _showNotification(
      id: id,
      title: '📋 事项更新',
      body: '"$itemName"$message',
      channelId: 'item_tracking',
      importance: Importance.defaultImportance,
      payload: payload,
    );
  }

  /// 安排定时通知
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String channelId = 'todo_reminders',
    String? payload,
  }) async {
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _getChannelName(channelId),
          channelDescription: _getChannelDescription(channelId),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// 显示通知的基础方法
  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    Importance importance = Importance.defaultImportance,
    StyleInformation? style,
    String? payload,
  }) async {
    await _notifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _getChannelName(channelId),
          channelDescription: _getChannelDescription(channelId),
          importance: importance,
          priority: importance == Importance.high ? Priority.high : Priority.defaultPriority,
          styleInformation: style,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// 取消特定通知
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// 获取渠道名称
  String _getChannelName(String channelId) {
    switch (channelId) {
      case 'todo_reminders':
        return '待办提醒';
      case 'ai_suggestions':
        return 'AI建议';
      case 'daily_summary':
        return '每日摘要';
      case 'item_tracking':
        return '事项追踪';
      default:
        return '通知';
    }
  }

  /// 获取渠道描述
  String _getChannelDescription(String channelId) {
    switch (channelId) {
      case 'todo_reminders':
        return '重要待办事项的提醒通知';
      case 'ai_suggestions':
        return '基于您习惯的智能建议';
      case 'daily_summary':
        return '每日记忆摘要推送';
      case 'item_tracking':
        return '事项进展和停滞提醒';
      default:
        return '应用通知';
    }
  }
}
