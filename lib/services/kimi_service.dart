import 'dart:convert';
import 'package:dio/dio.dart';
import 'developer_service.dart';
import 'agent_service.dart';

// Kimi服务 - 云端深度分析
// 支持两种平台：
// 1. Moonshot AI (platform.moonshot.cn) - API Key格式: sk-xxx
// 2. KimiCode (kimi.com/code) - API Key格式: sk-kimi-xxx
class KimiService {
  static final KimiService _instance = KimiService._internal();
  factory KimiService() => _instance;
  KimiService._internal();

  final Dio _dio = Dio();
  String? _apiKey;
  bool _isEnabled = true;
  bool _isKimiCode = false; // 是否为KimiCode平台
  bool _forceMoonshot = true; // 默认强制使用Moonshot（KimiCode API有限制）
  final _developerService = DeveloperService();

  // 月度预算控制
  double _monthlyBudget = 0; // 0表示无限制
  double _currentMonthUsage = 0;

  // 初始化
  void initialize({String? apiKey, double? monthlyBudget, bool? useKimiCode}) {
    _apiKey = apiKey;
    _monthlyBudget = monthlyBudget ?? 0;

    // 平台选择：默认强制使用Moonshot（KimiCode API有限制）
    // 只有明确设置 useKimiCode=true 时才使用KimiCode
    if (useKimiCode == true) {
      _isKimiCode = true;
      _forceMoonshot = false;
    } else {
      _isKimiCode = false;
      _forceMoonshot = true;
    }

    _dio.options.baseUrl = _isKimiCode
        ? 'https://api.kimi.com/coding/v1'  // KimiCode平台
        : 'https://api.moonshot.cn/v1';      // Moonshot平台

    _dio.options.headers = {
      'Content-Type': 'application/json',
      if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    _developerService.log('KimiService初始化: ${_isKimiCode ? "KimiCode平台" : "Moonshot平台"}, baseUrl=${_dio.options.baseUrl}, model=${_getModelName()}', tag: 'Kimi');
  }

  // 设置API密钥
  // 注意：默认强制使用Moonshot平台，因为KimiCode API有限制
  void setApiKey(String apiKey, {bool? useKimiCode}) {
    _apiKey = apiKey;
    _isEnabled = true; // 设置API Key时自动启用

    // 平台选择：默认强制使用Moonshot（KimiCode API有限制）
    if (useKimiCode == true) {
      _isKimiCode = true;
      _forceMoonshot = false;
    } else {
      // 默认使用Moonshot，即使key是sk-kimi-格式
      _isKimiCode = false;
      _forceMoonshot = true;
    }

    // 重新初始化Dio配置
    _dio.options.baseUrl = _isKimiCode
        ? 'https://api.kimi.com/coding/v1'
        : 'https://api.moonshot.cn/v1';

    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    _developerService.log('KimiService.setApiKey: 平台=${_isKimiCode ? "KimiCode" : "Moonshot"}, baseUrl=${_dio.options.baseUrl}, API Key已设置', tag: 'Kimi');

    // 如果key是sk-kimi-格式但强制使用Moonshot，给出警告
    if (apiKey.startsWith('sk-kimi-') && _forceMoonshot) {
      _developerService.log('注意: API Key格式为KimiCode，但已自动切换到Moonshot平台（KimiCode API有限制）', level: LogLevel.warning, tag: 'Kimi');
    }
  }

  // 获取当前平台类型
  bool get isKimiCode => _isKimiCode;

  // 启用/禁用云端分析
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  // 检查是否可用
  bool get isAvailable => _isEnabled && _apiKey != null;

  // 获取API Key（用于其他服务）
  String? get apiKey => _apiKey;

  // 获取当前使用的模型名称
  String _getModelName() {
    return _isKimiCode ? 'kimi-k2-0723' : 'moonshot-v1-8k';
  }

  // 检查预算是否超限
  bool get isWithinBudget {
    if (_monthlyBudget <= 0) return true;
    return _currentMonthUsage < _monthlyBudget;
  }

  // 生成每日摘要
  Future<DailySummary?> generateDailySummary(String dailyContent) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _getModelName(),
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
      return _parseDailySummary(content);
    } catch (e, stack) {
      _developerService.log('生成每日摘要失败', level: LogLevel.error, tag: 'Kimi', error: e, stackTrace: stack);
      return null;
    }
  }

  // 分析用户画像更新
  Future<List<ProfileInsight>?> analyzeProfileUpdate(String content) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _getModelName(),
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
      _developerService.log('分析用户画像失败', level: LogLevel.error, tag: 'Kimi', error: e, stackTrace: stack);
      return null;
    }
  }

  // 智能问答 - 支持深度对话、用户画像学习和智能体工具调用
  Future<String?> askQuestion(
    String question, {
    List<String>? context,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true, // 是否启用工具调用
  }) async {
    if (!isAvailable) {
      _developerService.log('Kimi API不可用: isEnabled=$_isEnabled, apiKey=${_apiKey != null ? "已设置" : "未设置"}', level: LogLevel.warning, tag: 'Kimi');
      return null;
    }
    if (!isWithinBudget) {
      _developerService.log('Kimi API预算已超限', level: LogLevel.warning, tag: 'Kimi');
      return null;
    }

    try {
      final messages = <Map<String, String>>[];

      // 系统提示词 - 定义AI角色和行为准则
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

记住：你的目标是成为最懂用户的智能助理。''';

      // 如果启用工具，添加工具定义
      if (enableTools) {
        systemPrompt += '\n\n${AgentService().getToolsDefinition()}';
      }

      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });

      // 添加上下文（用户画像、记忆数据等）
      if (context != null && context.isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': '【上下文信息】\n${context.join("\n\n")}',
        });
        // 让系统确认收到上下文
        messages.add({
          'role': 'assistant',
          'content': '已了解上下文信息。我会基于这些信息为你提供个性化回答。',
        });
      }

      // 添加对话历史（如果有）
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        messages.addAll(conversationHistory);
      }

      // 添加当前问题
      messages.add({
        'role': 'user',
        'content': question,
      });

      final modelName = _getModelName();
      _developerService.log('调用Kimi API: platform=${_isKimiCode ? "KimiCode" : "Moonshot"}, model=$modelName, messages=${messages.length}', tag: 'Kimi');

      final response = await _dio.post('/chat/completions', data: {
        'model': modelName,
        'messages': messages,
        'temperature': 0.8, // 稍高的温度增加创造性
        'max_tokens': 2000, // 允许较长的回复
      });

      _trackUsage(response);

      final content = response.data['choices'][0]['message']['content'] as String?;
      _developerService.log('Kimi API响应成功, 内容长度: ${content?.length ?? 0}', tag: 'Kimi');
      return content;
    } on DioException catch (e) {
      _developerService.log('Kimi API调用失败: ${e.type} - ${e.message}', level: LogLevel.error, tag: 'Kimi', error: e);
      if (e.response != null) {
        _developerService.log('Kimi API响应状态: ${e.response?.statusCode}', level: LogLevel.error, tag: 'Kimi');
        _developerService.log('Kimi API响应数据: ${e.response?.data}', level: LogLevel.error, tag: 'Kimi');
      }
      return null;
    } catch (e, stack) {
      _developerService.log('问答失败', level: LogLevel.error, tag: 'Kimi', error: e, stackTrace: stack);
      return null;
    }
  }

  // 提取待办事项
  Future<List<TodoItem>?> extractTodos(String content) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _getModelName(),
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
      _developerService.log('提取待办失败', level: LogLevel.error, tag: 'Kimi', error: e, stackTrace: stack);
      return null;
    }
  }

  // 跟踪API使用量
  void _trackUsage(Response response) {
    final usage = response.data['usage'];
    if (usage != null) {
      final tokens = usage['total_tokens'] as int? ?? 0;
      // 估算费用 (Kimi: ~0.006元/1K tokens)
      final cost = tokens * 0.000006;
      _currentMonthUsage += cost;
    }
  }

  // 解析每日摘要
  DailySummary _parseDailySummary(String content) {
    // 简单解析，实际可以更复杂
    return DailySummary(
      rawContent: content,
      date: DateTime.now(),
    );
  }

  // 解析用户画像洞察
  List<ProfileInsight>? _parseProfileInsights(String jsonStr) {
    try {
      // 提取JSON部分
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
      _developerService.log('解析画像洞察失败', level: LogLevel.error, tag: 'Kimi', error: e, stackTrace: stack);
      return null;
    }
  }

  // 解析待办事项
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
      _developerService.log('解析待办失败', level: LogLevel.error, tag: 'Kimi', error: e, stackTrace: stack);
      return null;
    }
  }
}

// 每日摘要
class DailySummary {
  final String rawContent;
  final DateTime date;

  DailySummary({
    required this.rawContent,
    required this.date,
  });
}

// 用户画像洞察
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

// 待办事项
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
