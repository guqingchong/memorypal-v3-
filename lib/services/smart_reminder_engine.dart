import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../models/note.dart';
import '../models/user_profile.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// 智能提醒引擎
/// 基于用户上下文、习惯和AI分析生成个性化提醒
class SmartReminderEngine {
  static final SmartReminderEngine _instance = SmartReminderEngine._internal();
  factory SmartReminderEngine() => _instance;
  SmartReminderEngine._internal();

  final DatabaseService _databaseService = DatabaseService();
  final NotificationService _notificationService = NotificationService();

  bool _initialized = false;
  Timer? _contextCheckTimer;

  // 上下文状态
  DateTime? _lastActivityTime;
  String? _lastLocation;
  int _consecutiveChecksWithoutActivity = 0;

  /// 初始化引擎
  Future<void> initialize() async {
    if (_initialized) return;

    // 每30分钟检查一次上下文
    _contextCheckTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _analyzeContextAndRemind();
    });

    _initialized = true;
    debugPrint('SmartReminderEngine 初始化完成');
  }

  /// 分析上下文并生成提醒
  Future<void> _analyzeContextAndRemind() async {
    try {
      final profile = await _databaseService.getUserProfile();
      if (profile == null) return;

      final now = DateTime.now();
      final hour = now.hour;

      // 根据时间和用户习惯生成不同类型的提醒
      if (hour >= 9 && hour <= 18) {
        await _checkWorkHoursContext(profile, now);
      } else if (hour >= 19 && hour <= 22) {
        await _checkEveningContext(profile, now);
      } else if (hour >= 7 && hour <= 9) {
        await _checkMorningContext(profile, now);
      }

      // 检查是否有重要待办
      await _checkUrgentTodos();

      // 分析录音和笔记中的潜在待办
      await _analyzeForImplicitTodos();

    } catch (e) {
      debugPrint('上下文分析失败: $e');
    }
  }

  /// 工作时段上下文检查
  Future<void> _checkWorkHoursContext(UserProfile profile, DateTime now) async {
    // 检查今日待办
    final todos = await _databaseService.getTodos();
    final pendingTodos = todos.where((t) => t['is_completed'] == 0).toList();

    if (pendingTodos.isNotEmpty && now.hour == 9) {
      await _notificationService.showAISuggestion(
        id: 5001,
        title: '早晨准备',
        suggestion: '您今天有 ${pendingTodos.length} 项待办，建议先查看待办清单',
      );
    }
  }

  /// 晚间上下文检查
  Future<void> _checkEveningContext(UserProfile profile, DateTime now) async {
    // 检查今日是否有未完成的待办
    final todos = await _databaseService.getTodos();
    final pendingTodos = todos.where((t) => t['is_completed'] == 0).toList();

    if (pendingTodos.isNotEmpty) {
      await _notificationService.showAISuggestion(
        id: 5002,
        title: '晚间回顾',
        suggestion: '今天还有 ${pendingTodos.length} 项待办未完成，建议花10分钟整理一下',
      );
    }

    // 建议记录今日反思
    if (profile.habits.isNotEmpty) {
      final today = DateTime(now.year, now.month, now.day);
      final recordings = await _databaseService.getRecordings(limit: 50);
      final todayRecordings = recordings.where(
        (r) => r.startTime.isAfter(today),
      ).toList();

      if (todayRecordings.isEmpty) {
        await _notificationService.showAISuggestion(
          id: 5003,
          title: '今日反思',
          suggestion: '今天还没有记录任何想法，花几分钟记录一下吧',
        );
      }
    }
  }

  /// 早晨上下文检查
  Future<void> _checkMorningContext(UserProfile profile, DateTime now) async {
    // 检查昨日是否有遗漏
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStart = DateTime(yesterday.year, yesterday.month, yesterday.day);
    final yesterdayEnd = DateTime(now.year, now.month, now.day);

    final recordings = await _databaseService.getRecordings(limit: 50);
    final yesterdayRecordings = recordings.where(
      (r) => r.startTime.isAfter(yesterdayStart) && r.startTime.isBefore(yesterdayEnd),
    ).toList();

    if (yesterdayRecordings.any((r) => r.transcript != null && r.transcript!.contains('待办'))) {
      await _notificationService.showAISuggestion(
        id: 5004,
        title: '昨日回顾',
        suggestion: '昨天提到了一些待办事项，已帮您整理到待办列表',
      );
    }
  }

  /// 检查紧急待办
  Future<void> _checkUrgentTodos() async {
    final now = DateTime.now();
    final todos = await _databaseService.getTodos();
    final pendingTodos = todos.where((t) => t['is_completed'] == 0).toList();

    for (final todo in pendingTodos) {
      final deadline = todo['deadline'] as int?;
      if (deadline != null) {
        final deadlineDate = DateTime.fromMillisecondsSinceEpoch(deadline);
        if (deadlineDate.difference(now).inHours <= 2 && deadlineDate.isAfter(now)) {
          await _notificationService.showTodoReminder(
            id: 6000 + (todo['id'] as int),
            title: '紧急待办',
            content: '"${todo['content']}" 即将到期',
            payload: 'todo:${todo['id']}',
          );
        }
      }
    }
  }

  /// 分析录音和笔记中的潜在待办
  Future<void> _analyzeForImplicitTodos() async {
    try {
      final recentRecordings = await _databaseService.getRecordings(limit: 5);

      // 关键词检测（简化版，实际应使用NLP）
      final todoKeywords = [
        '记得', '需要', '应该', '必须', '别忘了',
        '要做', '待办', '任务', '安排', '计划'
      ];

      for (final recording in recentRecordings) {
        if (recording.transcript == null) continue;

        for (final keyword in todoKeywords) {
          if (recording.transcript!.contains(keyword)) {
            // 建议创建待办
            final snippet = _extractSnippet(recording.transcript!, keyword);
            await _notificationService.showAISuggestion(
              id: 7000 + (recording.id ?? 0),
              title: '发现可能的待办',
              suggestion: '您在录音中提到: "$snippet..." 需要创建待办吗？',
              payload: 'recording:${recording.id}',
            );
            break; // 每条录音只提醒一次
          }
        }
      }
    } catch (e) {
      debugPrint('分析潜在待办失败: $e');
    }
  }

  /// 提取文本片段
  String _extractSnippet(String text, String keyword) {
    final index = text.indexOf(keyword);
    if (index == -1) return text;

    final start = max(0, index - 10);
    final end = min(text.length, index + keyword.length + 20);
    return text.substring(start, end);
  }

  /// 手动触发上下文分析（用于测试）
  Future<void> triggerAnalysis() async {
    await _analyzeContextAndRemind();
  }

  /// 记录用户活动
  void recordActivity(String type, {String? location}) {
    _lastActivityTime = DateTime.now();
    if (location != null) _lastLocation = location;
    _consecutiveChecksWithoutActivity = 0;
  }

  /// 停止引擎
  void dispose() {
    _contextCheckTimer?.cancel();
    _contextCheckTimer = null;
  }
}
