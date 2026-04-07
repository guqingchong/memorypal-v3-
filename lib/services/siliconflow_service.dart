import 'dart:convert';
import 'package:dio/dio.dart';
import 'developer_service.dart';
import 'agent_service.dart';
import 'kimi_service.dart' show DailySummary, ProfileInsight, TodoItem;

/// SiliconFlow 硅基流动服务 - 免费/低成本备用 AI
/// 官网: https://siliconflow.cn
/// 免费模型: Qwen2.5-7B 等
class SiliconFlowService {
  static final SiliconFlowService _instance = SiliconFlowService._internal();
  factory SiliconFlowService() => _instance;
  SiliconFlowService._internal();

  final Dio _dio = Dio();
  String? _apiKey;
  bool _isEnabled = true;
  final _developerService = DeveloperService();

  // 基础URL
  static const String _baseUrl = 'https://api.siliconflow.cn/v1';

  // 免费模型
  static const String _freeModel = 'Qwen/Qwen2.5-7B-Instruct';

  /// 初始化
  void initialize({String? apiKey}) {
    _apiKey = apiKey;

    _dio.options.baseUrl = _baseUrl;
    _dio.options.headers = {
      'Content-Type': 'application/json',
      if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    _developerService.log('SiliconFlowService initialized', tag: 'SiliconFlow');
  }

  /// 设置API密钥
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    _isEnabled = true;

    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    _developerService.log('SiliconFlowService API Key set', tag: 'SiliconFlow');
  }

  /// 启用/禁用服务
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// 检查是否可用
  bool get isAvailable => _isEnabled && _apiKey != null;

  /// 获取API Key
  String? get apiKey => _apiKey;

  /// 智能问答
  Future<String?> askQuestion(
    String question, {
    List<String>? context,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true,
  }) async {
    if (!isAvailable) {
      _developerService.log('SiliconFlow API not available', level: LogLevel.warning, tag: 'SiliconFlow');
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

      _developerService.log('Calling SiliconFlow API: model=$_freeModel', tag: 'SiliconFlow');

      final response = await _dio.post('/chat/completions', data: {
        'model': _freeModel,
        'messages': messages,
        'temperature': 0.8,
        'max_tokens': 2000,
      });

      final content = response.data['choices'][0]['message']['content'] as String?;
      _developerService.log('SiliconFlow API response received, length: ${content?.length ?? 0}', tag: 'SiliconFlow');
      return content;
    } on DioException catch (e) {
      _developerService.log('SiliconFlow API error: ${e.type}', level: LogLevel.error, tag: 'SiliconFlow', error: e);
      return null;
    } catch (e, stack) {
      _developerService.log('SiliconFlow error', level: LogLevel.error, tag: 'SiliconFlow', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 生成每日摘要
  Future<DailySummary?> generateDailySummary(String dailyContent) async {
    if (!isAvailable) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _freeModel,
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

      final content = response.data['choices'][0]['message']['content'] as String;
      return DailySummary(
        rawContent: content,
        date: DateTime.now(),
      );
    } catch (e, stack) {
      _developerService.log('Daily summary failed', level: LogLevel.error, tag: 'SiliconFlow', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 分析用户画像更新
  Future<List<ProfileInsight>?> analyzeProfileUpdate(String content) async {
    if (!isAvailable) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _freeModel,
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

      final result = response.data['choices'][0]['message']['content'] as String;
      return _parseProfileInsights(result);
    } catch (e, stack) {
      _developerService.log('Profile analysis failed', level: LogLevel.error, tag: 'SiliconFlow', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 提取待办事项
  Future<List<TodoItem>?> extractTodos(String content) async {
    if (!isAvailable) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _freeModel,
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

      final result = response.data['choices'][0]['message']['content'] as String;
      return _parseTodos(result);
    } catch (e, stack) {
      _developerService.log('Todo extraction failed', level: LogLevel.error, tag: 'SiliconFlow', error: e, stackTrace: stack);
      return null;
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
      _developerService.log('Parse insights failed', level: LogLevel.error, tag: 'SiliconFlow', error: e, stackTrace: stack);
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
      _developerService.log('Parse todos failed', level: LogLevel.error, tag: 'SiliconFlow', error: e, stackTrace: stack);
      return null;
    }
  }
}
