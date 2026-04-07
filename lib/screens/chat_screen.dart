import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/kimi_service.dart';
import '../services/whisper_service.dart';
import '../services/recording_service.dart';
import '../services/vector_search_service.dart';
import '../services/settings_service.dart';
import '../services/agent_service.dart';
import '../services/second_brain_orchestrator.dart';
import '../services/profile_evolution_engine.dart';
import '../utils/permission_manager.dart';
import '../models/user_profile.dart';

/// AI对话界面 - 与助理对话、自然语言检索、智能问答
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _databaseService = DatabaseService();
  final _kimiService = KimiService();
  final _whisperService = WhisperService();
  final _vectorSearchService = VectorSearchService();
  final _settingsService = SettingsService();
  final _agentService = AgentService();
  final _secondBrain = SecondBrainOrchestrator();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  // 第二大脑消息流订阅
  StreamSubscription? _orchestratorSubscription;

  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _voiceInputPath;

  final _recordingService = RecordingService();

  // 用户画像
  UserProfile? _userProfile;
  bool _isLoadingProfile = true;

  // 快捷询问选项 - 更自然的对话引导
  List<String> get _quickQuestions {
    final questions = <String>[];

    // 根据用户画像个性化快捷问题
    if (_userProfile?.occupation != null) {
      questions.add('最近工作有什么进展？');
    }
    if (_userProfile?.shortTermGoals != null) {
      questions.add('我的目标完成得怎么样了？');
    }

    questions.addAll([
      '总结一下我最近的状态',
      '根据我的习惯，给我一些建议',
      '我今天有什么安排吗？',
      '帮我分析最近的思考模式',
    ]);

    return questions.take(4).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadChatHistory();
    _setupAgentCallbacks();
    _initializeSecondBrain();
  }

  // 初始化第二大脑系统
  Future<void> _initializeSecondBrain() async {
    await _secondBrain.initialize();

    // 订阅第二大脑的消息流
    _orchestratorSubscription = _secondBrain.messageStream.listen((message) {
      switch (message.type) {
        case MessageType.welcome:
          _addAssistantMessage(message.content);
          break;
        case MessageType.proactive:
          _addAssistantMessage(
            message.content,
            isProactive: true,
          );
          break;
        default:
          break;
      }
    });
  }

  // 添加助理消息（支持主动消息标识）
  void _addAssistantMessage(String content, {bool isProactive = false}) {
    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(
        isUser: false,
        content: content,
        timestamp: DateTime.now(),
        isProactive: isProactive,
      ));
    });

    _scrollToBottom();

    // 保存到数据库
    _databaseService.insertChatMessage({
      'is_user': 0,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_search_result': 0,
      'is_proactive': isProactive ? 1 : 0,
    });
  }

  // 设置智能体回调
  void _setupAgentCallbacks() {
    _agentService.onPlayRecording = (path) {
      // 使用Navigator跳转到播放页面
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在打开录音播放...')),
        );
      }
    };

    _agentService.onStartRecording = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开始录音...')),
        );
      }
    };

    _agentService.onShowTodoNotification = (content) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(content), duration: const Duration(seconds: 2)),
        );
      }
    };
  }

  // 加载对话历史
  Future<void> _loadChatHistory() async {
    try {
      final messages = await _databaseService.getChatMessages(limit: 100);
      if (messages.isNotEmpty) {
        setState(() {
          _messages.clear();
          for (final m in messages) {
            _messages.add(ChatMessage(
              isUser: (m['is_user'] as int) == 1,
              content: m['content'] as String,
              timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
              isSearchResult: (m['is_search_result'] as int? ?? 0) == 1,
            ));
          }
        });
      } else {
        _addWelcomeMessage();
      }
    } catch (e) {
      debugPrint('加载对话历史失败: $e');
      _addWelcomeMessage();
    }
  }

  // 加载用户画像
  Future<void> _loadUserProfile() async {
    try {
      final profile = await _databaseService.getUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('加载用户画像失败: $e');
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  void _addWelcomeMessage() {
    String welcomeText;

    if (_userProfile != null) {
      final name = _userProfile!.name ?? '';
      final occupation = _userProfile!.occupation;
      final interests = _userProfile!.interests.take(2).toList();

      final buffer = StringBuffer();
      buffer.write('你好${name.isNotEmpty ? name : ''}！');
      buffer.write('我是你的MemoryPal智能助理。\n\n');

      if (occupation != null && interests.isNotEmpty) {
        buffer.write('作为$occupation，你对${interests.join('、')}充满热情。');
        buffer.write('我会基于这些了解为你提供个性化帮助。\n\n');
      } else if (occupation != null) {
        buffer.write('我了解你的职业背景，可以针对性地为你服务。\n\n');
      } else if (interests.isNotEmpty) {
        buffer.write('我知道你对${interests.join('、')}感兴趣，');
        buffer.write('会据此给出相关建议。\n\n');
      }

      buffer.write('我可以：\n');
      buffer.write('💬 与你自由对话，基于你的画像提供建议\n');
      buffer.write('📝 记录和分析你的生活与思考\n');
      buffer.write('🎯 帮你追踪目标和习惯养成\n');
      buffer.write('💡 主动发现你关心的话题\n\n');
      buffer.write('想聊点什么？比如：\n');
      buffer.write('"根据我的习惯给我一些建议"\n');
      buffer.write('"分析一下我最近的状态"');

      welcomeText = buffer.toString();
    } else {
      welcomeText = '你好！我是你的MemoryPal智能助理。\n\n'
          '我可以：\n'
          '💬 与你自由对话，回答各种问题\n'
          '📝 帮你记录和整理记忆\n'
          '🎯 提取待办和追踪目标\n'
          '💡 分析习惯并提供建议\n\n'
          '建议先在"我的"页面完善你的画像，我能更好地为你服务。\n\n'
          '有什么想聊的吗？';
    }

    _messages.add(ChatMessage(
      isUser: false,
      content: welcomeText,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _orchestratorSubscription?.cancel();
    _secondBrain.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final userMessage = ChatMessage(
      isUser: true,
      content: content,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isProcessing = true;
    });

    // 保存用户消息到数据库
    await _databaseService.insertChatMessage({
      'is_user': 1,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_search_result': 0,
    });

    _textController.clear();
    _scrollToBottom();

    // 分析用户意图并响应
    final response = await _processQuery(content);

    final assistantMessage = ChatMessage(
      isUser: false,
      content: response,
      timestamp: DateTime.now(),
      isSearchResult: response.contains('📁') || response.contains('📝'),
    );

    setState(() {
      _messages.add(assistantMessage);
      _isProcessing = false;
    });

    // 保存AI回复到数据库
    await _databaseService.insertChatMessage({
      'is_user': 0,
      'content': response,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_search_result': assistantMessage.isSearchResult ? 1 : 0,
    });

    _scrollToBottom();
  }

  Future<String> _processQuery(String query) async {
    final lowerQuery = query.toLowerCase();

    // 只保留明确的数据查询指令，其他全部交给第二大脑处理
    // 1. 精确待办查询（用户明确要查待办列表）
    final todoPatterns = ['列出待办', '显示待办', '查看待办', '我的待办清单'];
    if (todoPatterns.any((p) => lowerQuery.contains(p))) {
      return await _getTodosResponse();
    }

    // 2. 精确文件查询
    final filePatterns = ['列出文件', '显示导入的文件', '我导入的文件'];
    if (filePatterns.any((p) => lowerQuery.contains(p))) {
      return await _searchFiles(query);
    }

    // 其他所有问题交给第二大脑处理（三层架构完整处理）
    return await _secondBrain.processUserInput(query);
  }

  Future<String> _getTodosResponse() async {
    final todos = await _databaseService.getTodos(includeCompleted: false);

    if (todos.isEmpty) {
      return '你当前没有待办事项。需要我帮你从最近的录音中提取吗？';
    }

    final buffer = StringBuffer();
    buffer.writeln('📋 你的待办事项 (${todos.length}项)：\n');

    for (var i = 0; i < todos.take(5).length; i++) {
      final todo = todos[i];
      final priority = todo['priority'] as String? ?? 'medium';
      final priorityEmoji = priority == 'high' ? '🔴' : priority == 'medium' ? '🟡' : '🟢';
      buffer.writeln('$priorityEmoji ${todo['content']}');

      final deadline = todo['deadline'] as int?;
      if (deadline != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(deadline);
        final diff = date.difference(DateTime.now());
        if (diff.inDays >= 0) {
          buffer.writeln('   截止: ${date.month}/${date.day} (${diff.inDays}天后)');
        } else {
          buffer.writeln('   ⚠️ 已逾期 ${-diff.inDays} 天');
        }
      }
      buffer.writeln('');
    }

    if (todos.length > 5) {
      buffer.writeln('...还有 ${todos.length - 5} 项待办');
    }

    return buffer.toString();
  }

  Future<String> _getRecentContentResponse(String query) async {
    DateTime startDate;
    final now = DateTime.now();

    if (query.contains('今天')) {
      startDate = DateTime(now.year, now.month, now.day);
    } else if (query.contains('昨天')) {
      startDate = now.subtract(const Duration(days: 1));
    } else if (query.contains('上周') || query.contains('最近一周')) {
      startDate = now.subtract(const Duration(days: 7));
    } else {
      startDate = now.subtract(const Duration(days: 7)); // 默认最近一周
    }

    final recordings = await _databaseService.getRecordings(limit: 100);
    final notes = await _databaseService.getNotes(limit: 100);

    final recentRecordings = recordings.where((r) => r.startTime.isAfter(startDate)).toList();
    final recentNotes = notes.where((n) => n.createdAt.isAfter(startDate)).toList();

    if (recentRecordings.isEmpty && recentNotes.isEmpty) {
      return '这段时间内没有记录。开始录音或记笔记来记录你的生活吧！';
    }

    final buffer = StringBuffer();
    buffer.writeln('📊 ${query.contains('今天') ? '今天' : query.contains('昨天') ? '昨天' : '最近'}的记录概况：\n');
    buffer.writeln('🎙️ ${recentRecordings.length} 条录音');
    buffer.writeln('📝 ${recentNotes.length} 条笔记\n');

    if (recentRecordings.isNotEmpty) {
      buffer.writeln('🎙️ 最新录音：');
      for (final r in recentRecordings.take(3)) {
        buffer.writeln('• ${r.startTime.hour}:${r.startTime.minute.toString().padLeft(2, '0')} ${r.transcript?.substring(0, r.transcript!.length > 30 ? 30 : r.transcript!.length) ?? '无转写'}...');
      }
      buffer.writeln('');
    }

    if (recentNotes.isNotEmpty) {
      buffer.writeln('📝 最新笔记：');
      for (final n in recentNotes.take(3)) {
        buffer.writeln('• ${n.title}');
      }
    }

    return buffer.toString();
  }

  Future<String> _searchByPersonOrTopic(String query) async {
    // 使用语义搜索
    final result = await _vectorSearchService.semanticSearch(query, limit: 5);
    return _vectorSearchService.generateAnswer(query, result);
  }

  Future<String> _searchFiles(String query) async {
    final files = await _databaseService.getImportedFiles(limit: 50);

    if (files.isEmpty) {
      return '你还没有导入任何文件。可以在首页点击"导入文件"添加文档。';
    }

    final buffer = StringBuffer();
    buffer.writeln('📁 你的文件 (${files.length}个)：\n');

    for (final f in files.take(10)) {
      final fileName = f['file_name'] as String? ?? '未命名';
      final fileType = f['file_type'] as String? ?? '未知';
      final typeIcon = _getFileTypeIcon(fileType);
      buffer.writeln('$typeIcon $fileName');
    }

    if (files.length > 10) {
      buffer.writeln('\n...还有 ${files.length - 10} 个文件');
    }

    return buffer.toString();
  }

  String _getFileTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return '📕';
      case 'doc':
      case 'docx':
        return '📘';
      case 'ppt':
      case 'pptx':
        return '📊';
      case 'txt':
      case 'md':
        return '📝';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return '🖼️';
      default:
        return '📄';
    }
  }

  Future<String> _getWorkSummary() async {
    final recordings = await _databaseService.getRecordings(limit: 30);
    final notes = await _databaseService.getNotes(limit: 30);

    // 简单的关键词匹配分析
    final workKeywords = ['项目', '会议', '工作', '汇报', '方案', '客户', '需求'];
    int workMentions = 0;

    for (final r in recordings) {
      if (r.transcript != null && workKeywords.any((k) => r.transcript!.contains(k))) {
        workMentions++;
      }
    }

    for (final n in notes) {
      if (workKeywords.any((k) => n.content.contains(k) || n.title.contains(k))) {
        workMentions++;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('💼 工作情况概览\n');

    if (workMentions > 0) {
      buffer.writeln('最近你记录了 $workMentions 条工作相关内容');
      buffer.writeln('\n从记录中发现你可能在关注：');
      buffer.writeln('• 项目进展跟踪');
      buffer.writeln('• 会议讨论');
      buffer.writeln('• 工作汇报准备');
    } else {
      buffer.writeln('最近没有明显的工作相关记录。');
      buffer.writeln('\n提示：多录音记录工作想法，我可以帮你更好地管理。');
    }

    return buffer.toString();
  }

  /// AI智能体对话 - 支持工具调用循环
  ///
  /// 智能体执行流程：
  /// 1. 用户输入 → 构建上下文 → 发送给AI
  /// 2. AI响应 → 解析是否包含工具调用
  /// 3. 如有工具调用 → 执行工具 → 将结果返回给AI
  /// 4. AI根据工具结果生成最终回复
  Future<String> _askAI(String question, {int maxToolRounds = 3}) async {
    // 构建完整的上下文
    final profileContext = _buildFullProfileContext();
    final userDataContext = await _buildUserDataContext();

    // 诊断日志
    debugPrint('[_askAI] KimiService诊断: isAvailable=${_kimiService.isAvailable}, apiKey=${_kimiService.apiKey != null ? "已设置(长度:${_kimiService.apiKey!.length})" : "未设置"}');

    // 先尝试用Kimi API
    if (_kimiService.isAvailable) {
      debugPrint('Kimi API可用，启用智能体模式...');

      final context = <String>[];

      // 添加系统角色定义
      context.add('【你的角色】你是MemoryPal，用户的24小时智能助理。你深度了解用户，基于用户画像和记忆数据提供个性化服务。');

      // 添加用户画像（完整版）
      if (profileContext.isNotEmpty) {
        context.add(profileContext);
      }

      // 添加用户数据摘要
      if (userDataContext.isNotEmpty) {
        context.add(userDataContext);
      }

      try {
        // 构建对话历史
        var history = await _buildConversationHistoryForAI();

        // 使用增强的系统提示词
        final enhancedQuestion = _buildEnhancedPrompt(question);

        // 智能体循环：支持多轮工具调用
        String? finalResponse;
        var currentRound = 0;

        while (currentRound < maxToolRounds) {
          currentRound++;
          debugPrint('智能体执行轮次: $currentRound/$maxToolRounds');

          // 发送请求给AI
          final aiResponse = await _kimiService.askQuestion(
            currentRound == 1 ? enhancedQuestion : '请根据工具执行结果继续',
            context: context,
            conversationHistory: history,
            enableTools: true, // 启用工具调用
          );

          if (aiResponse == null || aiResponse.isEmpty) {
            debugPrint('AI响应为空，中断智能体循环');
            break;
          }

          // 解析是否包含工具调用
          final toolCalls = _agentService.parseToolCalls(aiResponse);

          if (toolCalls.isEmpty) {
            // 没有工具调用，这是最终回复
            debugPrint('AI响应不含工具调用，返回最终回复');
            finalResponse = aiResponse;
            break;
          }

          // 执行工具调用
          debugPrint('检测到 ${toolCalls.length} 个工具调用，开始执行...');
          final toolResults = await _agentService.executeToolCalls(toolCalls);

          // 构建工具结果上下文
          final toolResultsContext = _agentService.buildToolResultsContext(toolResults);

          // 更新对话历史，包含工具调用和结果
          history.add({'role': 'assistant', 'content': aiResponse});
          history.add({'role': 'user', 'content': '工具执行结果：$toolResultsContext'});

          // 如果达到最大轮次，直接返回当前响应
          if (currentRound >= maxToolRounds) {
            finalResponse = aiResponse;
            break;
          }
        }

        if (finalResponse != null && finalResponse.isNotEmpty) {
          // 清理响应中的工具调用标记，保留给用户友好的文本
          return _cleanToolCallsFromResponse(finalResponse);
        }
      } catch (e, stack) {
        debugPrint('Kimi API调用失败: $e');
        debugPrint(stack.toString());
      }
    } else {
      debugPrint('Kimi API不可用，使用离线模式 (API Key: ${_kimiService.apiKey != null ? "已设置" : "未设置"})');
    }

    // 离线模式
    return _offlineAnswer(question, profileContext: profileContext);
  }

  /// 清理响应中的工具调用标记
  String _cleanToolCallsFromResponse(String response) {
    // 移除 ```tool ... ``` 代码块，但保留其他内容
    final toolBlockPattern = RegExp(r'```tool\s*\n.*?\n```\s*\n?', dotAll: true);
    return response.replaceAll(toolBlockPattern, '').trim();
  }

  // 构建增强的提示词
  String _buildEnhancedPrompt(String question) {
    // 检测问题类型并添加引导
    final lower = question.toLowerCase();

    // 分析/建议类问题
    final analysisKeywords = ['分析', '建议', '为什么', '怎么办', '如何', '怎样', '推荐'];
    if (analysisKeywords.any((k) => lower.contains(k))) {
      return '$question\n\n【请基于用户画像和习惯，给出深度分析和个性化建议】';
    }

    // 总结类问题
    final summaryKeywords = ['总结', '概括', '回顾', '怎么样', '状态'];
    if (summaryKeywords.any((k) => lower.contains(k))) {
      return '$question\n\n【请综合用户画像和近期记录，给出全面总结】';
    }

    // 开放式对话
    return '$question\n\n【请自然回应，可以主动关联用户画像中的信息，体现你作为智能助理的个性化】';
  }

  // 构建文本格式的对话历史（用于上下文提示）
  Future<String> _buildConversationHistory() async {
    try {
      // 获取最近10条对话（不包括当前这条）
      final messages = await _databaseService.getChatMessages(limit: 10);
      if (messages.length <= 1) return ''; // 只有当前消息，没有历史

      final buffer = StringBuffer();
      // 跳过最后一条（当前用户消息）
      for (int i = 0; i < messages.length - 1; i++) {
        final m = messages[i];
        final role = (m['is_user'] as int) == 1 ? '用户' : '助理';
        final content = m['content'] as String;
        // 截取前100字符避免太长
        final shortContent = content.length > 100 ? '${content.substring(0, 100)}...' : content;
        buffer.writeln('$role: $shortContent');
      }
      return buffer.toString();
    } catch (e) {
      debugPrint('构建对话历史失败: $e');
      return '';
    }
  }

  // 构建AI API格式的对话历史
  Future<List<Map<String, String>>> _buildConversationHistoryForAI() async {
    try {
      // 获取最近6条对话（不包括当前这条）
      final messages = await _databaseService.getChatMessages(limit: 7);
      if (messages.length <= 1) return [];

      final history = <Map<String, String>>[];
      // 跳过最后一条（当前用户消息），最多取6条历史
      final startIdx = messages.length > 7 ? messages.length - 7 : 0;
      for (int i = startIdx; i < messages.length - 1; i++) {
        final m = messages[i];
        final role = (m['is_user'] as int) == 1 ? 'user' : 'assistant';
        final content = m['content'] as String;
        history.add({'role': role, 'content': content});
      }
      return history;
    } catch (e) {
      debugPrint('构建AI对话历史失败: $e');
      return [];
    }
  }

  // 构建用户数据上下文
  Future<String> _buildUserDataContext() async {
    try {
      final recordings = await _databaseService.getRecordings(limit: 30);
      final notes = await _databaseService.getNotes(limit: 20);
      final todos = await _databaseService.getTodos(includeCompleted: false);

      final buffer = StringBuffer();
      buffer.writeln('【用户数据概览】');

      // 统计信息
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final recentRecordings = recordings.where((r) => r.startTime.isAfter(weekAgo)).toList();

      buffer.writeln('近7天记录：${recentRecordings.length}条录音，${notes.where((n) => n.createdAt.isAfter(weekAgo)).length}条笔记');
      buffer.writeln('待办事项：${todos.length}项未完成');

      // 添加最近的转写内容摘要
      if (recentRecordings.isNotEmpty) {
        buffer.writeln('\n【近期录音摘要】');
        for (final r in recentRecordings.take(5)) {
          if (r.transcript != null && r.transcript!.isNotEmpty) {
            final shortText = r.transcript!.length > 80
                ? '${r.transcript!.substring(0, 80)}...'
                : r.transcript!;
            buffer.writeln('• ${r.startTime.month}/${r.startTime.day} ${r.title ?? ""}: $shortText');
          }
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('构建用户数据上下文失败: $e');
      return '';
    }
  }

  // 构建完整用户画像上下文
  String _buildFullProfileContext() {
    if (_userProfile == null) return '';

    final buffer = StringBuffer();
    buffer.writeln('【用户画像】');

    final p = _userProfile!;

    // 基础信息
    final basicInfo = <String>[];
    if (p.name != null && p.name!.isNotEmpty) basicInfo.add('姓名:${p.name}');
    if (p.gender != null) basicInfo.add('性别:${p.gender}');
    if (p.age != null) basicInfo.add('年龄:${p.age}岁');
    if (p.occupation != null && p.occupation!.isNotEmpty) basicInfo.add('职业:${p.occupation}');
    if (p.address != null && p.address!.isNotEmpty) basicInfo.add('所在地:${p.address}');
    if (basicInfo.isNotEmpty) {
      buffer.writeln('基础信息：${basicInfo.join('，')}');
    }

    // 兴趣偏好
    if (p.interests.isNotEmpty) {
      buffer.writeln('兴趣爱好：${p.interests.join('、')}');
    }

    // 生活习惯
    if (p.habits.isNotEmpty) {
      buffer.writeln('生活习惯：${p.habits.join('、')}');
    }

    // 性格特点
    if (p.personality != null && p.personality!.isNotEmpty) {
      buffer.writeln('性格特点：${p.personality}');
    }

    // 优势特长
    if (p.strengths != null && p.strengths!.isNotEmpty) {
      buffer.writeln('优势特长：${p.strengths}');
    }

    // 社交关系
    final socialInfo = <String>[];
    if (p.familyMembers != null && p.familyMembers!.isNotEmpty) {
      socialInfo.add('家庭成员：${p.familyMembers}');
    }
    if (p.workCircle != null && p.workCircle!.isNotEmpty) {
      socialInfo.add('工作关系：${p.workCircle}');
    }
    if (p.socialCircle != null && p.socialCircle!.isNotEmpty) {
      socialInfo.add('社交圈：${p.socialCircle}');
    }
    if (socialInfo.isNotEmpty) {
      buffer.writeln('社交关系：${socialInfo.join('，')}');
    }

    // 目标与困惑
    if (p.shortTermGoals != null && p.shortTermGoals!.isNotEmpty) {
      buffer.writeln('短期目标：${p.shortTermGoals}');
    }
    if (p.longTermDreams != null && p.longTermDreams!.isNotEmpty) {
      buffer.writeln('长期愿景：${p.longTermDreams}');
    }
    if (p.currentConfusions != null && p.currentConfusions!.isNotEmpty) {
      buffer.writeln('当前困惑：${p.currentConfusions}');
    }

    return buffer.toString();
  }

  // 简化的用户画像（用于离线模式）
  String _buildProfileContext() {
    if (_userProfile == null) return '';

    final parts = <String>[];
    final p = _userProfile!;

    if (p.name != null && p.name!.isNotEmpty) parts.add('姓名:${p.name}');
    if (p.occupation != null && p.occupation!.isNotEmpty) parts.add('职业:${p.occupation}');
    if (p.interests.isNotEmpty) parts.add('兴趣:${p.interests.take(3).join(',')}');
    if (p.habits.isNotEmpty) parts.add('习惯:${p.habits.take(3).join(',')}');
    if (p.shortTermGoals != null && p.shortTermGoals!.isNotEmpty) {
      parts.add('近期目标:${p.shortTermGoals}');
    }

    return parts.join('；');
  }

  String _offlineAnswer(String question, {String profileContext = ''}) {
    final lower = question.toLowerCase();
    final userName = _userProfile?.name;
    final greeting = userName != null && userName.isNotEmpty ? '你好$userName！' : '你好！';

    // 基础问候
    if (lower.contains('你好') || lower.contains('是谁') || lower.contains('介绍')) {
      return '$greeting我是MemoryPal，${_userProfile != null ? '为你量身定制的' : ''}24小时智能助理。\n\n我${_userProfile != null ? '了解你的偏好和习惯，可以' : '可以'}帮你记录生活、整理思路、分析习惯、提醒待办。\n\n${_userProfile != null ? "根据你的资料，我知道你是${_userProfile!.occupation ?? '职场人士'}，对${_userProfile!.interests.take(2).join('、')}感兴趣。" : ''}';
    }

    // 隐私相关
    if (lower.contains('隐私') || lower.contains('安全') || lower.contains('数据')) {
      return '🔒 隐私保护说明\n\n• 所有数据（录音、笔记、画像）仅存储在本地\n• 云端AI分析可选，仅传输文本摘要\n• 你可以随时导出或删除所有数据\n• 离线模式下所有功能仍然可用\n\n你的数据永远属于你。';
    }

    // 功能介绍
    if (lower.contains('功能') || lower.contains('能做什么') || lower.contains('帮助') || lower.contains('用法')) {
      return '$greeting作为${_userProfile?.occupation != null ? '${_userProfile!.occupation}的' : '你的'}智能助理，我可以：\n\n• 📱 24小时环境录音，记录生活点滴\n• 📝 语音/文字笔记，快速记录想法\n• 💡 基于你的画像和习惯提供建议\n• 🔍 自然语言搜索所有记忆\n• ⏰ 智能识别待办并提醒\n• 📊 定期总结你的生活状态\n\n${_buildPersonalizedHint()}';
    }

    // 基于用户画像的自由回应
    if (_userProfile != null) {
      final p = _userProfile!;

      // 兴趣相关
      if (lower.contains('兴趣') || lower.contains('喜欢') || lower.contains('爱好')) {
        if (p.interests.isNotEmpty) {
          return '根据你的资料，你对${p.interests.join('、')}感兴趣。\n\n建议：多记录与兴趣相关的内容，我可以帮你深入分析和整理。比如你可以录音记录${p.interests.first}相关的想法，我会自动归类。';
        }
      }

      // 目标相关
      if (lower.contains('目标') || lower.contains('计划') || lower.contains('规划')) {
        final goals = [];
        // 安全获取字符串值
        final shortTermGoals = p.shortTermGoals?.toString();
        final longTermDreams = p.longTermDreams?.toString();
        // 过滤掉无效值（包含Instance of的对象表示）
        if (shortTermGoals != null && !shortTermGoals.contains('Instance of')) {
          goals.add('短期目标：$shortTermGoals');
        }
        if (longTermDreams != null && !longTermDreams.contains('Instance of')) {
          goals.add('长期愿景：$longTermDreams');
        }

        if (goals.isNotEmpty) {
          return '你当前的目标：\n${goals.join('\n')}\n\n需要我帮你制定行动计划或设置提醒吗？你可以录音告诉我具体想法。';
        }
      }

      // 工作/职业相关
      if (lower.contains('工作') || lower.contains('职业') || lower.contains('事业')) {
        if (p.occupation != null && p.occupation!.isNotEmpty) {
          return '作为$p.occupation，你的${p.workCircle != null ? '工作圈包括${p.workCircle}，' : ''}我可以帮你：\n• 记录工作灵感和会议内容\n• 整理项目进展和待办事项\n• 分析工作模式提供效率建议\n\n有具体的工作内容想要讨论吗？';
        }
      }

      // 性格/自我认知
      if (lower.contains('性格') || lower.contains('特点') || lower.contains('优势')) {
        final traits = [];
        if (p.personality != null) traits.add('性格：${p.personality}');
        if (p.strengths != null) traits.add('优势：${p.strengths}');

        if (traits.isNotEmpty) {
          return '根据我对你的了解：\n${traits.join('\n')}\n\n这些特质让你在${_userProfile?.occupation ?? '工作'}中很有优势。建议持续记录相关经历，我可以帮你更好地发挥长处。';
        }
      }

      // 生活/习惯
      if (lower.contains('习惯') || lower.contains('生活') || lower.contains('日常')) {
        if (p.habits.isNotEmpty) {
          return '你的生活包括：${p.habits.join('、')}。\n\n基于这些习惯，我可以：\n• 在合适的时间给出相关提醒\n• 分析习惯模式，发现优化空间\n• 关联相关录音和笔记内容';
        }
      }

      // 社交关系
      if (lower.contains('家庭') || lower.contains('朋友') || lower.contains('关系')) {
        final relations = [];
        if (p.familyMembers != null) relations.add('家人：${p.familyMembers}');
        if (p.socialCircle != null) relations.add('朋友：${p.socialCircle}');

        if (relations.isNotEmpty) {
          return '${relations.join('，')}都是对你来说重要的人。\n\n建议记录与他们的重要时刻，我可以帮你记住生日、重要事件等，维护好这些关系。';
        }
      }

      // 困惑/建议
      if (lower.contains('困惑') || lower.contains('烦恼') || lower.contains('问题')) {
        if (p.currentConfusions != null && p.currentConfusions!.isNotEmpty) {
          return '我了解到你目前的困惑：${p.currentConfusions}\n\n建议通过录音记录思考过程，我可以帮你梳理思路。也可以定期回顾这些困惑的进展。';
        }
      }
    }

    // 通用自由对话回复
    final hasApiKey = _kimiService.apiKey != null;
    final buffer = StringBuffer();

    buffer.writeln('$greeting');

    if (_userProfile != null) {
      buffer.writeln('作为了解你的助理，我注意到你是${_userProfile!.occupation ?? '职场人士'}。');
    }

    buffer.writeln('');
    buffer.writeln('关于"$question"，我想了解更多背景才能给你更好的建议。');
    buffer.writeln('');

    if (!hasApiKey) {
      buffer.writeln('⚠️ 当前处于离线模式，我的回答基于本地规则。');
      buffer.writeln('如需更深度的AI对话：');
      buffer.writeln('1. 前往 设置 → AI设置');
      buffer.writeln('2. 配置Kimi API Key（从 kimi.com 获取）');
      buffer.writeln('');
    }

    buffer.writeln('💡 试试这样问我：');
    buffer.writeln('• "根据我的习惯给我一些建议"');
    buffer.writeln('• "总结一下我最近的状态"');
    buffer.writeln('• "我的目标完成得怎么样了"');

    if (_userProfile != null) {
      buffer.writeln('• "基于我的性格，你觉得我适合做什么"');
    }

    return buffer.toString();
  }

  // 构建个性化提示
  String _buildPersonalizedHint() {
    final hints = <String>[];

    if (_userProfile?.occupation != null) {
      hints.add('💼 试试问我工作相关的问题');
    }
    if (_userProfile?.interests.isNotEmpty == true) {
      hints.add('🎯 询问你的兴趣相关记录');
    }
    if (hints.isEmpty) {
      hints.add('💡 试着问我："我最近有什么待办？"');
      hints.add('💡 或："帮我找一下会议纪要"');
    }

    return hints.take(2).join('\n');
  }

  // 开始语音输入录音
  Future<void> _startVoiceInput() async {
    // 检查麦克风权限
    final hasPermission = await PermissionManager().checkMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能语音输入')),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });

    // 启动计时器
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _recordingSeconds++;
      });
    });

    // 开始录音（使用临时文件）
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _voiceInputPath = '${tempDir.path}/voice_input_$timestamp.wav';

      await _recordingService.startRecordingForTranscription(_voiceInputPath!);
    } catch (e) {
      debugPrint('启动语音输入录音失败: $e');
      _stopVoiceInput();
    }
  }

  // 停止语音输入并进行转写
  Future<void> _stopVoiceInput() async {
    _recordingTimer?.cancel();

    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    // 停止录音
    await _recordingService.stopRecordingForTranscription();

    // 如果录音太短，放弃
    if (_recordingSeconds < 1) {
      _voiceInputPath = null;
      return;
    }

    // 显示转写中
    setState(() {
      _isTranscribing = true;
    });

    try {
      // 调用Whisper进行转写
      if (_voiceInputPath != null) {
        final result = await _whisperService.transcribe(_voiceInputPath!);

        if (result != null && result.text.isNotEmpty) {
          setState(() {
            _textController.text = result.text;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('未能识别语音，请重试')),
            );
          }
        }

        // 清理临时文件
        final file = File(_voiceInputPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _voiceInputPath = null;
      }
    } catch (e) {
      debugPrint('语音转写失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音转写失败，请检查网络或重试')),
        );
      }
    } finally {
      setState(() {
        _isTranscribing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.blue),
            SizedBox(width: 8),
            Text('与助理对话'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // TODO: 查看对话历史
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 快捷询问区域（仅在消息较少时显示）
          if (_messages.length <= 2)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '快捷询问',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickQuestions.map((q) => ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _sendMessage(q),
                    )).toList(),
                  ),
                ],
              ),
            ),

          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessageItem(_messages[index]),
            ),
          ),

          // 输入区域
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // 语音输入按钮
                  GestureDetector(
                    onTapDown: (_) => _startVoiceInput(),
                    onTapUp: (_) => _stopVoiceInput(),
                    onTapCancel: () => _stopVoiceInput(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: _isRecording ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 文本输入框
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: _isTranscribing
                            ? '正在识别语音...'
                            : _isRecording
                                ? '录音中 ${_recordingSeconds}s...'
                                : '输入文字或按住麦克风说话...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                      enabled: !_isProcessing && !_isTranscribing && !_isRecording,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 发送按钮
                  if (_isProcessing || _isTranscribing)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: () => _sendMessage(_textController.text),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? Colors.blue.shade100
                    : message.isSearchResult
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: message.isUser ? Colors.black87 : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

/// 聊天消息模型
class ChatMessage {
  final bool isUser;
  final String content;
  final DateTime timestamp;
  final bool isSearchResult;
  final bool isProactive;  // 是否为主动触发的消息

  ChatMessage({
    required this.isUser,
    required this.content,
    required this.timestamp,
    this.isSearchResult = false,
    this.isProactive = false,
  });
}
