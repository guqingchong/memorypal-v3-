import 'dart:async';
import 'package:flutter/material.dart';
import 'agent_service.dart';
import 'profile_evolution_engine.dart';
import 'proactive_dialogue_engine.dart';
import 'need_prediction_engine.dart';
import 'database_service.dart';
import 'ai_service_manager.dart';
import '../models/user_profile.dart';

/// 第二大脑协调器 - 三层架构的中央控制器
///
/// 类似Claudecode的QueryEngine，负责：
/// 1. 协调三层架构的交互
/// 2. 管理记忆流动（感知→短期→长期）
/// 3. 决策何时主动/被动响应
/// 4. 维护对话状态机
class SecondBrainOrchestrator {
  static final SecondBrainOrchestrator _instance = SecondBrainOrchestrator._internal();
  factory SecondBrainOrchestrator() => _instance;
  SecondBrainOrchestrator._internal();

  // 三层组件
  final AgentService _agentService = AgentService();
  final ProfileEvolutionEngine _evolutionEngine = ProfileEvolutionEngine();
  final ProactiveDialogueEngine _proactiveEngine = ProactiveDialogueEngine();
  final NeedPredictionEngine _predictionEngine = NeedPredictionEngine();
  final DatabaseService _databaseService = DatabaseService();
  final AIServiceManager _aiManager = AIServiceManager();

  // 状态
  bool _isInitialized = false;
  UserProfile? _userProfile;
  OrchestratorState _currentState = OrchestratorState.idle;

  // 流控制器
  final _messageController = StreamController<OrchestratorMessage>.broadcast();
  Stream<OrchestratorMessage> get messageStream => _messageController.stream;

  /// 初始化第二大脑
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🧠 初始化第二大脑...');

    // 加载用户画像
    _userProfile = await _databaseService.getUserProfile();

    // 初始化各层引擎
    _evolutionEngine.initialize();
    await _proactiveEngine.initialize();

    _isInitialized = true;
    debugPrint('✅ 第二大脑已就绪');

