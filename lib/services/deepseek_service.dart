import 'dart:convert';
import 'package:dio/dio.dart';
import 'developer_service.dart';
import 'agent_service.dart';

/// DeepSeek 服务 - 高性价比云端 AI
/// 官方 API: https://api.deepseek.com
/// 主力模型: DeepSeek-V3.2
class DeepSeekService {
  static final DeepSeekService _instance = DeepSeekService._internal();
  factory DeepSeekService() => _instance;
  DeepSeekService._internal();

  final Dio _dio = Dio();
  String? _apiKey;
  bool _isEnabled = true;
  final _developerService = DeveloperService();

  // 月度预算控制
  double _monthlyBudget = 0;
  double _currentMonthUsage = 0;

  // 模型名称
  static const String _defaultModel = 'deepseek-chat'; // DeepSeek-V3.2
  static const String _reasonerModel = 'deepseek-reasoner'; // DeepSeek-R1

  /// 初始化
  void initialize({String? apiKey, double? monthlyBudget}) {
    _apiKey = apiKey;
    _monthlyBudget = monthlyBudget ?? 0;

    _dio.options.baseUrl = 'https://api.deepseek.com';
    _dio.options.headers = {
      'Content-Type': 'application/json',
      if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 120); // DeepSeek 可能需要更长时间

    _developerService.log('DeepSeekService初始化: baseUrl=${_dio.options.baseUrl}, model=$_defaultModel', tag: 'DeepSeek');
  }

