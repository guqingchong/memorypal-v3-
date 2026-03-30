import 'dart:convert';
import 'package:dio/dio.dart';

// Kimi服务 - 云端深度分析
class KimiService {
  static final KimiService _instance = KimiService._internal();
  factory KimiService() => _instance;
  KimiService._internal();

  final Dio _dio = Dio();
  String? _apiKey;
  bool _isEnabled = true;

  // 月度预算控制
  double _monthlyBudget = 0; // 0表示无限制
  double _currentMonthUsage = 0;

  // 初始化
  void initialize({String? apiKey, double? monthlyBudget}) {
    _apiKey = apiKey;
    _monthlyBudget = monthlyBudget ?? 0;

    _dio.options.baseUrl = 'https://api.moonshot.cn/v1';
    _dio.options.headers = {
      'Content-Type': 'application/json',
      if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  // 设置API密钥
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
  }

  // 启用/禁用云端分析
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  // 检查是否可用
  bool get isAvailable => _isEnabled && _apiKey != null;

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
        'model': 'moonshot-v1-8k',
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
    } catch (e) {
      print('生成每日摘要失败: $e');
      return null;
    }
  }

  // 分析用户画像更新
  Future<List<ProfileInsight>?> analyzeProfileUpdate(String content) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': 'moonshot-v1-8k',
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
    } catch (e) {
      print('分析用户画像失败: $e');
      return null;
    }
  }

  // 智能问答
  Future<String?> askQuestion(String question, {List<String>? context}) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final messages = <Map<String, String>>[
        {
          'role': 'system',
          'content': '你是MemoryPal智能助理，基于用户的记忆数据回答问题。如果信息不足，请明确告知。'
        },
      ];

      if (context != null && context.isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': '相关背景信息：\n${context.join("\n")}',
        });
      }

      messages.add({
        'role': 'user',
        'content': question,
      });

      final response = await _dio.post('/chat/completions', data: {
        'model': 'moonshot-v1-8k',
        'messages': messages,
        'temperature': 0.7,
      });

      _trackUsage(response);

      return response.data['choices'][0]['message']['content'] as String;
    } catch (e) {
      print('问答失败: $e');
      return null;
    }
  }

  // 提取待办事项
  Future<List<TodoItem>?> extractTodos(String content) async {
    if (!isAvailable || !isWithinBudget) return null;

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': 'moonshot-v1-8k',
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
    } catch (e) {
      print('提取待办失败: $e');
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
    } catch (e) {
      print('解析画像洞察失败: $e');
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
    } catch (e) {
      print('解析待办失败: $e');
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
