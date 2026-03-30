import 'dart:async';
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'database_service.dart';

/// 定时任务调度器
/// 管理应用的定时任务，包括每日摘要、智能提醒等
class SchedulerService {
  static final SchedulerService _instance = SchedulerService._internal();
  factory SchedulerService() => _instance;
  SchedulerService._internal();

  final NotificationService _notificationService = NotificationService();
  final DatabaseService _databaseService = DatabaseService();

  Timer? _dailyTimer;
  Timer? _hourlyTimer;
  bool _initialized = false;

  /// 初始化调度器
  Future<void> initialize() async {
    if (_initialized) return;

    await _notificationService.initialize();
    _setupTimers();

    _initialized = true;
    debugPrint('SchedulerService 初始化完成');
  }

  /// 设置定时器
  void _setupTimers() {
    // 每小时检查一次待办提醒
    _hourlyTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkTodoReminders();
    });

    // 每天早上8点发送每日摘要
    _scheduleDailySummary();

    // 立即执行一次检查
    _checkTodoReminders();
  }

  /// 安排每日摘要
  void _scheduleDailySummary() {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, 8, 0); // 早上8点

    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final delay = scheduledTime.difference(now);

    Timer(delay, () async {
      await _sendDailySummary();
      // 安排明天的摘要
      _dailyTimer = Timer.periodic(const Duration(days: 1), (_) {
        _sendDailySummary();
      });
    });
  }

  /// 发送每日摘要
  Future<void> _sendDailySummary() async {
    try {
      final todos = await _databaseService.getTodos();
      final pendingTodos = todos.where((t) => t['is_completed'] == 0).toList();

      final recordings = await _databaseService.getRecordings(limit: 100);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final recentRecordings = recordings.where((r) => r.startTime.isAfter(yesterday)).toList();

      final notes = await _databaseService.getNotes(limit: 100);
      final recentNotes = notes.where((n) => n.createdAt.isAfter(yesterday)).toList();

      final summary = StringBuffer();
      summary.writeln('昨日回顾');
      summary.writeln('• ${recentRecordings.length} 条录音');
      summary.writeln('• ${recentNotes.length} 条笔记');
      summary.writeln('');
      summary.writeln('今日待办 (${pendingTodos.length})');

      if (pendingTodos.isNotEmpty) {
        for (var i = 0; i < pendingTodos.take(3).length; i++) {
          summary.writeln('• ${pendingTodos[i]['content']}');
        }
        if (pendingTodos.length > 3) {
          summary.writeln('...还有 ${pendingTodos.length - 3} 项');
        }
      } else {
        summary.writeln('今天没有待办事项');
      }

      await _notificationService.showDailySummary(
        id: 1000,
        summary: summary.toString(),
      );
    } catch (e) {
      debugPrint('发送每日摘要失败: $e');
    }
  }

  /// 检查待办提醒
  Future<void> _checkTodoReminders() async {
    try {
      final now = DateTime.now();
      final oneHourLater = now.add(const Duration(hours: 1));

      final todos = await _databaseService.getTodos();
      final pendingTodos = todos.where((t) => t['is_completed'] == 0).toList();

      for (final todo in pendingTodos) {
        final deadline = todo['deadline'] as int?;
        if (deadline != null) {
          final deadlineDate = DateTime.fromMillisecondsSinceEpoch(deadline);
          if (deadlineDate.isAfter(now) && deadlineDate.isBefore(oneHourLater)) {
            await _notificationService.showTodoReminder(
              id: 2000 + (todo['id'] as int),
              title: '待办提醒',
              content: todo['content'] as String,
              payload: 'todo:${todo['id']}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('检查待办提醒失败: $e');
    }
  }

  /// 安排一次性提醒
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    await _notificationService.scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledTime,
    );
  }

  /// 取消提醒
  Future<void> cancelReminder(int id) async {
    await _notificationService.cancelNotification(id);
  }

  /// 停止所有定时器
  void dispose() {
    _dailyTimer?.cancel();
    _hourlyTimer?.cancel();
    _dailyTimer = null;
    _hourlyTimer = null;
  }
}
