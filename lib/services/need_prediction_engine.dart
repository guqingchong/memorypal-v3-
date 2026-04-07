import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'database_extension.dart';
import '../models/recording.dart';
import '../models/note.dart';
import '../models/user_profile.dart';

/// 需求预测引擎 - 预测用户可能需要什么
///
/// 基于：
/// 1. 历史行为模式
/// 2. 时间上下文（早上/晚上、工作日/周末）
/// 3. 最近活动序列
/// 4. 用户画像和偏好
/// 5. 外部事件（天气、日期等）
///
/// 参考Claudecode的Coordinator调度和上下文预测机制
class NeedPredictionEngine {
  static final NeedPredictionEngine _instance = NeedPredictionEngine._internal();
  factory NeedPredictionEngine() => _instance;
  NeedPredictionEngine._internal();

  final DatabaseService _databaseService = DatabaseService();

  // 预测置信度阈值
  static const double _confidenceThreshold = 0.6;

  /// 预测当前用户需求
  ///
  /// 返回按置信度排序的需求列表
  Future<List<PredictedNeed>> predictCurrentNeeds() async {
    final needs = <PredictedNeed>[];
    final context = await _gatherContext();

    // 1. 基于时间模式的预测（加权时间窗口算法）
    final timeBasedNeeds = await _predictBasedOnTimeWeighted(context);
    needs.addAll(timeBasedNeeds);

    // 2. 基于行为序列的预测（协同过滤算法）
    final sequenceNeeds = await _predictBasedOnSequenceCollaborative(context);
    needs.addAll(sequenceNeeds);

    // 3. 基于画像的预测
    final profileNeeds = await _predictBasedOnProfile(context);
    needs.addAll(profileNeeds);

    // 4. 基于外部事件的预测
    final eventNeeds = await _predictBasedOnEvents(context);
    needs.addAll(eventNeeds);

    // 5. 基于历史模式匹配的预测
    final patternNeeds = await _predictBasedOnHistoryPatterns(context);
    needs.addAll(patternNeeds);

    // 使用加权算法综合评分
    return _weightedRankAndDeduplicate(needs, context);
  }

  /// 预测接下来24小时的可能需求
  Future<List<FutureNeed>> predictFutureNeeds() async {
    final needs = <FutureNeed>[];
    final now = DateTime.now();

    // 分析未来24小时的时间点
    for (int hour = 0; hour < 24; hour++) {
      final futureTime = now.add(Duration(hours: hour));
      final context = await _gatherContextForTime(futureTime);

      // 预测该时间点可能的需求
      final predictedNeed = await _predictForTimePoint(context);
      if (predictedNeed != null && predictedNeed.confidence > _confidenceThreshold) {
        needs.add(FutureNeed(
          predictedTime: futureTime,
          need: predictedNeed,
        ));
      }
    }

    return needs;
  }

  /// 预测用户可能想搜索什么
  Future<List<String>> predictSearchQueries() async {
    final queries = <String>[];
    final context = await _gatherContext();

    // 1. 基于当前活动的预测
    if (context.recentRecordings.isNotEmpty) {
      final latestRecording = context.recentRecordings.first;
      if (latestRecording.transcript != null) {
        // 提取可能的搜索意图
        final extractedQueries = await _extractSearchQueriesFromText(
          latestRecording.transcript!,
        );
        queries.addAll(extractedQueries);
      }
    }

    // 2. 基于待办的预测
    for (final todo in context.pendingTodos) {
      final content = todo['content'] as String;
      queries.add('关于"$content"的记录');
    }

    // 3. 基于画像兴趣的预测
    for (final interest in context.userProfile?.interests ?? []) {
      queries.add('$interest 相关');
    }

    return queries.take(5).toList();
  }