    // 启动后发送欢迎消息
    _sendWelcomeIfNeeded();
  }

  /// 处理用户输入（主入口）
  ///
  /// 协调三层架构处理用户输入：
  /// 1. 第一层：执行工具调用
  /// 2. 第二层：更新记忆/画像
  /// 3. 第三层：预测后续需求
  Future<String> processUserInput(
    String input, {
    Map<String, dynamic>? metadata,
  }) async {
    _setState(OrchestratorState.processing);

    try {
      // ===== 第一层：工具执行 =====
      debugPrint('🔧 第一层：执行工具调用');
      final toolCalls = _agentService.parseToolCalls(input);
      final toolResults = await _agentService.executeToolCalls(toolCalls);

      // 生成AI响应（使用AI服务生成自然回复）
      String response;
      if (toolCalls.isNotEmpty) {
        // 有工具调用，生成带工具结果的回复
        response = await _generateResponseWithTools(input, toolResults);
      } else {
        // 没有工具调用，使用AI服务生成回复
        response = await generateAIResponse(userInput: input);
      }

      // ===== 第二层：记忆进化 =====
      debugPrint('📝 第二层：学习并进化');
      await _evolutionEngine.recordConversation(
        userMessage: input,
        aiResponse: response,
        toolCalls: toolCalls,
      );

      // 如果涉及用户画像相关话题，触发即时进化
      if (_isProfileRelated(input)) {
        await _evolutionEngine.triggerEvolution();
      }

      // ===== 第三层：需求预测 =====
      debugPrint('🔮 第三层：预测需求');
      final predictedNeeds = await _predictionEngine.predictCurrentNeeds();
      final topNeed = predictedNeeds.isNotEmpty ? predictedNeeds.first : null;

      // 如果预测到高置信度需求，追加建议
      if (topNeed != null && topNeed.confidence > 0.8) {
        response = _appendSuggestion(response, topNeed);
      }

      // 广播消息
      _messageController.add(OrchestratorMessage(
        type: MessageType.userInput,
        content: input,
        metadata: {
          'toolCalls': toolCalls.length,
          'toolResults': toolResults.length,
          'predictedNeeds': predictedNeeds.length,
        },
      ));

      _setState(OrchestratorState.idle);
      return response;
    } catch (e, stack) {
      debugPrint('❌ 处理用户输入失败: $e');
      debugPrint(stack.toString());
      _setState(OrchestratorState.error);
      return '抱歉，处理时出现了问题。请重试或换一种方式表达。';
    }
  }

  /// 主动触发互动
  ///
  /// 由定时任务或事件触发
  Future<void> triggerProactiveEngagement() async {
    if (_currentState != OrchestratorState.idle) {
      debugPrint('⏸️ 协调器忙碌，跳过主动触发');
      return;
    }

    _setState(OrchestratorState.proactive);

    try {
      // 获取主动建议
      final suggestions = await _evolutionEngine.analyzeForProactiveEngagement();

      // 过滤并选择最高优先级的建议
      final highPriority = suggestions
          .where((s) => s.priority == SuggestionPriority.high ||
              s.priority == SuggestionPriority.urgent)
          .toList();

      if (highPriority.isNotEmpty) {
        final suggestion = highPriority.first;

        // 广播主动消息
        _messageController.add(OrchestratorMessage(
          type: MessageType.proactive,
          content: suggestion.content,
          metadata: {
            'suggestionType': suggestion.type.name,
            'priority': suggestion.priority.name,
          },
        ));

        debugPrint('📢 主动触发: ${suggestion.title}');
      }

      // 获取预测的需求
      final predictedNeeds = await _predictionEngine.predictCurrentNeeds();
      if (predictedNeeds.isNotEmpty) {
        debugPrint('🔮 预测到 ${predictedNeeds.length} 个需求');
        // 可以在这里预加载相关数据
      }
    } catch (e) {
      debugPrint('❌ 主动触发失败: $e');
    } finally {
      _setState(OrchestratorState.idle);
    }
  }

  /// 获取AI助手响应（带完整上下文）
  Future<String> generateAIResponse({
    required String userInput,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true,
  }) async {
    if (!_aiManager.hasAnyAvailableService) {
      return _generateOfflineResponse(userInput);
    }

    // 构建完整上下文
    final context = await _buildCompleteContext();

    // 如果启用工具，添加工具定义
    String systemPrompt = _buildSystemPrompt();
    if (enableTools) {
      systemPrompt += '\n\n${_agentService.getToolsDefinition()}';
    }

    final response = await _aiManager.askQuestion(
      userInput,
      context: [systemPrompt, context],
      conversationHistory: conversationHistory,
      enableTools: enableTools,
    );

    return response ?? _generateOfflineResponse(userInput);
  }

  /// 生成深度洞察报告
  Future<InsightReport> generateDeepInsight({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final end = endDate ?? DateTime.now();
    final start = startDate ?? end.subtract(const Duration(days: 7));

    return await _evolutionEngine.generateInsightReport(
      startDate: start,
      endDate: end,
    );
  }

  /// 获取用户当前状态摘要
  Future<UserStateSummary> getCurrentStateSummary() async {
    final profile = await _databaseService.getUserProfile();
    final predictedNeeds = await _predictionEngine.predictCurrentNeeds();
    final todayRecordings = await _getTodayRecordings();
    final pendingTodos = await _databaseService.getTodos(includeCompleted: false);

    return UserStateSummary(
      profile: profile,
      predictedNeeds: predictedNeeds,
      todayRecordingsCount: todayRecordings.length,
      pendingTodosCount: pendingTodos.length,
      emotionalState: await _getCurrentEmotionalState(),
    );
  }

  /// 清理资源
  void dispose() {
    _messageController.close();
    _proactiveEngine.dispose();
    _evolutionEngine.dispose();
  }

  // ==================== 私有方法 ====================

  void _setState(OrchestratorState state) {
    _currentState = state;
    debugPrint('🔄 状态: ${state.name}');
  }

  Future<void> _sendWelcomeIfNeeded() async {
    // 检查是否今天已经发过欢迎
    final today = DateTime.now();
    final lastWelcome = await _getLastWelcomeTime();

    if (lastWelcome == null ||
        lastWelcome.day != today.day ||
        lastWelcome.month != today.month) {
      // 发送个性化欢迎
      final profile = _userProfile;
      final name = profile?.name ?? '';

      _messageController.add(OrchestratorMessage(
        type: MessageType.welcome,
        content: '欢迎回来${name.isNotEmpty ? '，$name' : ''}！我是你的第二大脑，一直在学习了解你。',
        metadata: {'isFirstToday': true},
      ));

      await _recordWelcomeTime();
    }
  }

  Future<String> _generateResponseWithTools(
    String input,
    List<ToolResult> toolResults,
  ) async {
    // 简化实现：返回工具执行结果摘要
    final buffer = StringBuffer();
    for (final result in toolResults) {
      buffer.writeln(result.message);
    }
    return buffer.toString();
  }

  bool _isProfileRelated(String input) {
    final keywords = [
      '我', '喜欢', '想要', '计划', '目标', '工作', '家庭',
      '朋友', '兴趣', '习惯', '性格', '困惑', '梦想',
    ];
    return keywords.any((k) => input.contains(k));
  }

  String _appendSuggestion(String response, PredictedNeed need) {
    return '$response\n\n💡 顺便问一句：${need.description}？';
  }

  String _buildSystemPrompt() {
    return '''你是MemoryPal，用户的第二大脑。

你的使命：
1. **深度陪伴** - 不仅是工具，更是理解用户的伙伴
2. **主动进化** - 每次交互都在加深对用户的理解
3. **预测需求** - 在用户开口前就准备好帮助
4. **终身学习** - 陪伴用户成长，见证人生历程

交流原则：
- 用温暖、自然的语气，像老朋友一样
- 记住用户的偏好、习惯和上下文
- 主动关联相关记忆和经历
- 在适当时机提出有价值的建议

记住：你是用户可以依赖终身的第二大脑。''';
  }

  Future<String> _buildCompleteContext() async {
    final buffer = StringBuffer();

    // 添加画像摘要
    final profile = await _databaseService.getUserProfile();
    if (profile != null) {
      buffer.writeln('用户画像：');
      if (profile.occupation != null) buffer.writeln('- 职业：${profile.occupation}');
      if (profile.interests.isNotEmpty) {
        buffer.writeln('- 兴趣：${profile.interests.take(5).join('、')}');
      }
    }

    // 添加今日概览
    final todayRecordings = await _getTodayRecordings();
    buffer.writeln('\n今日记录：${todayRecordings.length}条');

    // 添加待办
    final todos = await _databaseService.getTodos(includeCompleted: false);
    buffer.writeln('待办事项：${todos.length}项');

    return buffer.toString();
  }

  String _generateOfflineResponse(String input) {
    return '我了解你的意思。目前处于离线模式，但我仍在学习了解你。';
  }

  Future<List<dynamic>> _getTodayRecordings() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final recordings = await _databaseService.getRecordings(limit: 100);
    return recordings.where((r) => r.startTime.isAfter(startOfDay)).toList();
  }

  Future<EmotionalState?> _getCurrentEmotionalState() async {
    // TODO: 实现情绪状态查询
    return null;
  }

  Future<DateTime?> _getLastWelcomeTime() async {
    // TODO: 实现查询
    return null;
  }

  Future<void> _recordWelcomeTime() async {
    // TODO: 实现记录
  }
}

// ==================== 数据模型 ====================

enum OrchestratorState {
  idle,
  processing,
  proactive,
  error,
}

enum MessageType {
  userInput,
  aiResponse,
  proactive,
  welcome,
  insight,
}

class OrchestratorMessage {
  final MessageType type;
  final String content;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  OrchestratorMessage({
    required this.type,
    required this.content,
    this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class UserStateSummary {
  final UserProfile? profile;
  final List<PredictedNeed> predictedNeeds;
  final int todayRecordingsCount;
  final int pendingTodosCount;
  final EmotionalState? emotionalState;

  UserStateSummary({
    required this.profile,
    required this.predictedNeeds,
    required this.todayRecordingsCount,
    required this.pendingTodosCount,
    this.emotionalState,
  });
}
