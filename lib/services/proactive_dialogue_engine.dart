import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'database_extension.dart';
import 'profile_evolution_engine.dart';
import 'notification_service.dart';
import 'notification_router.dart';
import 'kimi_service.dart';
import '../models/user_profile.dart';

/// 主动对话引擎 - 让AI主动与用户互动
///
/// 核心功能：
/// 1. 定时检查触发条件
/// 2. 生成主动消息
/// 3. 管理对话时机（不打扰用户）
/// 4. 预测用户需求并提前准备
///
/// 参考Claudecode的Coordinator模式和主动触发机制
class ProactiveDialogueEngine {
  static final ProactiveDialogueEngine _instance = ProactiveDialogueEngine._internal();
  factory ProactiveDialogueEngine() => _instance;
  ProactiveDialogueEngine._internal();

  final DatabaseService _databaseService = DatabaseService();
  final ProfileEvolutionEngine _evolutionEngine = ProfileEvolutionEngine();
  final NotificationService _notificationService = NotificationService();
  final KimiService _kimiService = KimiService();

  // 定时器
  Timer? _checkTimer;
  Timer? _morningGreetingTimer;
  Timer? _eveningSummaryTimer;

  // 状态
  bool _isEngineRunning = false;
  DateTime? _lastProactiveMessage;
  UserProfile? _userProfile;

  // 配置
  static const int _minHoursBetweenMessages = 4; // 最少间隔4小时
  static const int _maxDailyMessages = 5; // 每天最多主动消息数

