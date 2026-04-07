import 'kimi_service.dart';
import 'deepseek_service.dart';
import 'siliconflow_service.dart';
import 'database_service.dart';

/// AI 服务提供商类型
enum AIProvider {
  moonshot,    // Moonshot (原Kimi)
  deepseek,    // DeepSeek
  siliconflow, // SiliconFlow (免费备用)
}

/// AI 服务管理器
/// 统一管理多个 AI 服务提供商，支持自动切换和负载均衡
class AIServiceManager {
  static final AIServiceManager _instance = AIServiceManager._internal();
  factory AIServiceManager() => _instance;
  AIServiceManager._internal();

  final _kimiService = KimiService();
  final _deepseekService = DeepSeekService();
  final _siliconflowService = SiliconFlowService();
  final _databaseService = DatabaseService();

  AIProvider _currentProvider = AIProvider.deepseek; // 默认使用DeepSeek
  bool _autoFallback = true; // 自动降级到备用服务

  /// 初始化
  Future<void> initialize() async {
    // 加载用户设置的AI提供商
    final providerName = await _databaseService.getSetting('ai_provider');
    if (providerName != null) {
      _currentProvider = AIProvider.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => AIProvider.deepseek,
      );
    }

    // 加载各服务的API Key
    final kimiApiKey = await _databaseService.getSetting('kimi_api_key');
    final deepseekApiKey = await _databaseService.getSetting('deepseek_api_key');
    final siliconflowApiKey = await _databaseService.getSetting('siliconflow_api_key');