  /// 设置API密钥
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    _isEnabled = true;

    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    _developerService.log('DeepSeekService.setApiKey: API Key已设置', tag: 'DeepSeek');
  }

  /// 启用/禁用服务
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// 检查是否可用
  bool get isAvailable => _isEnabled && _apiKey != null;

  /// 获取API Key
  String? get apiKey => _apiKey;

  /// 检查预算是否超限
  bool get isWithinBudget {
    if (_monthlyBudget <= 0) return true;
    return _currentMonthUsage < _monthlyBudget;
  }

  /// 获取模型名称
  String _getModelName({bool useReasoner = false}) {
    return useReasoner ? _reasonerModel : _defaultModel;
  }

  /// 智能问答 - 支持深度对话
  Future<String?> askQuestion(
    String question, {
    List<String>? context,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true,
    bool useReasoner = false, // 是否使用推理模型
  }) async {
    if (!isAvailable) {
      _developerService.log('DeepSeek API不可用: isEnabled=$_isEnabled, apiKey=${_apiKey != null ? "已设置" : "未设置"}', level: LogLevel.warning, tag: 'DeepSeek');
      return null;
    }
    if (!isWithinBudget) {
      _developerService.log('DeepSeek API预算已超限', level: LogLevel.warning, tag: 'DeepSeek');
      return null;
    }

    try {
      final messages = <Map<String, String>>[];

      // 系统提示词
      var systemPrompt = '''你是MemoryPal，用户的24小时智能助理。你的特点是：

1. **深度个性化**：你全面了解用户的画像（职业、兴趣、习惯、目标、性格等），回答时自然融入这些信息。

2. **主动关联**：不局限于回答问题，主动关联用户的相关经历和偏好，提供有价值的洞察。

3. **学习进化**：每次对话都在加深对用户的理解，回答越来越个性化。

4. **对话风格**：
   - 用"你"而不是"用户"来称呼
   - 语气亲切、专业、有见地
   - 适当使用表情符号增加亲和力
   - 回答结构清晰，重点突出

5. **回答原则**：
   - 基于提供的画像和记忆数据回答
   - 不确定时坦诚告知，不编造
   - 鼓励用户多记录以加深了解
   - 主动提出有价值的后续问题

记住：你的目标是成为最懂用户的智能助理。'';

      if (enableTools) {
        systemPrompt += '\n\n${AgentService().getToolsDefinition()}';
      }

      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });

      // 添加上下文
      if (context != null && context.isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': '【上下文信息】\n${context.join("\n\n")}',
        });
        messages.add({
          'role': 'assistant',
          'content': '已了解上下文信息。我会基于这些信息为你提供个性化回答。',
        });
      }

      // 添加对话历史
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        messages.addAll(conversationHistory);
      }

      // 添加当前问题
      messages.add({
        'role': 'user',
        'content': question,
      });

      final modelName = _getModelName(useReasoner: useReasoner);
      _developerService.log('调用DeepSeek API: model=$modelName, messages=${messages.length}', tag: 'DeepSeek');

      final response = await _dio.post('/chat/completions', data: {
        'model': modelName,
        'messages': messages,
        'temperature': 0.8,
        'max_tokens': 2000,
      });

      _trackUsage(response);

      final content = response.data['choices'][0]['message']['content'] as String?;

      // DeepSeek-R1 有 reasoning_content 字段
      final reasoningContent = response.data['choices'][0]['message']['reasoning_content'] as String?;
      if (reasoningContent != null && reasoningContent.isNotEmpty) {
        _developerService.log('DeepSeek推理过程: ${reasoningContent.substring(0, reasoningContent.length > 100 ? 100 : reasoningContent.length)}...', tag: 'DeepSeek');
      }

      _developerService.log('DeepSeek API响应成功, 内容长度: ${content?.length ?? 0}', tag: 'DeepSeek');
      return content;
    } on DioException catch (e) {
      _developerService.log('DeepSeek API调用失败: ${e.type} - ${e.message}', level: LogLevel.error, tag: 'DeepSeek', error: e);
      if (e.response != null) {
        _developerService.log('DeepSeek API响应状态: ${e.response?.statusCode}', level: LogLevel.error, tag: 'DeepSeek');
        _developerService.log('DeepSeek API响应数据: ${e.response?.data}', level: LogLevel.error, tag: 'DeepSeek');
      }
      return null;
    } catch (e, stack) {
      _developerService.log('DeepSeek问答失败', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 生成每日摘要
  Future<DailySummary?> generateDailySummary(String dailyContent) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _defaultModel,
        'messages': [
          {
            'role': 'system',
            'content': '''你是一个贴心的个人助理，帮助用户整理一天的记忆和信息。
请分析以下内容，生成结构化的每日摘要：
1. 今日完成的事项
2. 待办提醒
3. 基于用户习惯的个性化建议'''
          },
          {
            'role': 'user',
            'content': '请分析今天的记录，生成每日记忆摘要：\n\n$dailyContent'
          }
        ],
        'temperature': 0.7,
      });

      _trackUsage(response);

      final content = response.data['choices'][0]['message']['content'] as String;
      return DailySummary(
        rawContent: content,
        date: DateTime.now(),
      );
    } catch (e, stack) {
      _developerService.log('DeepSeek生成每日摘要失败', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 分析用户画像更新
  Future<List<ProfileInsight>?> analyzeProfileUpdate(String content) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _defaultModel,
        'messages': [
          {
            'role': 'system',
            'content': '''分析用户内容，提取可能反映用户特征的信息。
对每项洞察给出置信度评分(0.0-1.0)。
只输出JSON格式：{"insights": [{"field": "字段名", "value": "值", "confidence": 0.8, "evidence": "证据"}]}'''
          },
          {
            'role': 'user',
            'content': content
          }
        ],
        'temperature': 0.3,
      });

      _trackUsage(response);

      final result = response.data['choices'][0]['message']['content'] as String;
      return _parseProfileInsights(result);
    } catch (e, stack) {
      _developerService.log('DeepSeek分析用户画像失败', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 提取待办事项
  Future<List<TodoItem>?> extractTodos(String content) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _defaultModel,
        'messages': [
          {
            'role': 'system',
            'content': '''从用户内容中提取待办事项。
输出JSON格式：{"todos": [{"content": "待办内容", "deadline": "YYYY-MM-DD或null", "priority": "high/medium/low"}]}'''
          },
          {
            'role': 'user',
            'content': content
          }
        ],
        'temperature': 0.3,
      });

      _trackUsage(response);

      final result = response.data['choices'][0]['message']['content'] as String;
      return _parseTodos(result);
    } catch (e, stack) {
      _developerService.log('DeepSeek提取待办失败', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 跟踪API使用量
  void _trackUsage(Response response) {
    final usage = response.data['usage'];
    if (usage != null) {
      final tokens = usage['total_tokens'] as int? ?? 0;
      // DeepSeek-V3 价格: 输入¥2/百万tokens, 输出¥8/百万tokens
      // 估算平均费用: ~0.005元/1K tokens
      final cost = tokens * 0.000005;
      _currentMonthUsage += cost;
    }
  }

  /// 解析用户画像洞察
  List<ProfileInsight>? _parseProfileInsights(String jsonStr) {
    try {
      final jsonStart = jsonStr.indexOf('{');
      final jsonEnd = jsonStr.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) return null;

      final json = jsonDecode(jsonStr.substring(jsonStart, jsonEnd + 1));
      final insights = json['insights'] as List<dynamic>?;

      return insights?.map((i) => ProfileInsight(
        field: i['field'] as String,
        value: i['value'].toString(),
        confidence: (i['confidence'] as num).toDouble(),
        evidence: i['evidence'] as String?,
      )).toList();
    } catch (e, stack) {
      _developerService.log('DeepSeek解析画像洞察失败', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 解析待办事项
  List<TodoItem>? _parseTodos(String jsonStr) {
    try {
      final jsonStart = jsonStr.indexOf('{');
      final jsonEnd = jsonStr.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) return null;

      final json = jsonDecode(jsonStr.substring(jsonStart, jsonEnd + 1));
      final todos = json['todos'] as List<dynamic>?;

      return todos?.map((t) => TodoItem(
        content: t['content'] as String,
        deadline: t['deadline'] != null ? DateTime.tryParse(t['deadline']) : null,
        priority: t['priority'] as String? ?? 'medium',
      )).toList();
    } catch (e, stack) {
      _developerService.log('DeepSeek解析待办失败', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }
}

/// 每日摘要
class DailySummary {
  final String rawContent;
  final DateTime date;

  DailySummary({
    required this.rawContent,
    required this.date,
  });
}

/// 用户画像洞察
class ProfileInsight {
  final String field;
  final String value;
  final double confidence;
  final String? evidence;

  ProfileInsight({
    required this.field,
    required this.value,
    required this.confidence,
    this.evidence,
  });
}

/// 待办事项
class TodoItem {
  final String content;
  final DateTime? deadline;
  final String priority;

  TodoItem({
    required this.content,
    this.deadline,
    required this.priority,
  });
}
