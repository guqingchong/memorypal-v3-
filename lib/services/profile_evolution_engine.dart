import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'database_extension.dart';
import 'agent_service.dart';
import 'kimi_service.dart';
import 'emotion_analysis_service.dart';
import '../models/user_profile.dart';

/// 用户画像进化引擎 - 长期学习用户
///
/// 核心功能：
/// 1. 从每次对话中提取画像更新
/// 2. 自动分析行为模式
/// 3. 识别用户情绪状态变化
/// 4. 学习目标完成进度
/// 5. 发现新兴趣点和生活变化
///
/// 参考Claudecode的Auto-Memory系统设计
class ProfileEvolutionEngine {
  static final ProfileEvolutionEngine _instance = ProfileEvolutionEngine._internal();
  factory ProfileEvolutionEngine() => _instance;
  ProfileEvolutionEngine._internal();

  final DatabaseService _databaseService = DatabaseService();
  final KimiService _kimiService = KimiService();

  // 学习队列（避免频繁更新）
  final List<LearningEvent> _learningQueue = [];
  Timer? _learningTimer;

  // 进化配置
  static const int _minConversationsBeforeEvolve = 3; // 至少3次对话后开始进化
  static const int _evolutionCooldownHours = 24; // 画像更新冷却时间

  /// 初始化进化引擎
  void initialize() {
    // 每小时检查一次是否有待处理的学习事件
    _learningTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _processLearningQueue();
    });
  }

  /// 记录对话事件用于学习
  ///
  /// 在每次AI对话后调用，让引擎从对话中学习
  Future<void> recordConversation({
    required String userMessage,
    required String aiResponse,
    required List<ToolCall> toolCalls,
  }) async {
    final event = LearningEvent(
      type: LearningEventType.conversation,
      timestamp: DateTime.now(),
      data: {
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
      },
    );

    _learningQueue.add(event);

    // 立即分析高价值对话（涉及画像相关话题）
    if (_isHighValueConversation(userMessage)) {
      await _analyzeAndEvolve(event);
    }
  }

  /// 记录用户行为事件
  ///
  /// 如：完成待办、播放录音、创建笔记等
  Future<void> recordBehavior({
    required BehaviorType type,
    required Map<String, dynamic> metadata,
  }) async {
    final event = LearningEvent(
      type: LearningEventType.behavior,
      timestamp: DateTime.now(),
      data: {
        'behaviorType': type.name,
        'metadata': metadata,
      },
    );

    _learningQueue.add(event);

    // 关键行为立即分析
    if (_isKeyBehavior(type)) {
      await _analyzeBehaviorPattern(event);
    }
  }

  /// 分析单个行为模式
  Future<void> _analyzeBehaviorPattern(LearningEvent event) async {
    // 简化实现，直接记录行为
    final type = event.data['behaviorType'] as String? ?? 'unknown';
    await _recordBehaviorPattern(type, 1);
  }

  final EmotionAnalysisService _emotionAnalysis = EmotionAnalysisService();

  /// 记录情绪状态
  ///
  /// 用于追踪用户情绪波动
  Future<void> recordEmotionalState({
    required EmotionalState state,
    required String source, // 'conversation', 'voice_analysis', 'manual'
    String? context,
  }) async {
    await _databaseService.insertEmotionalState({
      'state': state.name,
      'source': source,
      'context': context,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // 如果检测到显著情绪变化，触发特殊处理
    final previousState = await _getPreviousEmotionalState();
    if (previousState != null && _isSignificantChange(previousState, state)) {
      await _handleSignificantEmotionalChange(previousState, state, context);
    }
  }

  /// 分析文本并记录情绪
  ///
  /// 使用情绪分析服务从文本中提取情绪
  Future<EmotionAnalysisResult> analyzeAndRecordEmotion(
    String text, {
    String source = 'conversation',
    String? context,
  }) async {
    _emotionAnalysis.initialize();

    // 分析文本情绪
    final result = _emotionAnalysis.analyze(text);

    // 转换为EmotionalState
    final emotionalState = _mapToEmotionalState(result.primaryEmotion);

    // 记录到数据库
    await _databaseService.insertEmotionalState({
      'state': emotionalState.name,
      'source': source,
      'context': context ?? text.substring(0, text.length > 50 ? 50 : text.length),
      'intensity': result.intensity,
      'confidence': result.confidence,
      'all_emotions': jsonEncode(result.allEmotions.map(
        (k, v) => MapEntry(k.name, v),
      )),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // 检测情绪变化
    final previousResult = await _getPreviousEmotionAnalysis();
    if (previousResult != null) {
      final change = _emotionAnalysis.detectChange(previousResult, result);

      if (change.isSignificant) {
        debugPrint('检测到显著情绪变化: ${change.fromEmotion} -> ${change.toEmotion}');
        await _handleEmotionChange(change, result);
      }
    }

    return result;
  }

  /// 处理情绪变化
  Future<void> _handleEmotionChange(EmotionChange change, EmotionAnalysisResult current) async {
    // 正向到负向的显著变化：触发关怀
    if (change.fromEmotion?.isPositive == true && change.toEmotion?.isNegative == true) {
      _triggerEmotionalSupport(current);
    }

    // 负向到正向的显著变化：庆祝
    if (change.fromEmotion?.isNegative == true && change.toEmotion?.isPositive == true) {
      _triggerPositiveReinforcement(current);
    }

    // 情绪强度突然增加
    if (change.type == ChangeType.intensify && current.intensity > 0.7) {
      _triggerIntensityCheck(current);
    }
  }

  void _triggerEmotionalSupport(EmotionAnalysisResult emotion) {
    // 广播情绪支持事件，由ProactiveDialogueEngine处理
    // TODO: 实现事件广播机制
    debugPrint('触发情绪支持: ${emotion.description}');
  }

  void _triggerPositiveReinforcement(EmotionAnalysisResult emotion) {
    debugPrint('触发正向强化: ${emotion.description}');
  }

  void _triggerIntensityCheck(EmotionAnalysisResult emotion) {
    debugPrint('触发强度检查: ${emotion.description}');
  }

  EmotionalState _mapToEmotionalState(EmotionType type) {
    switch (type) {
      case EmotionType.joy:
        return EmotionalState.happy;
      case EmotionType.excitement:
        return EmotionalState.excited;
      case EmotionType.gratitude:
        return EmotionalState.happy;
      case EmotionType.sadness:
        return EmotionalState.sad;
      case EmotionType.anxiety:
        return EmotionalState.anxious;
      case EmotionType.anger:
        return EmotionalState.angry;
      case EmotionType.frustration:
        return EmotionalState.stressed;
      case EmotionType.neutral:
        return EmotionalState.neutral;
    }
  }

  Future<EmotionAnalysisResult?> _getPreviousEmotionAnalysis() async {
    // TODO: 从数据库获取上次的情绪分析结果
    return null;
  }

  /// 主动触发画像进化分析
  ///
  /// 可由定时任务调用，深度分析近期数据
  Future<EvolutionResult?> triggerEvolution() async {
    final profile = await _databaseService.getUserProfile();
    if (profile == null) return null;

    // 检查冷却时间
    final lastEvolution = await _getLastEvolutionTime();
    if (lastEvolution != null) {
      final hoursSince = DateTime.now().difference(lastEvolution).inHours;
      if (hoursSince < _evolutionCooldownHours) {
        debugPrint('画像进化冷却中，还需 ${_evolutionCooldownHours - hoursSince} 小时');
        return null;
      }
    }

    // 获取近期数据
    final recentConversations = await _getRecentConversations(days: 7);
    final recentBehaviors = _learningQueue
        .where((e) => e.timestamp.isAfter(DateTime.now().subtract(const Duration(days: 7))))
        .toList();

    if (recentConversations.length < _minConversationsBeforeEvolve) {
      debugPrint('对话数据不足，暂不进化');
      return null;
    }

    // 使用AI分析进化方向
    return await _analyzeEvolutionPotential(
      profile: profile,
      conversations: recentConversations,
      behaviors: recentBehaviors,
    );
  }

  /// 分析用户当前状态并生成主动建议
  ///
  /// 用于主动对话触发
  Future<List<ProactiveSuggestion>> analyzeForProactiveEngagement() async {
    final suggestions = <ProactiveSuggestion>[];
    final now = DateTime.now();

    // 1. 检查目标截止日期
    final goalSuggestions = await _checkGoalDeadlines(now);
    suggestions.addAll(goalSuggestions);

    // 2. 检测情绪低谷
    final emotionalSuggestions = await _checkEmotionalState();
    suggestions.addAll(emotionalSuggestions);

    // 3. 识别行为模式异常
    const patternSuggestions = <ProactiveSuggestion>[];
    // TODO: 实现行为模式分析
    suggestions.addAll(patternSuggestions);

    // 4. 检测重要日期（生日、纪念日等）
    final dateSuggestions = await _checkImportantDates(now);
    suggestions.addAll(dateSuggestions);

    // 5. 基于习惯的主动提醒
    final habitSuggestions = await _checkHabitPatterns(now);
    suggestions.addAll(habitSuggestions);

    return suggestions..sort((a, b) => b.priority.index - a.priority.index);
  }

  /// 生成用户深度洞察报告
  ///
  /// 用于定期总结和反馈
  Future<InsightReport> generateInsightReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final conversations = await _getConversationsInRange(startDate, endDate);
    final behaviors = await _getBehaviorsInRange(startDate, endDate);
    final emotionalStates = await _getEmotionalStatesInRange(startDate, endDate);

    // 计算关键指标
    final metrics = _calculateMetrics(conversations, behaviors, emotionalStates);

    // 使用AI生成深度洞察
    final aiInsights = await _generateAIInsights(
      conversations: conversations,
      emotionalStates: emotionalStates,
      metrics: metrics,
    );

    return InsightReport(
      period: DateTimeRange(start: startDate, end: endDate),
      metrics: metrics,
      aiInsights: aiInsights,
      suggestedActions: await _generateSuggestedActions(metrics),
    );
  }

  // ==================== 私有方法 ====================

  /// 判断是否为高价值对话
  bool _isHighValueConversation(String message) {
    final keywords = [
      // 目标相关
      '目标', '计划', '想要', '希望', '梦想', '打算',
      // 情绪相关
      '焦虑', '开心', '难过', '压力', '兴奋', '担心',
      // 关系相关
      '家人', '朋友', '同事', '恋爱', '分手', '结婚',
      // 工作相关
      '工作', '项目', '老板', '辞职', '升职', '面试',
      // 生活变化
      '搬家', '旅行', '生病', '健身', '学习', '考试',
    ];

    final lowerMessage = message.toLowerCase();
    return keywords.any((k) => lowerMessage.contains(k));
  }

  /// 判断是否为关键行为
  bool _isKeyBehavior(BehaviorType type) {
    return [
      BehaviorType.completedTodo,
      BehaviorType.createdNote,
      BehaviorType.playedRecording,
      BehaviorType.importedCallRecording,
      BehaviorType.updatedProfile,
    ].contains(type);
  }

  /// 分析对话并进化画像
  Future<void> _analyzeAndEvolve(LearningEvent event) async {
    if (!_kimiService.isAvailable) return;

    final userMessage = event.data['userMessage'] as String;
    final profile = await _databaseService.getUserProfile();
    if (profile == null) return;

    // 构建分析提示词
    final prompt = _buildEvolutionPrompt(profile, userMessage);

    try {
      final response = await _kimiService.askQuestion(
        prompt,
        enableTools: false,
      );

      if (response != null) {
        final updates = _parseEvolutionResponse(response);
        for (final update in updates) {
          await _applyProfileUpdate(update, profile);
        }
      }
    } catch (e) {
      debugPrint('画像进化分析失败: $e');
    }
  }

  /// 构建画像进化分析提示词
  String _buildEvolutionPrompt(UserProfile profile, String userMessage) {
    return '''分析以下用户对话，判断是否需要更新用户画像。

【当前用户画像】
${profile.toMap().entries.where((e) => e.value != null && e.value.toString().isNotEmpty).map((e) => '${e.key}: ${e.value}').join('\n')}

【用户新对话】
$userMessage

请分析这段对话中是否包含以下可更新画像的信息：
1. 新的兴趣点或偏好变化
2. 目标或计划的进展/变化
3. 社交关系的变化
4. 情绪状态或性格特征的体现
5. 生活习惯的变化

只输出需要更新的字段，格式：
field_name|new_value|confidence(0.0-1.0)|reason

如果无更新，输出：NO_UPDATE''';
  }

  /// 解析进化响应
  List<ProfileUpdateCandidate> _parseEvolutionResponse(String response) {
    final updates = <ProfileUpdateCandidate>[];

    if (response.trim() == 'NO_UPDATE') return updates;

    final lines = response.split('\n');
    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length >= 3) {
        updates.add(ProfileUpdateCandidate(
          field: parts[0].trim(),
          value: parts[1].trim(),
          confidence: double.tryParse(parts[2].trim()) ?? 0.5,
          reason: parts.length > 3 ? parts[3].trim() : null,
        ));
      }
    }

    return updates;
  }

  /// 应用画像更新
  Future<void> _applyProfileUpdate(
    ProfileUpdateCandidate update,
    UserProfile profile,
  ) async {
    // 只应用高置信度更新（>0.7）
    if (update.confidence < 0.7) {
      debugPrint('画像更新置信度不足: ${update.field} = ${update.value} (${update.confidence})');
      return;
    }

    // 根据字段类型应用更新
    switch (update.field) {
      case 'interests':
        final newInterests = update.value.split(',').map((s) => s.trim()).toList();
        final currentInterests = profile.interests;
        for (final interest in newInterests) {
          if (!currentInterests.contains(interest)) {
            currentInterests.add(interest);
          }
        }
        profile.updateField('interests', currentInterests, update.confidence);
        break;
      case 'habits':
        final newHabits = update.value.split(',').map((s) => s.trim()).toList();
        final currentHabits = profile.habits;
        for (final habit in newHabits) {
          if (!currentHabits.contains(habit)) {
            currentHabits.add(habit);
          }
        }
        profile.updateField('habits', currentHabits, update.confidence);
        break;
      default:
        profile.updateField(update.field, update.value, update.confidence);
    }

    await _databaseService.saveUserProfile(profile);
    debugPrint('画像已进化: ${update.field} = ${update.value}');

    // 记录进化历史
    await _databaseService.insertEvolutionLog({
      'field': update.field,
      'new_value': update.value,
      'confidence': update.confidence,
      'reason': update.reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 处理学习队列
  Future<void> _processLearningQueue() async {
    if (_learningQueue.isEmpty) return;

    // 批量处理积累的学习事件
    final batch = List<LearningEvent>.from(_learningQueue);
    _learningQueue.clear();

    debugPrint('处理 ${batch.length} 个学习事件');

    // 分析行为模式
    await _analyzeBehaviorPatterns(batch);
  }

  /// 分析行为模式
  Future<void> _analyzeBehaviorPatterns(List<LearningEvent> events) async {
    // 统计各类行为频率
    final behaviorCounts = <String, int>{};
    for (final event in events) {
      if (event.type == LearningEventType.behavior) {
        final type = event.data['behaviorType'] as String;
        behaviorCounts[type] = (behaviorCounts[type] ?? 0) + 1;
      }
    }

    // 检测高频行为模式
    for (final entry in behaviorCounts.entries) {
      if (entry.value >= 5) {
        // 某行为发生5次以上
        await _recordBehaviorPattern(entry.key, entry.value);
      }
    }
  }

  /// 记录行为模式
  Future<void> _recordBehaviorPattern(String behaviorType, int frequency) async {
    await _databaseService.insertBehaviorPattern({
      'pattern_type': behaviorType,
      'frequency': frequency,
      'detected_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 检查目标截止日期
  Future<List<ProactiveSuggestion>> _checkGoalDeadlines(DateTime now) async {
    final suggestions = <ProactiveSuggestion>[];
    final profile = await _databaseService.getUserProfile();

    if (profile?.shortTermGoals != null) {
      // 解析目标中的日期信息
      final goals = profile!.shortTermGoals!.split('\n');
      for (final goal in goals) {
        // 简单日期检测
        final dateMatch = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(goal);
        if (dateMatch != null) {
          final month = int.parse(dateMatch.group(1)!);
          final day = int.parse(dateMatch.group(2)!);
          final targetDate = DateTime(now.year, month, day);

          final daysUntil = targetDate.difference(now).inDays;
          if (daysUntil >= 0 && daysUntil <= 3) {
            suggestions.add(ProactiveSuggestion(
              type: SuggestionType.goalDeadline,
              title: '目标截止提醒',
              content: '"$goal" 将在${daysUntil == 0 ? '今天' : daysUntil == 1 ? '明天' : '$daysUntil天后'}到期',
              priority: daysUntil == 0 ? SuggestionPriority.high : SuggestionPriority.medium,
              action: '询问用户进展',
            ));
          }
        }
      }
    }

    return suggestions;
  }

  /// 检查情绪状态
  Future<List<ProactiveSuggestion>> _checkEmotionalState() async {
    final suggestions = <ProactiveSuggestion>[];

    // 获取最近7天情绪状态
    final states = await _getRecentEmotionalStates(days: 7);
    if (states.length < 3) return suggestions;

    // 检测持续负面情绪
    final negativeStates = states.where((s) => [
      EmotionalState.anxious,
      EmotionalState.sad,
      EmotionalState.stressed,
    ].contains(s)).length;

    if (negativeStates >= states.length * 0.6) {
      // 60%以上时间为负面情绪
      suggestions.add(ProactiveSuggestion(
        type: SuggestionType.emotionalSupport,
        title: '情绪关注',
        content: '检测到您最近可能有些压力，需要聊聊吗？',
        priority: SuggestionPriority.high,
        action: '主动提供支持对话',
      ));
    }

    return suggestions;
  }

  /// 检查重要日期
  Future<List<ProactiveSuggestion>> _checkImportantDates(DateTime now) async {
    final suggestions = <ProactiveSuggestion>[];
    final profile = await _databaseService.getUserProfile();

    // 检查家庭成员生日等
    if (profile?.familyMembers != null) {
      // 这里可以扩展生日检测逻辑
    }

    return suggestions;
  }

  /// 检查习惯模式
  Future<List<ProactiveSuggestion>> _checkHabitPatterns(DateTime now) async {
    final suggestions = <ProactiveSuggestion>[];

    // 获取用户习惯
    final patterns = await _databaseService.getBehaviorPatterns(limit: 20);

    for (final pattern in patterns) {
      final type = pattern['pattern_type'] as String;
      final lastTriggered = pattern['last_triggered'] as int?;

      if (lastTriggered != null) {
        final lastDate = DateTime.fromMillisecondsSinceEpoch(lastTriggered);
        final hoursSince = now.difference(lastDate).inHours;

        // 如果习惯行为超过通常间隔未发生
        if (type == 'morning_recording' && hoursSince > 48) {
          suggestions.add(ProactiveSuggestion(
            type: SuggestionType.habitReminder,
            title: '习惯提醒',
            content: '您通常会在早上记录想法，今天要不要也记一点？',
            priority: SuggestionPriority.low,
            action: '提醒录音',
          ));
        }
      }
    }

    return suggestions;
  }

  /// 生成AI洞察
  Future<String> _generateAIInsights({
    required List<Map<String, dynamic>> conversations,
    required List<Map<String, dynamic>> emotionalStates,
    required UserMetrics metrics,
  }) async {
    if (!_kimiService.isAvailable) {
      return 'AI分析不可用，基于本地数据生成基础报告。';
    }

    final prompt = '''基于以下用户数据生成深度洞察：

【对话数量】${conversations.length}条
【情绪分布】积极:${metrics.positiveEmotionRatio}%, 中性:${metrics.neutralEmotionRatio}%, 消极:${metrics.negativeEmotionRatio}%
【活跃时段】${metrics.mostActiveHour}:00
【高频话题】${metrics.topTopics.join(', ')}

请从心理学和生活习惯角度，给出3-5条深度洞察，帮助用户更好地了解自己。''';return await _kimiService.askQuestion(prompt, enableTools: false) ??'洞察生成失败';
  }

  /// 生成建议行动
  Future<List<String>> _generateSuggestedActions(UserMetrics metrics) async {
    final actions = <String>[];

    if (metrics.negativeEmotionRatio > 30) {
      actions.add('建议安排放松活动，如冥想或散步');
    }

    if (metrics.dailyAverageConversations < 2) {
      actions.add('多使用语音笔记记录想法，有助于情绪管理');
    }

    return actions;
  }

  // ==================== 辅助方法 ====================

  Future<DateTime?> _getLastEvolutionTime() async {
    final logs = await _databaseService.getEvolutionLogs(limit: 1);
    if (logs.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(logs.first['timestamp'] as int);
  }

  Future<List<Map<String, dynamic>>> _getRecentConversations({required int days}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final messages = await _databaseService.getChatMessages(limit: 1000);
    return messages.where((m) {
      final ts = DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int);
      return ts.isAfter(since);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getConversationsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final messages = await _databaseService.getChatMessages(limit: 1000);
    return messages.where((m) {
      final ts = DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int);
      return ts.isAfter(start) && ts.isBefore(end);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getBehaviorsInRange(
    DateTime start,
    DateTime end,
  ) async {
    // TODO: 实现行为查询
    return [];
  }

  Future<List<Map<String, dynamic>>> _getEmotionalStatesInRange(
    DateTime start,
    DateTime end,
  ) async {
    // TODO: 实现情绪状态查询
    return [];
  }

  Future<EmotionalState?> _getPreviousEmotionalState() async {
    final states = await _getRecentEmotionalStates(days: 1);
    return states.isNotEmpty ? states.first : null;
  }

  Future<List<EmotionalState>> _getRecentEmotionalStates({required int days}) async {
    // TODO: 实现情绪状态查询
    return [];
  }

  bool _isSignificantChange(EmotionalState previous, EmotionalState current) {
    // 从积极到消极，或从消极到积极，都是显著变化
    final positive = [EmotionalState.happy, EmotionalState.excited, EmotionalState.calm];
    final negative = [EmotionalState.anxious, EmotionalState.sad, EmotionalState.angry];

    return (positive.contains(previous) && negative.contains(current)) ||
        (negative.contains(previous) && positive.contains(current));
  }

  Future<void> _handleSignificantEmotionalChange(
    EmotionalState previous,
    EmotionalState current,
    String? context,
  ) async {
    // 记录显著情绪变化
    debugPrint('检测到显著情绪变化: ${previous.name} -> ${current.name}');
    // 可以触发主动关心
  }

  UserMetrics _calculateMetrics(
    List<Map<String, dynamic>> conversations,
    List<Map<String, dynamic>> behaviors,
    List<Map<String, dynamic>> emotionalStates,
  ) {
    // TODO: 实现完整的指标计算
    return UserMetrics(
      totalConversations: conversations.length,
      dailyAverageConversations: conversations.length / 7,
      positiveEmotionRatio: 60,
      neutralEmotionRatio: 30,
      negativeEmotionRatio: 10,
      mostActiveHour: 9,
      topTopics: ['工作', '学习', '生活'],
    );
  }

  Future<EvolutionResult?> _analyzeEvolutionPotential({
    required UserProfile profile,
    required List<Map<String, dynamic>> conversations,
    required List<LearningEvent> behaviors,
  }) async {
    // TODO: 实现深度进化潜力分析
    return null;
  }

  void dispose() {
    _learningTimer?.cancel();
  }
}

// ==================== 数据模型 ====================

enum LearningEventType { conversation, behavior, external }

enum BehaviorType {
  createdTodo,
  completedTodo,
  createdNote,
  playedRecording,
  importedCallRecording,
  updatedProfile,
  searchedMemory,
  morningRecording,
}

enum EmotionalState {
  happy,
  excited,
  calm,
  neutral,
  anxious,
  sad,
  angry,
  stressed,
}

extension EmotionalStateExtension on EmotionalState {
  bool get isPositive =>
      this == EmotionalState.happy ||
      this == EmotionalState.excited ||
      this == EmotionalState.calm;

  bool get isNegative =>
      this == EmotionalState.anxious ||
      this == EmotionalState.sad ||
      this == EmotionalState.angry ||
      this == EmotionalState.stressed;
}

enum SuggestionType {
  goalDeadline,
  emotionalSupport,
  habitReminder,
  importantDate,
  insight,
}

enum SuggestionPriority { low, medium, high, urgent }

class LearningEvent {
  final LearningEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  LearningEvent({
    required this.type,
    required this.timestamp,
    required this.data,
  });
}

class ProfileUpdateCandidate {
  final String field;
  final String value;
  final double confidence;
  final String? reason;

  ProfileUpdateCandidate({
    required this.field,
    required this.value,
    required this.confidence,
    this.reason,
  });
}

class ProactiveSuggestion {
  final SuggestionType type;
  final String title;
  final String content;
  final SuggestionPriority priority;
  final String action;
  final Map<String, dynamic>? metadata;

  ProactiveSuggestion({
    required this.type,
    required this.title,
    required this.content,
    required this.priority,
    required this.action,
    this.metadata,
  });
}

class InsightReport {
  final DateTimeRange period;
  final UserMetrics metrics;
  final String aiInsights;
  final List<String> suggestedActions;

  InsightReport({
    required this.period,
    required this.metrics,
    required this.aiInsights,
    required this.suggestedActions,
  });
}

class UserMetrics {
  final int totalConversations;
  final double dailyAverageConversations;
  final double positiveEmotionRatio;
  final double neutralEmotionRatio;
  final double negativeEmotionRatio;
  final int mostActiveHour;
  final List<String> topTopics;

  UserMetrics({
    required this.totalConversations,
    required this.dailyAverageConversations,
    required this.positiveEmotionRatio,
    required this.neutralEmotionRatio,
    required this.negativeEmotionRatio,
    required this.mostActiveHour,
    required this.topTopics,
  });
}

class EvolutionResult {
  final bool hasUpdates;
  final List<ProfileUpdateCandidate> updates;
  final String summary;

  EvolutionResult({
    required this.hasUpdates,
    required this.updates,
    required this.summary,
  });
}

// 扩展 ToolCall
extension ToolCallJson on ToolCall {
  Map<String, dynamic> toJson() => {
        'tool': tool,
        'params': params,
      };
}