  /// 初始化引擎
  Future<void> initialize() async {
    if (_isEngineRunning) return;

    _userProfile = await _databaseService.getUserProfile();

    // 设置定时检查（每30分钟）
    _checkTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _checkAndTriggerProactiveEngagement();
    });

    // 设置早上问候
    _scheduleMorningGreeting();

    // 设置晚间总结
    _scheduleEveningSummary();

    _isEngineRunning = true;
    debugPrint('主动对话引擎已启动');
  }

  /// 停止引擎
  void dispose() {
    _checkTimer?.cancel();
    _morningGreetingTimer?.cancel();
    _eveningSummaryTimer?.cancel();
    _isEngineRunning = false;
  }

  /// 检查并触发主动互动
  Future<void> _checkAndTriggerProactiveEngagement() async {
    if (!_shouldTriggerNow()) return;

    // 获取主动建议
    final suggestions = await _evolutionEngine.analyzeForProactiveEngagement();

    if (suggestions.isEmpty) return;

    // 只处理高优先级建议
    final highPriority = suggestions
        .where((s) => s.priority == SuggestionPriority.high ||
            s.priority == SuggestionPriority.urgent)
        .toList();

    if (highPriority.isNotEmpty) {
      await _sendProactiveMessage(highPriority.first);
    }
  }

  /// 生成早上问候
  Future<void> _generateMorningGreeting() async {
    final profile = await _databaseService.getUserProfile();
    final name = profile?.name ?? '';

    // 获取今日概览
    final todaySummary = await _getTodaySummary();

    // 获取今日待办
    final todos = await _databaseService.getTodos();
    final pendingTodos = todos.where((t) => t['is_completed'] == 0).toList();

    String greeting;

    if (_kimiService.isAvailable) {
      // 使用AI生成个性化问候
      final context = _buildMorningContext(profile, todaySummary, pendingTodos);
      final aiGreeting = await _kimiService.askQuestion(
        '生成一个温暖的早上问候语，基于以下用户上下文：\n$context',
        enableTools: false,
      );
      greeting = aiGreeting ?? _generateDefaultMorningGreeting(name, pendingTodos);
    } else {
      greeting = _generateDefaultMorningGreeting(name, pendingTodos);
    }

    await _sendProactiveNotification(
      title: '早上好${name.isNotEmpty ? '，$name' : ''}',
      body: greeting,
      type: ProactiveMessageType.morningGreeting,
    );
  }

  /// 生成晚间总结
  Future<void> _generateEveningSummary() async {
    final profile = await _databaseService.getUserProfile();
    final name = profile?.name ?? '';

    // 获取今日记录
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final recordings = await _databaseService.getRecordings(limit: 100);
    final todayRecordings = recordings
        .where((r) => r.startTime.isAfter(startOfDay))
        .toList();

    final notes = await _databaseService.getNotes(limit: 100);
    final todayNotes = notes
        .where((n) => n.createdAt.isAfter(startOfDay))
        .toList();

    final completedTodos = (await _databaseService.getTodos())
        .where((t) => t['is_completed'] == 1)
        .where((t) {
          final completedAt = t['completed_at'] as int?;
          if (completedAt == null) return false;
          return DateTime.fromMillisecondsSinceEpoch(completedAt)
              .isAfter(startOfDay);
        })
        .toList();

    String summary;

    if (_kimiService.isAvailable) {
      final context = '''今日记录：
- 录音：${todayRecordings.length}条
- 笔记：${todayNotes.length}条
- 完成待办：${completedTodos.length}项''';

      final aiSummary = await _kimiService.askQuestion(
        '基于今日活动生成温暖晚间总结和鼓励：\n$context',
        enableTools: false,
      );
      summary = aiSummary ?? _generateDefaultEveningSummary(
        todayRecordings.length,
        todayNotes.length,
        completedTodos.length,
      );
    } else {
      summary = _generateDefaultEveningSummary(
        todayRecordings.length,
        todayNotes.length,
        completedTodos.length,
      );
    }

    await _sendProactiveNotification(
      title: '今日回顾',
      body: summary,
      type: ProactiveMessageType.eveningSummary,
    );
  }

  /// 发送主动消息
  Future<void> _sendProactiveMessage(ProactiveSuggestion suggestion) async {
    final message = await _generateProactiveMessage(suggestion);

    await _sendProactiveNotification(
      title: suggestion.title,
      body: message,
      type: _mapSuggestionType(suggestion.type),
    );

    _lastProactiveMessage = DateTime.now();

    // 记录主动消息
    await _databaseService.insertProactiveMessage({
      'type': suggestion.type.name,
      'title': suggestion.title,
      'content': message,
      'priority': suggestion.priority.name,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  /// 生成主动消息内容
  Future<String> _generateProactiveMessage(ProactiveSuggestion suggestion) async {
    return suggestion.content;
  }

  /// 发送主动通知
  Future<void> _sendProactiveNotification({
    required String title,
    required String body,
    required ProactiveMessageType type,
  }) async {
    await _notificationService.showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: NotificationPayloadBuilder.proactive(type.name),
    );
  }

  /// 发送主动通知

  /// 判断是否应该现在触发
  bool _shouldTriggerNow() {
    // 检查是否在活跃时段（避免深夜打扰）
    final hour = DateTime.now().hour;
    if (hour < 8 || hour > 22) return false;

    // 检查距离上次主动消息的时间
    if (_lastProactiveMessage != null) {
      final hoursSince = DateTime.now()
          .difference(_lastProactiveMessage!)
          .inHours;
      if (hoursSince < _minHoursBetweenMessages) return false;
    }

    // 检查今日消息数量
    // TODO: 查询今日已发送的主动消息数

    return true;
  }

  /// 安排早上问候
  void _scheduleMorningGreeting() {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, 8, 30);

    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final delay = scheduledTime.difference(now);

    _morningGreetingTimer = Timer(delay, () async {
      await _generateMorningGreeting();
      // 安排明天的问候
      _scheduleMorningGreeting();
    });
  }

  /// 安排晚间总结
  void _scheduleEveningSummary() {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, 21, 0);

    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final delay = scheduledTime.difference(now);

    _eveningSummaryTimer = Timer(delay, () async {
      await _generateEveningSummary();
      // 安排明天的总结
      _scheduleEveningSummary();
    });
  }

  /// 获取今日概览
  Future<Map<String, dynamic>> _getTodaySummary() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final recordings = await _databaseService.getRecordings(limit: 100);
    final todayRecordings = recordings
        .where((r) => r.startTime.isAfter(startOfDay))
        .toList();

    return {
      'recordings': todayRecordings.length,
      'totalDuration': todayRecordings.fold<int>(
        0,
        (sum, r) => sum + r.durationSeconds,
      ),
    };
  }

  /// 构建早上问候上下文
  String _buildMorningContext(
    UserProfile? profile,
    Map<String, dynamic> todaySummary,
    List<Map<String, dynamic>> pendingTodos,
  ) {
    final buffer = StringBuffer();

    if (profile?.occupation != null) {
      buffer.writeln('用户职业：${profile!.occupation}');
    }

    if (profile?.shortTermGoals != null) {
      buffer.writeln('当前目标：${profile!.shortTermGoals}');
    }

    buffer.writeln('今日录音：${todaySummary['recordings']}条');
    buffer.writeln('待办事项：${pendingTodos.length}项');

    return buffer.toString();
  }

  /// 生成默认早上问候
  String _generateDefaultMorningGreeting(
    String name,
    List<Map<String, dynamic>> pendingTodos,
  ) {
    final greetings = [
      '新的一天开始了！准备好迎接挑战了吗？',
      '今天也要元气满满哦！',
      '早安！记得记录今天的精彩想法。',
      '新的一天，新的可能！',
    ];

    final random = Random().nextInt(greetings.length);
    var greeting = greetings[random];

    if (pendingTodos.isNotEmpty) {
      greeting += '\n今天有 ${pendingTodos.length} 项待办等你完成。';
    }

    return greeting;
  }

  /// 生成默认晚间总结
  String _generateDefaultEveningSummary(
    int recordings,
    int notes,
    int completedTodos,
  ) {
    if (recordings == 0 && notes == 0 && completedTodos == 0) {
      return '今天似乎没有新的记录。明天记得多用语音笔记记录想法哦！';
    }

    final buffer = StringBuffer();
    buffer.write('今天你很棒！\n');

    if (recordings > 0) {
      buffer.write('记录了 $recordings 条想法');
    }

    if (notes > 0) {
      if (recordings > 0) buffer.write('，');
      buffer.write('写了 $notes 条笔记');
    }

    if (completedTodos > 0) {
      if (recordings > 0 || notes > 0) buffer.write('，');
      buffer.write('完成了 $completedTodos 项待办');
    }

    buffer.write('。\n早点休息，明天见！');

    return buffer.toString();
  }

  ProactiveMessageType _mapSuggestionType(SuggestionType type) {
    switch (type) {
      case SuggestionType.goalDeadline:
        return ProactiveMessageType.goalReminder;
      case SuggestionType.emotionalSupport:
        return ProactiveMessageType.emotionalCheck;
      case SuggestionType.habitReminder:
        return ProactiveMessageType.habitPrompt;
      case SuggestionType.importantDate:
        return ProactiveMessageType.importantDate;
      case SuggestionType.insight:
        return ProactiveMessageType.insight;
    }
  }
}

/// 主动消息类型
enum ProactiveMessageType {
  morningGreeting,    // 早上问候
  eveningSummary,     // 晚间总结
  goalReminder,       // 目标提醒
  emotionalCheck,     // 情绪关怀
  habitPrompt,        // 习惯提醒
  importantDate,      // 重要日期
  insight,            // 洞察分享
}