  /// 预测用户可能需要创建什么内容
  Future<List<ContentSuggestion>> predictContentNeeds() async {
    final suggestions = <ContentSuggestion>[];
    final context = await _gatherContext();

    // 1. 检测语音笔记需求
    if (_shouldSuggestVoiceNote(context)) {
      suggestions.add(ContentSuggestion(
        type: ContentType.voiceNote,
        title: '记录当前想法',
        reason: '检测到你可能有想法想要记录',
        confidence: 0.7,
      ));
    }

    // 2. 检测待办创建需求
    if (_shouldSuggestTodo(context)) {
      suggestions.add(ContentSuggestion(
        type: ContentType.todo,
        title: '从最近录音提取待办',
        reason: '最近的录音中可能包含待办事项',
        confidence: 0.6,
      ));
    }

    // 3. 检测笔记整理需求
    if (_shouldSuggestNote(context)) {
      suggestions.add(ContentSuggestion(
        type: ContentType.note,
        title: '整理今天的想法',
        reason: '今天有多条录音，可以整理成笔记',
        confidence: 0.5,
      ));
    }

    return suggestions;
  }

  /// 学习并更新预测模型
  ///
  /// 在每次用户行为后调用，改进预测准确性
  Future<void> learnFromBehavior({
    required BehaviorAction action,
    required DateTime timestamp,
    required Map<String, dynamic> context,
  }) async {
    // 记录行为模式
    await _databaseService.insertBehaviorPattern({
      'action': action.name,
      'hour': timestamp.hour,
      'weekday': timestamp.weekday,
      'context': jsonEncode(context),
      'timestamp': timestamp.millisecondsSinceEpoch,
    });

    // 如果用户接受了预测建议，记录为正反馈
    if (context['accepted_prediction'] == true) {
      await _recordPositiveFeedback(action, context);
    }
  }

  // ==================== 私有方法 ====================

  /// 收集当前上下文
  Future<PredictionContext> _gatherContext() async {
    final now = DateTime.now();

    return PredictionContext(
      currentTime: now,
      userProfile: await _databaseService.getUserProfile(),
      recentRecordings: await _getRecentRecordings(hours: 24),
      recentNotes: await _getRecentNotes(hours: 24),
      pendingTodos: await _databaseService.getTodos(includeCompleted: false),
      recentBehaviors: await _getRecentBehaviors(hours: 24),
      todayConversations: await _getTodayConversations(),
    );
  }

  /// 收集指定时间的上下文
  Future<PredictionContext> _gatherContextForTime(DateTime time) async {
    // 获取该时间的历史行为模式
    final historicalBehaviors = await _getHistoricalBehaviorsAtTime(time);

    return PredictionContext(
      currentTime: time,
      userProfile: await _databaseService.getUserProfile(),
      recentRecordings: [],
      recentNotes: [],
      pendingTodos: [],
      recentBehaviors: historicalBehaviors,
      todayConversations: [],
    );
  }

  /// 基于时间预测需求
  Future<List<PredictedNeed>> _predictBasedOnTime(PredictionContext context) async {
    final needs = <PredictedNeed>[];
    final hour = context.currentTime.hour;
    final weekday = context.currentTime.weekday;

    // 早上8-9点：可能需要查看今日概览
    if (hour >= 8 && hour <= 9) {
      needs.add(PredictedNeed(
        type: NeedType.dailyOverview,
        description: '查看今日待办和安排',
        confidence: _calculateTimeBasedConfidence(context, 'morning_overview'),
        suggestedAction: 'show_daily_summary',
      ));
    }

    // 中午12点：可能需要记录午休想法
    if (hour == 12) {
      needs.add(PredictedNeed(
        type: NeedType.quickCapture,
        description: '快速记录午间想法',
        confidence: _calculateTimeBasedConfidence(context, 'noon_capture'),
        suggestedAction: 'start_voice_note',
      ));
    }

    // 晚上9-10点：可能需要回顾一天
    if (hour >= 21 && hour <= 22) {
      needs.add(PredictedNeed(
        type: NeedType.dailyReview,
        description: '回顾今天的记录',
        confidence: _calculateTimeBasedConfidence(context, 'evening_review'),
        suggestedAction: 'show_daily_summary',
      ));
    }

    // 周末早上：可能有更多时间深度思考
    if ((weekday == 6 || weekday == 7) && hour >= 9 && hour <= 11) {
      needs.add(PredictedNeed(
        type: NeedType.deepReflection,
        description: '深度思考或规划',
        confidence: _calculateTimeBasedConfidence(context, 'weekend_reflection'),
        suggestedAction: 'suggest_reflection_prompts',
      ));
    }

    return needs;
  }

