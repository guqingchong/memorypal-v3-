import 'dart:convert';
import 'package:dio/dio.dart';
import 'developer_service.dart';
import 'agent_service.dart';
import 'kimi_service.dart' show DailySummary, ProfileInsight, TodoItem;

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
    _dio.options.receiveTimeout = const Duration(seconds: 120);

    _developerService.log('DeepSeekService initialized', tag: 'DeepSeek');
  }

  /// 设置API密钥
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    _isEnabled = true;

    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    _developerService.log('DeepSeekService API Key set', tag: 'DeepSeek');
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

  /// 智能问答
  Future<String?> askQuestion(
    String question, {
    List<String>? context,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true,
    bool useReasoner = false,
  }) async {
    if (!isAvailable) {
      _developerService.log('DeepSeek API not available', level: LogLevel.warning, tag: 'DeepSeek');
      return null;
    }
    if (!isWithinBudget) {
      _developerService.log('DeepSeek API budget exceeded', level: LogLevel.warning, tag: 'DeepSeek');
      return null;
    }

    try {
      final messages = <Map<String, String>>[];

      // 系统提示词
      var systemPrompt = 'You are MemoryPal, a helpful AI assistant.';

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
          'content': 'Context:\n${context.join("\n\n")}',
        });
        messages.add({
          'role': 'assistant',
          'content': 'Context received.',
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

      final modelName = useReasoner ? _reasonerModel : _defaultModel;
      _developerService.log('Calling DeepSeek API: model=$modelName', tag: 'DeepSeek');

      final response = await _dio.post('/chat/completions', data: {
        'model': modelName,
        'messages': messages,
        'temperature': 0.8,
        'max_tokens': 2000,
      });

      _trackUsage(response);

      final content = response.data['choices'][0]['message']['content'] as String?;
      _developerService.log('DeepSeek API response received, length: ${content?.length ?? 0}', tag: 'DeepSeek');
      return content;
    } on DioException catch (e) {
      _developerService.log('DeepSeek API error: ${e.type}', level: LogLevel.error, tag: 'DeepSeek', error: e);
      return null;
    } catch (e, stack) {
      _developerService.log('DeepSeek error', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
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
            'content': 'Generate a daily summary.',
          },
          {
            'role': 'user',
            'content': 'Daily content: $dailyContent',
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
      _developerService.log('Daily summary failed', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
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
            'content': 'Extract user profile insights from content. Return JSON.',
          },
          {
            'role': 'user',
            'content': content,
          }
        ],
        'temperature': 0.3,
      });

      _trackUsage(response);

      final result = response.data['choices'][0]['message']['content'] as String;
      return _parseProfileInsights(result);
    } catch (e, stack) {
      _developerService.log('Profile analysis failed', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
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
            'content': 'Extract todos from content. Return JSON.',
          },
          {
            'role': 'user',
            'content': content,
          }
        ],
        'temperature': 0.3,
      });

      _trackUsage(response);

      final result = response.data['choices'][0]['message']['content'] as String;
      return _parseTodos(result);
    } catch (e, stack) {
      _developerService.log('Todo extraction failed', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 跟踪API使用量
  void _trackUsage(Response response) {
    final usage = response.data['usage'];
    if (usage != null) {
      final tokens = usage['total_tokens'] as int? ?? 0;
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
      _developerService.log('Parse insights failed', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
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
      _developerService.log('Parse todos failed', level: LogLevel.error, tag: 'DeepSeek', error: e, stackTrace: stack);
      return null;
    }
  }
}