    if (kimiApiKey != null && kimiApiKey.isNotEmpty) {
      _kimiService.setApiKey(kimiApiKey);
    }
    if (deepseekApiKey != null && deepseekApiKey.isNotEmpty) {
      _deepseekService.setApiKey(deepseekApiKey);
    }
    if (siliconflowApiKey != null && siliconflowApiKey.isNotEmpty) {
      _siliconflowService.setApiKey(siliconflowApiKey);
    }
  }

  /// 获取当前提供商
  AIProvider get currentProvider => _currentProvider;

  /// 设置当前提供商
  Future<void> setProvider(AIProvider provider) async {
    _currentProvider = provider;
    await _databaseService.setSetting('ai_provider', provider.name);
  }

  /// 获取当前提供商名称
  String get currentProviderName {
    switch (_currentProvider) {
      case AIProvider.moonshot:
        return 'Moonshot';
      case AIProvider.deepseek:
        return 'DeepSeek';
      case AIProvider.siliconflow:
        return 'SiliconFlow';
    }
  }

  /// 获取当前提供商状态
  Map<String, dynamic> getProviderStatus() {
    return {
      'moonshot': {
        'available': _kimiService.isAvailable,
        'apiKeySet': _kimiService.apiKey != null,
      },
      'deepseek': {
        'available': _deepseekService.isAvailable,
        'apiKeySet': _deepseekService.apiKey != null,
      },
      'siliconflow': {
        'available': _siliconflowService.isAvailable,
        'apiKeySet': _siliconflowService.apiKey != null,
      },
    };
  }

  /// 智能问答 - 自动选择可用的服务
  Future<String?> askQuestion(
    String question, {
    List<String>? context,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true,
  }) async {
    // 按优先级尝试服务
    final providers = _getProviderPriority();

    for (final provider in providers) {
      final result = await _askWithProvider(
        provider,
        question,
        context: context,
        conversationHistory: conversationHistory,
        enableTools: enableTools,
      );
      if (result != null) return result;
    }

    return null;
  }

  /// 使用指定提供商提问
  Future<String?> _askWithProvider(
    AIProvider provider,
    String question, {
    List<String>? context,
    List<Map<String, String>>? conversationHistory,
    bool enableTools = true,
  }) async {
    switch (provider) {
      case AIProvider.moonshot:
        return await _kimiService.askQuestion(
          question,
          context: context,
          conversationHistory: conversationHistory,
          enableTools: enableTools,
        );
      case AIProvider.deepseek:
        return await _deepseekService.askQuestion(
          question,
          context: context,
          conversationHistory: conversationHistory,
          enableTools: enableTools,
        );
      case AIProvider.siliconflow:
        return await _siliconflowService.askQuestion(
          question,
          context: context,
          conversationHistory: conversationHistory,
          enableTools: enableTools,
        );
    }
  }

  /// 生成每日摘要
  Future<DailySummary?> generateDailySummary(String dailyContent) async {
    // 按优先级尝试
    final providers = _getProviderPriority();

    for (final provider in providers) {
      final result = await _generateSummaryWithProvider(provider, dailyContent);
      if (result != null) return result;
    }

    return null;
  }

  /// 使用指定提供商生成摘要
  Future<DailySummary?> _generateSummaryWithProvider(
    AIProvider provider,
    String dailyContent,
  ) async {
    switch (provider) {
      case AIProvider.moonshot:
        return await _kimiService.generateDailySummary(dailyContent);
      case AIProvider.deepseek:
        return await _deepseekService.generateDailySummary(dailyContent);
      case AIProvider.siliconflow:
        return await _siliconflowService.generateDailySummary(dailyContent);
    }
  }

  /// 分析用户画像更新
  Future<List<ProfileInsight>?> analyzeProfileUpdate(String content) async {
    final providers = _getProviderPriority();

    for (final provider in providers) {
      final result = await _analyzeProfileWithProvider(provider, content);
      if (result != null) return result;
    }

    return null;
  }

  /// 使用指定提供商分析画像
  Future<List<ProfileInsight>?> _analyzeProfileWithProvider(
    AIProvider provider,
    String content,
  ) async {
    switch (provider) {
      case AIProvider.moonshot:
        return await _kimiService.analyzeProfileUpdate(content);
      case AIProvider.deepseek:
        return await _deepseekService.analyzeProfileUpdate(content);
      case AIProvider.siliconflow:
        return await _siliconflowService.analyzeProfileUpdate(content);
    }
  }

  /// 提取待办事项
  Future<List<TodoItem>?> extractTodos(String content) async {
    final providers = _getProviderPriority();

    for (final provider in providers) {
      final result = await _extractTodosWithProvider(provider, content);
      if (result != null) return result;
    }

    return null;
  }

  /// 使用指定提供商提取待办
  Future<List<TodoItem>?> _extractTodosWithProvider(
    AIProvider provider,
    String content,
  ) async {
    switch (provider) {
      case AIProvider.moonshot:
        return await _kimiService.extractTodos(content);
      case AIProvider.deepseek:
        return await _deepseekService.extractTodos(content);
      case AIProvider.siliconflow:
        return await _siliconflowService.extractTodos(content);
    }
  }

  /// 获取服务优先级列表
  List<AIProvider> _getProviderPriority() {
    if (!_autoFallback) {
      return [_currentProvider];
    }

    // 构建优先级列表：当前首选 + 其他可用服务
    final List<AIProvider> priority = [_currentProvider];

    for (final provider in AIProvider.values) {
      if (provider != _currentProvider && _isProviderAvailable(provider)) {
        priority.add(provider);
      }
    }

    return priority;
  }

  /// 检查提供商是否可用
  bool _isProviderAvailable(AIProvider provider) {
    switch (provider) {
      case AIProvider.moonshot:
        return _kimiService.isAvailable;
      case AIProvider.deepseek:
        return _deepseekService.isAvailable;
      case AIProvider.siliconflow:
        return _siliconflowService.isAvailable;
    }
  }

  /// 设置API Key
  Future<void> setApiKey(AIProvider provider, String apiKey) async {
    switch (provider) {
      case AIProvider.moonshot:
        _kimiService.setApiKey(apiKey);
        await _databaseService.setSetting('kimi_api_key', apiKey);
        break;
      case AIProvider.deepseek:
        _deepseekService.setApiKey(apiKey);
        await _databaseService.setSetting('deepseek_api_key', apiKey);
        break;
      case AIProvider.siliconflow:
        _siliconflowService.setApiKey(apiKey);
        await _databaseService.setSetting('siliconflow_api_key', apiKey);
        break;
    }
  }

  /// 清除API Key
  Future<void> clearApiKey(AIProvider provider) async {
    switch (provider) {
      case AIProvider.moonshot:
        await _databaseService.setSetting('kimi_api_key', '');
        break;
      case AIProvider.deepseek:
        await _databaseService.setSetting('deepseek_api_key', '');
        break;
      case AIProvider.siliconflow:
        await _databaseService.setSetting('siliconflow_api_key', '');
        break;
    }
  }

  /// 获取指定提供商的API Key
  String? getApiKey(AIProvider provider) {
    switch (provider) {
      case AIProvider.moonshot:
        return _kimiService.apiKey;
      case AIProvider.deepseek:
        return _deepseekService.apiKey;
      case AIProvider.siliconflow:
        return _siliconflowService.apiKey;
    }
  }

  /// 设置自动降级
  void setAutoFallback(bool enabled) {
    _autoFallback = enabled;
  }

  /// 获取自动降级状态
  bool get autoFallback => _autoFallback;

  /// 检查是否有任何可用的AI服务
  bool get hasAnyAvailableService {
    return _kimiService.isAvailable ||
           _deepseekService.isAvailable ||
           _siliconflowService.isAvailable;
  }
}

// 导出数据类
export 'kimi_service.dart' show DailySummary, ProfileInsight, TodoItem;