  /// 基于行为序列预测需求
  Future<List<PredictedNeed>> _predictBasedOnSequence(PredictionContext context) async {
    final needs = <PredictedNeed>[];

    // 检测连续录音模式
    if (context.recentRecordings.length >= 3) {
      final lastThree = context.recentRecordings.take(3).toList();
      final timeSpan = lastThree.first.startTime.difference(lastThree.last.startTime);

      // 如果3小时内录了3条，可能在密集思考某个话题
      if (timeSpan.inHours <= 3) {
        needs.add(PredictedNeed(
          type: NeedType.topicOrganization,
          description: '整理相关录音为专题笔记',
          confidence: 0.75,
          suggestedAction: 'suggest_note_organization',
          metadata: {'recordings': lastThree.map((r) => r.id).toList()},
        ));
      }
    }

    // 检测待办完成后的行为
    final recentCompletedTodos = context.recentBehaviors
        .where((b) => b['action'] == 'complete_todo')
        .toList();

    if (recentCompletedTodos.isNotEmpty) {
      // 完成待办后，可能想要记录相关想法
      needs.add(PredictedNeed(
        type: NeedType.postCompletionReflection,
        description: '记录完成待办的心得',
        confidence: 0.6,
        suggestedAction: 'prompt_voice_note',
      ));
    }

    return needs;
  }

  /// 基于画像预测需求
  Future<List<PredictedNeed>> _predictBasedOnProfile(PredictionContext context) async {
    final needs = <PredictedNeed>[];
    final profile = context.userProfile;

    if (profile == null) return needs;

    // 基于兴趣预测
    for (final interest in profile.interests) {
      // 如果最近没有关于这个兴趣的记录，但用户之前经常记录
      final hasRecentInterestContent = context.recentRecordings.any((r) {
        return r.transcript?.contains(interest) ?? false;
      });

      if (!hasRecentInterestContent) {
        final frequency = await _getInterestRecordingFrequency(interest);
        if (frequency > 0.5) { // 每周超过0.5次
          needs.add(PredictedNeed(
            type: NeedType.interestFollowUp,
            description: '记录关于$interest的新想法',
            confidence: frequency * 0.8,
            suggestedAction: 'suggest_topic_recording',
            metadata: {'topic': interest},
          ));
        }
      }
    }

    // 基于目标预测
    if (profile.shortTermGoals != null && profile.shortTermGoals!.isNotEmpty) {
      needs.add(PredictedNeed(
        type: NeedType.goalProgress,
        description: '记录目标进展',
        confidence: 0.65,
        suggestedAction: 'prompt_goal_update',
      ));
    }

    return needs;
  }

  /// 基于外部事件预测需求
  Future<List<PredictedNeed>> _predictBasedOnEvents(PredictionContext context) async {
    final needs = <PredictedNeed>[];

    // 检测月初/月末
    final day = context.currentTime.day;
    if (day == 1) {
      needs.add(PredictedNeed(
        type: NeedType.monthlyPlanning,
        description: '制定本月计划',
        confidence: 0.7,
        suggestedAction: 'suggest_monthly_planning',
      ));
    }

    // 检测周末结束
    if (context.currentTime.weekday == 7) { // 周日
      needs.add(PredictedNeed(
        type: NeedType.weeklyReview,
        description: '回顾本周并规划下周',
        confidence: 0.65,
        suggestedAction: 'suggest_weekly_review',
      ));
    }

    return needs;
  }

  /// 预测特定时间点的需求
  Future<PredictedNeed?> _predictForTimePoint(PredictionContext context) async {
    final hour = context.currentTime.hour;

    // 分析历史数据中该时间点的行为模式
    final patterns = await _getBehaviorPatternsAtHour(hour);
    if (patterns.isEmpty) return null;

    // 找到最常见的模式
    final patternCounts = <String, int>{};
    for (final pattern in patterns) {
      final action = pattern['action'] as String;
      patternCounts[action] = (patternCounts[action] ?? 0) + 1;
    }

    final mostCommon = patternCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b);

    final confidence = mostCommon.value / patterns.length;
    if (confidence < _confidenceThreshold) return null;

