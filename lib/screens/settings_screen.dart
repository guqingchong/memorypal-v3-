import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/database_service.dart';
import '../services/backup_service.dart';
import '../services/kimi_service.dart';
import '../services/deepseek_service.dart';
import '../services/siliconflow_service.dart';
import '../services/ai_service_manager.dart';
import '../services/recording_service.dart';
import '../services/call_state_service.dart';
import '../services/system_recording_importer.dart';
import '../services/settings_service.dart';
import '../services/developer_service.dart';
import '../services/data_export_service.dart';
import '../widgets/data_export_section.dart';
import 'developer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _databaseService = DatabaseService();
  final _backupService = BackupService();
  final _kimiService = KimiService();
  final _deepseekService = DeepSeekService();
  final _siliconflowService = SiliconFlowService();
  final _aiManager = AIServiceManager();
  final _recordingService = RecordingService();
  final _callStateService = CallStateService();
  final _settingsService = SettingsService();
  final _developerService = DeveloperService();

  // 开发者模式
  bool _isDeveloperMode = false;

  // 设置状态
  bool _notificationsEnabled = true;
  bool _autoRecording = false;
  bool _cloudAnalysis = true;
  bool _nightAnalysis = true;
  bool _locationBased = true;
  int _maxSuggestionsPerDay = 3;
  int _recordingRetentionDays = 30;
  String _dailySummaryTime = '08:00';
  String _recordingQuality = '标准';
  double _monthlyBudget = 0;

  // AI设置
  String? _kimiApiKey;

  // 通话录音设置
  bool _enableCallDetection = true;
  bool _autoImportSystemRecordings = true;

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initDeveloperMode();
  }

  Future<void> _initDeveloperMode() async {
    await _developerService.initialize();
    setState(() {
      _isDeveloperMode = _developerService.isDeveloperMode;
    });
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _databaseService.getSettings();

      // 从SharedPreferences加载设置
      final autoRecording = await _settingsService.getAutoRecordingEnabled();
      final kimiApiKey = await _settingsService.getKimiApiKey();
      final recordingQuality = await _settingsService.getRecordingQuality();

      // 初始化AI服务管理器
      await _aiManager.initialize();

      // 如果保存过API Key，初始化Kimi服务
      if (kimiApiKey != null && kimiApiKey.isNotEmpty) {
        _kimiService.setApiKey(kimiApiKey);
      }

      setState(() {
        _notificationsEnabled = true; // 通知权限单独管理
        _autoRecording = autoRecording;
        _cloudAnalysis = settings['enable_cloud_analysis'] == 1;
        _nightAnalysis = settings['night_analysis_enabled'] == 1;
        _locationBased = settings['allow_location_based'] == 1;
        _maxSuggestionsPerDay = settings['max_suggestions_per_day'] ?? 3;
        _recordingRetentionDays = settings['recording_retention_days'] ?? 30;
        _dailySummaryTime = settings['daily_summary_time'] ?? '08:00';
        _monthlyBudget = settings['monthly_api_budget'] ?? 0.0;
        _recordingQuality = recordingQuality;
        // 加载通话录音设置
        _enableCallDetection = settings['enable_call_detection'] ?? true;
        _autoImportSystemRecordings = settings['auto_import_system_recordings'] ?? true;
        // 加载Kimi API Key
        _kimiApiKey = kimiApiKey;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载设置失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    await _databaseService.updateSettings({
      'enable_cloud_analysis': _cloudAnalysis ? 1 : 0,
      'night_analysis_enabled': _nightAnalysis ? 1 : 0,
      'allow_location_based': _locationBased ? 1 : 0,
      'max_suggestions_per_day': _maxSuggestionsPerDay,
      'recording_retention_days': _recordingRetentionDays,
      'daily_summary_time': _dailySummaryTime,
      'monthly_api_budget': _monthlyBudget,
      'enable_call_detection': _enableCallDetection,
      'auto_import_system_recordings': _autoImportSystemRecordings,
    });

    // 更新通话状态服务设置
    await _callStateService.updateSettings(
      enableCallDetection: _enableCallDetection,
      autoImportSystemRecordings: _autoImportSystemRecordings,
    );
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);

    final password = await _showPasswordDialog('设置备份密码（可选）');
    if (password == null) {
      setState(() => _isExporting = false);
      return;
    }

    final backupPath = await _backupService.exportBackup(
      password: password.isEmpty ? null : password,
    );

    setState(() => _isExporting = false);

    if (backupPath != null) {
      await _backupService.shareBackup(backupPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份文件已保存')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importData() async {
    setState(() => _isImporting = true);

    final password = await _showPasswordDialog('如果备份有密码，请输入');
    if (password == null) {
      setState(() => _isImporting = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('恢复备份将覆盖当前所有数据。建议先导出当前数据作为备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('确认恢复', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _backupService.pickAndRestoreBackup(
        password: password.isEmpty ? null : password,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '数据恢复成功，请重启应用' : '恢复失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }

    setState(() => _isImporting = false);
  }

  Future<String?> _showPasswordDialog(String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '留空表示无密码',
            labelText: '密码',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('这将删除所有数据，包括录音、笔记和设置。此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _backupService.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所有数据已清除')),
        );
      }
    }
  }

  /// 获取API Key状态文本
  String _getApiKeyStatus() {
    final provider = _aiManager.currentProvider;
    final apiKey = _aiManager.getApiKey(provider);
    if (apiKey == null || apiKey.isEmpty) {
      return '未配置';
    }
    // 只显示前后几位
    final masked = '${apiKey.substring(0, 4)}****${apiKey.substring(apiKey.length - 4)}';
    return '已配置: $masked';
  }

  /// 选择AI提供商
  Future<void> _selectAIProvider() async {
    final result = await showDialog<AIProvider>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择AI服务提供商'),
        children: [
          _buildProviderOption(
            AIProvider.deepseek,
            'DeepSeek',
            'deepseek-chat (V3.2)',
            '高性价比，推荐',
            Colors.blue,
          ),
          _buildProviderOption(
            AIProvider.moonshot,
            'Moonshot',
            'moonshot-v1-8k',
            '长文本处理强',
            Colors.orange,
          ),
          _buildProviderOption(
            AIProvider.siliconflow,
            'SiliconFlow',
            'Qwen2.5-7B (免费)',
            '免费额度，适合备用',
            Colors.green,
          ),
        ],
      ),
    );

    if (result != null) {
      await _aiManager.setProvider(result);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已切换到: ${_aiManager.currentProviderName}')),
        );
      }
    }
  }

  Widget _buildProviderOption(
    AIProvider provider,
    String name,
    String model,
    String desc,
    Color color,
  ) {
    final isSelected = _aiManager.currentProvider == provider;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, provider),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      ],
                    ],
                  ),
                  Text(
                    model,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 配置当前提供商的API
  Future<void> _configureCurrentApi() async {
    final provider = _aiManager.currentProvider;
    switch (provider) {
      case AIProvider.deepseek:
        await _configureDeepSeekApi();
        break;
      case AIProvider.moonshot:
        await _configureKimiApi();
        break;
      case AIProvider.siliconflow:
        await _configureSiliconFlowApi();
        break;
    }
  }

  /// 配置DeepSeek API
  Future<void> _configureDeepSeekApi() async {
    final currentKey = _aiManager.getApiKey(AIProvider.deepseek);
    final controller = TextEditingController(text: currentKey);
    String? testResult;
    bool isTesting = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('配置 DeepSeek API'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '从 platform.deepseek.com 获取',
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DeepSeek-V3.2 价格参考：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• 输入: ¥2/百万tokens\n'
                      '• 输出: ¥8/百万tokens\n'
                      '• 比Kimi便宜约70%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 验证按钮和结果
              Row(
                children: [
                  TextButton.icon(
                    onPressed: isTesting || controller.text.isEmpty
                        ? null
                        : () async {
                            setDialogState(() {
                              isTesting = true;
                              testResult = null;
                            });

                            final testService = DeepSeekService();
                            testService.setApiKey(controller.text);
                            final result = await testService.askQuestion(
                              'Hello, this is a test.',
                              context: [],
                            );

                            setDialogState(() {
                              isTesting = false;
                              testResult = result != null
                                  ? '连接成功！'
                                  : '连接失败，请检查API Key';
                            });
                          },
                    icon: isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('测试连接'),
                  ),
                  const SizedBox(width: 8),
                  if (testResult != null)
                    Expanded(
                      child: Text(
                        testResult!,
                        style: TextStyle(
                          fontSize: 12,
                          color: testResult!.contains('成功')
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final apiKey = controller.text.trim();
                if (apiKey.isNotEmpty) {
                  await _aiManager.setApiKey(AIProvider.deepseek, apiKey);
                  setState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('DeepSeek API Key已保存')),
                    );
                  }
                } else {
                  await _aiManager.clearApiKey(AIProvider.deepseek);
                  setState(() {});
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 配置SiliconFlow API
  Future<void> _configureSiliconFlowApi() async {
    final currentKey = _aiManager.getApiKey(AIProvider.siliconflow);
    final controller = TextEditingController(text: currentKey);
    String? testResult;
    bool isTesting = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('配置 SiliconFlow API'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'API Key（可选）',
                  hintText: '从 siliconflow.cn 获取（新用户送¥20）',
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '免费模型：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Qwen2.5-7B: 完全免费\n'
                      '• 适合简单问答和备用\n'
                      '• 新用户送¥20额度',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 验证按钮和结果
              Row(
                children: [
                  TextButton.icon(
                    onPressed: isTesting || controller.text.isEmpty
                        ? null
                        : () async {
                            setDialogState(() {
                              isTesting = true;
                              testResult = null;
                            });

                            final testService = SiliconFlowService();
                            testService.setApiKey(controller.text);
                            final result = await testService.askQuestion(
                              'Hello, this is a test.',
                              context: [],
                            );

                            setDialogState(() {
                              isTesting = false;
                              testResult = result != null
                                  ? '连接成功！'
                                  : '连接失败';
                            });
                          },
                    icon: isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('测试连接'),
                  ),
                  const SizedBox(width: 8),
                  if (testResult != null)
                    Expanded(
                      child: Text(
                        testResult!,
                        style: TextStyle(
                          fontSize: 12,
                          color: testResult!.contains('成功')
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final apiKey = controller.text.trim();
                if (apiKey.isNotEmpty) {
                  await _aiManager.setApiKey(AIProvider.siliconflow, apiKey);
                  setState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('SiliconFlow API Key已保存')),
                    );
                  }
                } else {
                  await _aiManager.clearApiKey(AIProvider.siliconflow);
                  setState(() {});
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _configureKimiApi() async {
    final controller = TextEditingController(text: _kimiApiKey);
    String? testResult;
    bool isTesting = false;
    bool useKimiCode = false; // 默认使用Moonshot

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('配置 Kimi API'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '从 moonshot.cn 或 kimi.com/code 获取',
                  helperText: '建议使用 Moonshot API',
                ),
              ),
              const SizedBox(height: 12),
              // 平台选择
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'API平台选择',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Moonshot'),
                          icon: Icon(Icons.cloud),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('KimiCode'),
                          icon: Icon(Icons.code),
                        ),
                      ],
                      selected: {useKimiCode},
                      onSelectionChanged: (value) {
                        setDialogState(() {
                          useKimiCode = value.first;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      useKimiCode
                          ? 'KimiCode: 仅限编程Agent工具使用，普通调用可能受限'
                          : 'Moonshot: 推荐，稳定可靠，支持所有功能',
                      style: TextStyle(
                        fontSize: 12,
                        color: useKimiCode ? Colors.orange.shade700 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 8),
              const Text(
                'API Key仅存储在本地，用于云端AI分析。不使用云端时可留空。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // 验证按钮和结果
              Row(
                children: [
                  TextButton.icon(
                    onPressed: isTesting || controller.text.isEmpty
                        ? null
                        : () async {
                            setDialogState(() {
                              isTesting = true;
                              testResult = null;
                            });

                            // 测试API连接
                            final result = await _testApiConnection(controller.text, useKimiCode: useKimiCode);

                            setDialogState(() {
                              isTesting = false;
                              testResult = result;
                            });
                          },
                    icon: isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('测试连接'),
                  ),
                  const SizedBox(width: 8),
                  if (testResult != null)
                    Expanded(
                      child: Text(
                        testResult!,
                        style: TextStyle(
                          fontSize: 12,
                          color: testResult!.contains('成功')
                              ? Colors.green
                              : Colors.red,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),

              // 当前状态
              if (_kimiApiKey != null && _kimiApiKey!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kimiService.isAvailable
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _kimiService.isAvailable
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _kimiService.isAvailable
                            ? Icons.check_circle
                            : Icons.warning,
                        size: 16,
                        color: _kimiService.isAvailable
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _kimiService.isAvailable
                              ? 'API已配置且可用'
                              : 'API已配置但不可用',
                          style: TextStyle(
                            fontSize: 12,
                            color: _kimiService.isAvailable
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final apiKey = controller.text.trim();
                if (apiKey.isNotEmpty) {
                  setState(() => _kimiApiKey = apiKey);
                  // 传递平台选择参数，默认使用Moonshot（useKimiCode=false）
                  _kimiService.setApiKey(apiKey, useKimiCode: useKimiCode);
                  await _settingsService.setKimiApiKey(apiKey);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(useKimiCode
                            ? 'API Key已保存（KimiCode平台）'
                            : 'API Key已保存（Moonshot平台）'),
                      ),
                    );
                  }
                } else {
                  // 清空API Key
                  setState(() => _kimiApiKey = null);
                  await _settingsService.clearKimiApiKey();
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // 测试API连接
  Future<String> _testApiConnection(String apiKey, {bool useKimiCode = false}) async {
    try {
      // 创建临时服务测试
      final testService = KimiService();
      testService.setApiKey(apiKey, useKimiCode: useKimiCode);

      // 发送测试请求
      final response = await testService.askQuestion(
        'Hello, this is a test message. Please reply with "API test successful" only.',
        context: [],
      );

      if (response != null && response.isNotEmpty) {
        return '连接成功！AI已响应';
      } else {
        return '连接失败：无响应';
      }
    } on Exception catch (e) {
      return '连接失败：$e';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // 通知设置
          _buildSection('通知设置', [
            SwitchListTile(
              title: const Text('启用通知'),
              subtitle: const Text('接收智能提醒和待办事项通知'),
              value: _notificationsEnabled,
              onChanged: (value) async {
                setState(() => _notificationsEnabled = value);
                if (value) {
                  // 请求通知权限
                }
              },
            ),
            ListTile(
              title: const Text('每日摘要时间'),
              subtitle: Text('当前: $_dailySummaryTime'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTimePicker(),
            ),
            ListTile(
              title: const Text('每日AI建议上限'),
              subtitle: Text('$_maxSuggestionsPerDay 次'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSuggestionsDialog(),
            ),
          ]),

          // 录音设置
          _buildSection('录音设置', [
            SwitchListTile(
              title: const Text('自动环境录音'),
              subtitle: const Text('启动后自动开始24小时环境录音'),
              value: _autoRecording,
              onChanged: (value) async {
                setState(() => _autoRecording = value);
                // 保存到SharedPreferences
                await _settingsService.setAutoRecordingEnabled(value);
                if (value) {
                  final result = await _recordingService.startBackgroundRecording();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result ? '后台录音已启动' : '启动后台录音失败'),
                        backgroundColor: result ? Colors.green : Colors.red,
                      ),
                    );
                  }
                } else {
                  await _recordingService.stopBackgroundRecording();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('后台录音已停止')),
                    );
                  }
                }
              },
            ),
            ListTile(
              title: const Text('录音质量'),
              trailing: DropdownButton<String>(
                value: _recordingQuality,
                underline: const SizedBox(),
                items: ['低', '标准', '高'].map((e) =>
                  DropdownMenuItem(value: e, child: Text(e))
                ).toList(),
                onChanged: (value) async {
                  if (value != null) {
                    setState(() => _recordingQuality = value);
                    await _settingsService.setRecordingQuality(value);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('录音保留期限'),
              subtitle: Text('$_recordingRetentionDays 天后自动删除'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showRetentionDialog(),
            ),
          ]),

          // 通话录音设置
          _buildSection('通话录音', [
            SwitchListTile(
              title: const Text('通话检测'),
              subtitle: const Text('检测通话状态，避免与系统录音冲突'),
              value: _enableCallDetection,
              onChanged: (value) {
                setState(() => _enableCallDetection = value);
                _saveSettings();
              },
            ),
            SwitchListTile(
              title: const Text('自动导入系统录音'),
              subtitle: const Text('通话结束后自动导入华为/小米等系统录音'),
              value: _autoImportSystemRecordings,
              onChanged: _enableCallDetection
                  ? (value) {
                      setState(() => _autoImportSystemRecordings = value);
                      _saveSettings();
                    }
                  : null,
            ),
            ListTile(
              title: const Text('导入历史录音'),
              subtitle: const Text('手动扫描并导入系统通话录音'),
              leading: const Icon(Icons.phone_in_talk),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _importSystemRecordings(),
            ),
            if (_enableCallDetection)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '工作原理',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. 通话开始时，MemoryPal 自动暂停环境录音\n'
                      '2. 通话结束后，自动恢复环境录音\n'
                      '3. 如开启自动导入，将导入系统通话录音并 AI 分析',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade800,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
          ]),

          // AI设置
          _buildSection('AI设置', [
            // AI提供商选择
            ListTile(
              title: const Text('AI服务提供商'),
              subtitle: Text(_aiManager.currentProviderName),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectAIProvider,
            ),
            // 当前提供商的API配置
            ListTile(
              title: const Text('配置 API Key'),
              subtitle: Text(_getApiKeyStatus()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _configureCurrentApi,
            ),
            // 自动降级开关
            SwitchListTile(
              title: const Text('自动切换到备用服务'),
              subtitle: const Text('首选服务失败时自动尝试其他服务'),
              value: _aiManager.autoFallback,
              onChanged: (value) {
                setState(() {
                  _aiManager.setAutoFallback(value);
                });
              },
            ),
            SwitchListTile(
              title: const Text('启用云端分析'),
              subtitle: const Text('夜间充电时进行深度AI分析'),
              value: _cloudAnalysis,
              onChanged: (value) {
                setState(() => _cloudAnalysis = value);
                _kimiService.setEnabled(value);
                _saveSettings();
              },
            ),
            SwitchListTile(
              title: const Text('夜间分析'),
              subtitle: const Text('23:00-06:00期间进行分析'),
              value: _nightAnalysis,
              onChanged: (value) {
                setState(() => _nightAnalysis = value);
                _saveSettings();
              },
            ),
            ListTile(
              title: const Text('月度API预算'),
              subtitle: Text(_monthlyBudget > 0 ? '¥$_monthlyBudget' : '无限制'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showBudgetDialog(),
            ),
          ]),

          // 位置设置
          _buildSection('位置设置', [
            SwitchListTile(
              title: const Text('基于位置的建议'),
              subtitle: const Text('根据位置提供智能提醒'),
              value: _locationBased,
              onChanged: (value) {
                setState(() => _locationBased = value);
                _saveSettings();
              },
            ),
          ]),

          // 数据导出（用于优化建议）
          const DataExportSection(),

          // 数据管理
          _buildSection('数据管理', [
            ListTile(
              title: const Text('导出所有数据'),
              subtitle: const Text('创建加密备份文件'),
              leading: const Icon(Icons.download),
              trailing: _isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isExporting ? null : _exportData,
            ),
            ListTile(
              title: const Text('导入数据'),
              subtitle: const Text('从备份文件恢复'),
              leading: const Icon(Icons.upload),
              trailing: _isImporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isImporting ? null : _importData,
            ),
            ListTile(
              title: const Text('清除所有数据', style: TextStyle(color: Colors.red)),
              subtitle: const Text('删除所有录音、笔记和设置'),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              onTap: _clearAllData,
            ),
          ]),

          // 关于
          _buildSection('关于', [
            // 版本号（连续点击7次开启开发者模式）
            ListTile(
              title: const Text('版本'),
              trailing: GestureDetector(
                onTap: () async {
                  final triggered = await _developerService.checkDeveloperModeTrigger();
                  if (triggered && mounted) {
                    setState(() => _isDeveloperMode = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('开发者模式已开启'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isDeveloperMode ? Colors.orange.withOpacity(0.2) : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '1.0.0${_isDeveloperMode ? " (Dev)" : ""}',
                    style: TextStyle(
                      color: _isDeveloperMode ? Colors.orange : null,
                      fontWeight: _isDeveloperMode ? FontWeight.bold : null,
                    ),
                  ),
                ),
              ),
            ),
            ListTile(
              title: const Text('隐私政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPrivacyPolicy(),
            ),
            ListTile(
              title: const Text('使用条款'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTermsOfService(),
            ),
            // 开发者选项（仅在开发者模式下显示）
            if (_isDeveloperMode)
              ListTile(
                title: const Text(
                  '开发者选项',
                  style: TextStyle(color: Colors.orange),
                ),
                subtitle: const Text('系统诊断、日志查看、问题报告'),
                leading: const Icon(Icons.developer_mode, color: Colors.orange),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DeveloperScreen(),
                    ),
                  );
                },
              ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Future<void> _showTimePicker() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(_dailySummaryTime.split(':')[0]),
        minute: int.parse(_dailySummaryTime.split(':')[1]),
      ),
    );
    if (time != null) {
      setState(() {
        _dailySummaryTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      });
      _saveSettings();
    }
  }

  Future<void> _showSuggestionsDialog() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('每日AI建议上限'),
        children: [1, 2, 3, 5, 10].map((n) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, n),
          child: Text('$n 次'),
        )).toList(),
      ),
    );
    if (result != null) {
      setState(() => _maxSuggestionsPerDay = result);
      _saveSettings();
    }
  }

  Future<void> _showRetentionDialog() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('录音保留期限'),
        children: [7, 14, 30, 60, 90].map((n) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, n),
          child: Text('$n 天'),
        )).toList(),
      ),
    );
    if (result != null) {
      setState(() => _recordingRetentionDays = result);
      _saveSettings();
    }
  }

  Future<void> _showBudgetDialog() async {
    final controller = TextEditingController(
      text: _monthlyBudget > 0 ? _monthlyBudget.toString() : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('月度API预算'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '预算（元）',
            hintText: '0表示无限制',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('无限制'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text) ?? 0),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _monthlyBudget = result);
      _saveSettings();
    }
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隐私政策'),
        content: const SingleChildScrollView(
          child: Text('''
MemoryPal 隐私政策

1. 数据存储
• 所有数据（录音、笔记、画像）仅存储在本地设备
• 不使用云端服务器存储用户数据
• 可选的云端AI分析仅传输文本摘要

2. 权限使用
• 麦克风：用于录音功能
• 位置：用于基于位置的建议
• 通知：用于待办提醒

3. 用户控制
• 可随时导出或删除所有数据
• 可完全禁用云端功能，纯离线使用
• 可随时撤销权限

4. 第三方服务
• 云端分析使用Kimi API（可选）
• 反向地理编码使用高德/百度API（可选）

我们尊重你的隐私，你的数据永远属于你。
          '''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }

  void _showTermsOfService() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用条款'),
        content: const SingleChildScrollView(
          child: Text('''
MemoryPal 使用条款

1. 服务说明
MemoryPal是一款24小时个人智能助理应用，帮助用户记录和管理信息。

2. 用户责任
• 合法使用本应用
• 不用于侵犯他人隐私
• 自行备份重要数据

3. 免责声明
• 应用按"原样"提供，不作任何担保
• 因设备问题导致的数据丢失不承担责任
• AI分析结果仅供参考

4. 知识产权
应用及相关技术归开发者所有。
          '''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }

  Future<void> _importSystemRecordings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入系统通话录音'),
        content: const Text(
            '将扫描华为、小米等系统的通话录音目录，并导入到 MemoryPal 进行分析。\n\n注意：需要授予存储权限才能访问系统录音文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始扫描'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在扫描系统录音...'),
          ],
        ),
      ),
    );

    try {
      final importer = SystemRecordingImporter();
      final imported = await importer.scanAllSystemRecordings();

      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框

        if (imported.isEmpty) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('未找到录音'),
              content: const Text(
                  '未在系统目录中找到通话录音文件。\n\n可能原因：\n'
                  '1. 手机没有通话录音功能或未开启\n'
                  '2. 录音文件存储在其他路径\n'
                  '3. 存储权限未授予\n\n'
                  '支持的机型：华为、小米、OPPO、vivo、三星'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        } else {
          // 导入到数据库并触发转写
          for (final recording in imported) {
            final id = await _databaseService.insertRecording(recording);
            if (id > 0) {
              // 触发自动转写
              await _recordingService.startTranscription(id, recording.filePath);
            }
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('导入成功'),
              content: Text('已导入 ${imported.length} 条通话录音，Whisper 转写将在后台自动进行。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框

        if (e.toString().contains('权限')) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('需要权限'),
              content: const Text(
                  '需要存储权限才能访问系统录音文件。\n\n请在系统设置中授予存储权限。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('去设置'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