    return PredictedNeed(
      type: _mapActionToNeedType(mostCommon.key),
      description: '基于历史模式预测',
      confidence: confidence,
      suggestedAction: mostCommon.key,
    );
  }

  /// 从文本中提取搜索查询意图
  Future<List<String>> _extractSearchQueriesFromText(String text) async {
    final queries = <String>[];

    // 简单关键词提取
    final keywords = [
      '项目', '会议', '客户', '方案', '问题',
      '想法', '计划', '目标', '学习', '工作',
    ];

    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        // 提取包含关键词的上下文
        final index = text.indexOf(keyword);
        final start = index > 10 ? index - 10 : 0;
        final end = index + keyword.length + 10 < text.length
            ? index + keyword.length + 10
            : text.length;
        final context = text.substring(start, end);
        queries.add(context);
      }
    }

    return queries.take(3).toList();
  }

  /// 是否应该建议语音笔记
  bool _shouldSuggestVoiceNote(PredictionContext context) {
    // 如果已经有很多录音了，可能不需要再建议
    if (context.recentRecordings.length >= 5) return false;

    // 如果很久没录音了
    if (context.recentRecordings.isEmpty) {
      final lastRecording = context.recentRecordings.isNotEmpty
          ? context.recentRecordings.first
          : null;
      if (lastRecording != null) {
        final hoursSince = DateTime.now()
            .difference(lastRecording.startTime)
            .inHours;
        return hoursSince > 12;
      }
    }

    return false;
  }

  /// 是否应该建议创建待办
  bool _shouldSuggestTodo(PredictionContext context) {
    // 如果最近录音包含行动项词汇
    final actionKeywords = ['需要', '必须', '应该', '记得', '别忘了'];

    return context.recentRecordings.any((r) {
      if (r.transcript == null) return false;
      return actionKeywords.any((k) => r.transcript!.contains(k));
    });
  }

  /// 是否应该建议创建笔记
  bool _shouldSuggestNote(PredictionContext context) {
    // 如果今天有多条录音但没有笔记
    return context.recentRecordings.length >= 3 && context.recentNotes.isEmpty;
  }

  /// 计算时间模式置信度
  double _calculateTimeBasedConfidence(PredictionContext context, String patternType) {
    // 查询历史数据中该时间点的行为频率
    // 简化实现，实际应查询数据库
    return 0.7;
  }

  /// 获取兴趣记录频率
  Future<double> _getInterestRecordingFrequency(String interest) async {
    // 查询该兴趣相关的录音频率
    // 简化实现
    return 0.6;
  }

  // ==================== 新增加权算法 ====================

  /// 基于时间加权窗口的预测
  ///
  /// 考虑时间衰减：离当前时间越近的行为权重越高
  Future<List<PredictedNeed>> _predictBasedOnTimeWeighted(PredictionContext context) async {
    final needs = <PredictedNeed>[];
    final now = context.currentTime;
    final hour = now.hour;
    final weekday = now.weekday;

    // 获取历史行为数据（过去30天）
    final historicalBehaviors = await _getHistoricalBehaviors(days: 30);

    // 计算每个需求类型的时间加权得分
    final scores = <NeedType, double>{};

    for (final behavior in historicalBehaviors) {
      final behaviorTime = DateTime.fromMillisecondsSinceEpoch(
        behavior['timestamp'] as int,
      );
      final action = behavior['action'] as String;

      // 计算时间衰减权重
      final daysAgo = now.difference(behaviorTime).inDays;
      final timeWeight = _calculateTimeDecayWeight(daysAgo);

      // 计算时间相似度权重
      final hourSimilarity = _calculateHourSimilarity(
        behaviorTime.hour,
        hour,
      );
      final weekdaySimilarity = behaviorTime.weekday == weekday ? 1.0 : 0.3;

      // 综合权重
      final totalWeight = timeWeight * hourSimilarity * weekdaySimilarity;

      // 累加得分
      final needType = _mapActionToNeedType(action);
      scores[needType] = (scores[needType] ?? 0) + totalWeight;
    }

    // 将得分转换为预测需求
    scores.forEach((needType, score) {
      if (score > 1.0) { // 至少发生2次以上的行为才考虑
        needs.add(PredictedNeed(
          type: needType,
          description: _getNeedDescription(needType),
          confidence: _normalizeScore(score, historicalBehaviors.length),
          suggestedAction: _getSuggestedAction(needType),
        ));
      }
    });

    return needs;
  }

  /// 基于协同过滤的行为序列预测
  ///
  /// 分析：完成A行为后，用户通常在多长时间内会执行B行为
  Future<List<PredictedNeed>> _predictBasedOnSequenceCollaborative(
    PredictionContext context,
  ) async {
    final needs = <PredictedNeed>[];

    // 获取最近的行为序列
    final recentActions = context.recentBehaviors
        .map((b) => b['action'] as String)
        .take(5)
        .toList();

    if (recentActions.isEmpty) return needs;

    // 查询历史行为链：A -> B 的转换概率
    final transitionMatrix = await _buildTransitionMatrix();

    // 预测下一个可能的行为
    final predictions = <String, double>{};
    for (final action in recentActions) {
      final transitions = transitionMatrix[action] ?? {};
      transitions.forEach((nextAction, probability) {
        predictions[nextAction] = (predictions[nextAction] ?? 0) + probability;
      });
    }

    // 转换为需求
    predictions.forEach((action, probability) {
      if (probability > 0.3) { // 30%以上概率
        needs.add(PredictedNeed(
          type: _mapActionToNeedType(action),
          description: '基于最近行为的预测',
          confidence: probability.clamp(0, 1),
          suggestedAction: action,
        ));
      }
    });

    return needs;
  }

  /// 基于历史模式的预测
  ///
  /// 检测重复出现的模式（如：每周一早会、每周五总结）
  Future<List<PredictedNeed>> _predictBasedOnHistoryPatterns(
    PredictionContext context,
  ) async {
    final needs = <PredictedNeed>[];

    // 获取周期性行为模式
    final patterns = await _getPeriodicPatterns();

    for (final pattern in patterns) {
      final patternType = pattern['pattern_type'] as String;
      final frequency = pattern['frequency'] as int;
      final period = pattern['period'] as String; // 'daily', 'weekly', 'monthly'

      // 检查当前是否匹配该模式的时间点
      if (_matchesPatternTime(period, context.currentTime)) {
        needs.add(PredictedNeed(
          type: _mapPatternToNeedType(patternType),
          description: '基于$period习惯模式',
          confidence: (frequency / 10).clamp(0.5, 0.95),
          suggestedAction: patternType,
        ));
      }
    }

    return needs;
  }

  /// 加权排序和去重
  ///
  /// 综合多个预测源，使用加权投票算法
  List<PredictedNeed> _weightedRankAndDeduplicate(
    List<PredictedNeed> needs,
    PredictionContext context,
  ) {
    // 按类型分组
    final grouped = <NeedType, List<PredictedNeed>>{};
    for (final need in needs) {
      grouped.putIfAbsent(need.type, () => []).add(need);
    }

    // 对每个类型内的预测进行加权合并
    final merged = <PredictedNeed>[];
    grouped.forEach((type, typeNeeds) {
      if (typeNeeds.isEmpty) return;

      // 加权平均置信度
      double totalConfidence = 0;
      double totalWeight = 0;
      String bestDescription = typeNeeds.first.description;
      String bestAction = typeNeeds.first.suggestedAction;

      for (final need in typeNeeds) {
        final weight = _getPredictionSourceWeight(need);
        totalConfidence += need.confidence * weight;
        totalWeight += weight;

        // 保留最高置信度的描述
        if (need.confidence > (typeNeeds.first.confidence)) {
          bestDescription = need.description;
          bestAction = need.suggestedAction;
        }
      }

      final avgConfidence = totalWeight > 0 ? totalConfidence / totalWeight : 0;

      if (avgConfidence >= _confidenceThreshold) {
        merged.add(PredictedNeed(
          type: type,
          description: bestDescription,
          confidence: avgConfidence.clamp(0, 1).toDouble(),
          suggestedAction: bestAction,
        ));
      }
    });

    // 按置信度排序
    merged.sort((a, b) => b.confidence.compareTo(a.confidence));

    return merged;
  }

  /// 计算时间衰减权重
  ///
  /// 指数衰减：越近的行为权重越高
  double _calculateTimeDecayWeight(int daysAgo) {
    const halfLife = 7; // 7天半衰期
    return pow(0.5, daysAgo / halfLife).toDouble();
  }

  /// 计算小时相似度
  ///
  /// 越接近当前时间，相似度越高
  double _calculateHourSimilarity(int behaviorHour, int currentHour) {
    final diff = (behaviorHour - currentHour).abs();
    final circularDiff = diff > 12 ? 24 - diff : diff;
    return 1.0 - (circularDiff / 12.0);
  }

  /// 获取预测源的权重
  ///
  /// 不同预测源的可靠性不同
  double _getPredictionSourceWeight(PredictedNeed need) {
    // 基于描述判断来源
    if (need.description.contains('时间')) return 1.2;
    if (need.description.contains('行为')) return 1.0;
    if (need.description.contains('画像')) return 0.8;
    if (need.description.contains('事件')) return 0.9;
    if (need.description.contains('模式')) return 1.1;
    return 1.0;
  }

  /// 归一化得分
  double _normalizeScore(double score, int totalCount) {
    if (totalCount == 0) return 0;
    return (score / sqrt(totalCount)).clamp(0, 1);
  }

  /// 构建行为转换矩阵
  Future<Map<String, Map<String, double>>> _buildTransitionMatrix() async {
    // 简化实现：基于常见行为链
    return {
      'complete_todo': {
        'create_recording': 0.4, // 完成待办后40%概率录音
        'create_note': 0.3,
      },
      'create_recording': {
        'play_recording': 0.2,
        'create_note': 0.3,
      },
      'morning_open': {
        'check_todos': 0.6,
        'create_recording': 0.3,
      },
    };
  }

  /// 检查是否匹配模式时间
  bool _matchesPatternTime(String period, DateTime time) {
    switch (period) {
      case 'daily':
        return true;
      case 'weekly':
        // 检查是否是一周中的相同时间
        return time.weekday <= 5; // 工作日
      case 'monthly':
        return time.day <= 5; // 月初
      default:
        return false;
    }
  }

  /// 获取需求描述
  String _getNeedDescription(NeedType type) {
    final descriptions = {
      NeedType.dailyOverview: '查看今日概览',
      NeedType.quickCapture: '快速记录想法',
      NeedType.dailyReview: '回顾今日记录',
      NeedType.deepReflection: '深度思考',
      NeedType.topicOrganization: '整理话题',
      NeedType.goalProgress: '记录目标进展',
      NeedType.memoryRetrieval: '查找记忆',
      NeedType.taskManagement: '管理待办',
    };
    return descriptions[type] ?? '一般需求';
  }

  /// 获取建议动作
  String _getSuggestedAction(NeedType type) {
    final actions = {
      NeedType.dailyOverview: 'show_daily_summary',
      NeedType.quickCapture: 'start_voice_note',
      NeedType.dailyReview: 'show_today_recordings',
      NeedType.deepReflection: 'suggest_reflection',
      NeedType.topicOrganization: 'organize_by_topic',
      NeedType.goalProgress: 'update_goal_progress',
      NeedType.memoryRetrieval: 'smart_search',
      NeedType.taskManagement: 'manage_todos',
    };
    return actions[type] ?? 'general_help';
  }

  NeedType _mapPatternToNeedType(String patternType) {
    final mapping = {
      'morning_routine': NeedType.dailyOverview,
      'evening_review': NeedType.dailyReview,
      'weekly_planning': NeedType.goalProgress,
      'recording_spree': NeedType.topicOrganization,
    };
    return mapping[patternType] ?? NeedType.general;
  }

  Future<List<Map<String, dynamic>>> _getHistoricalBehaviors({
    required int days,
  }) async {
    // TODO: 实现历史行为查询
    return [];
  }

  Future<List<Map<String, dynamic>>> _getPeriodicPatterns() async {
    // TODO: 实现周期模式查询
    return [];
  }

  // ==================== 原有方法保留 ====================

  /// 去重并排序
  List<PredictedNeed> _deduplicateAndSort(List<PredictedNeed> needs) {
    // 按类型去重，保留置信度最高的
    final uniqueNeeds = <String, PredictedNeed>{};
    for (final need in needs) {
      final existing = uniqueNeeds[need.type.name];
      if (existing == null || need.confidence > existing.confidence) {
        uniqueNeeds[need.type.name] = need;
      }
    }

    // 按置信度排序
    final sorted = uniqueNeeds.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    return sorted;
  }

  NeedType _mapActionToNeedType(String action) {
    switch (action) {
      case 'create_recording':
        return NeedType.quickCapture;
      case 'search_memory':
        return NeedType.memoryRetrieval;
      case 'create_todo':
        return NeedType.taskManagement;
      default:
        return NeedType.general;
    }
  }

  // ==================== 数据获取方法 ====================

  Future<List<Recording>> _getRecentRecordings({required int hours}) async {
    final since = DateTime.now().subtract(Duration(hours: hours));
    final recordings = await _databaseService.getRecordings(limit: 100);
    return recordings.where((r) => r.startTime.isAfter(since)).toList();
  }

  Future<List<Note>> _getRecentNotes({required int hours}) async {
    final since = DateTime.now().subtract(Duration(hours: hours));
    final notes = await _databaseService.getNotes(limit: 100);
    return notes.where((n) => n.createdAt.isAfter(since)).toList();
  }

  Future<List<Map<String, dynamic>>> _getRecentBehaviors({required int hours}) async {
    // TODO: 实现行为查询
    return [];
  }

  Future<List<Map<String, dynamic>>> _getTodayConversations() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final messages = await _databaseService.getChatMessages(limit: 100);
    return messages.where((m) {
      final ts = DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int);
      return ts.isAfter(startOfDay);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getHistoricalBehaviorsAtTime(DateTime time) async {
    // TODO: 实现历史行为查询
    return [];
  }

  Future<List<Map<String, dynamic>>> _getBehaviorPatternsAtHour(int hour) async {
    // TODO: 实现行为模式查询
    return [];
  }

  Future<void> _recordPositiveFeedback(BehaviorAction action, Map<String, dynamic> context) async {
    // TODO: 记录正反馈用于改进预测
  }
}

// ==================== 数据模型 ====================

enum NeedType {
  dailyOverview,           // 每日概览
  quickCapture,            // 快速记录
  dailyReview,             // 每日回顾
  deepReflection,          // 深度思考
  topicOrganization,       // 话题整理
  postCompletionReflection, // 完成反思
  interestFollowUp,        // 兴趣跟进
  goalProgress,            // 目标进展
  memoryRetrieval,         // 记忆检索
  taskManagement,          // 任务管理
  monthlyPlanning,         // 月度规划
  weeklyReview,            // 周回顾
  general,                 // 一般需求
}

enum BehaviorAction {
  createRecording,
  playRecording,
  createNote,
  createTodo,
  completeTodo,
  searchMemory,
  openApp,
  closeApp,
}

enum ContentType {
  voiceNote,
  todo,
  note,
}

class PredictedNeed {
  final NeedType type;
  final String description;
  final double confidence;
  final String suggestedAction;
  final Map<String, dynamic>? metadata;

  PredictedNeed({
    required this.type,
    required this.description,
    required this.confidence,
    required this.suggestedAction,
    this.metadata,
  });
}

class FutureNeed {
  final DateTime predictedTime;
  final PredictedNeed need;

  FutureNeed({
    required this.predictedTime,
    required this.need,
  });
}

class ContentSuggestion {
  final ContentType type;
  final String title;
  final String reason;
  final double confidence;

  ContentSuggestion({
    required this.type,
    required this.title,
    required this.reason,
    required this.confidence,
  });
}

class PredictionContext {
  final DateTime currentTime;
  final UserProfile? userProfile;
  final List<Recording> recentRecordings;
  final List<Note> recentNotes;
  final List<Map<String, dynamic>> pendingTodos;
  final List<Map<String, dynamic>> recentBehaviors;
  final List<Map<String, dynamic>> todayConversations;

  PredictionContext({
    required this.currentTime,
    required this.userProfile,
    required this.recentRecordings,
    required this.recentNotes,
    required this.pendingTodos,
    required this.recentBehaviors,
    required this.todayConversations,
  });
}
