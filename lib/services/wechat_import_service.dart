import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notification_service.dart';

/// 微信聊天记录导入服务
///
/// 采用"智能提醒 + 快捷导入"方案：
/// 1. 检测用户前台使用微信
/// 2. 使用超过5分钟后显示轻量提醒
/// 3. 用户回到APP后提示快捷导入
class WeChatImportService {
  static final WeChatImportService _instance = WeChatImportService._internal();
  factory WeChatImportService() => _instance;
  WeChatImportService._internal();

  final NotificationService _notificationService = NotificationService();

  // MethodChannel用于检测前台应用
  static const MethodChannel _channel = MethodChannel('com.memorypal/wechat');

  Timer? _usageTimer;
  int _weChatUsageSeconds = 0;
  bool _isWeChatActive = false;
  DateTime? _weChatStartTime;

  // 提醒阈值（5分钟）
  static const int _reminderThreshold = 300; // 5分钟

  // 是否启用了自动检测（需要特殊权限）
  bool _autoDetectionEnabled = false;

  /// 初始化服务
  Future<void> initialize() async {
    // 尝试启用自动检测
    _autoDetectionEnabled = await _checkAndRequestUsageStatsPermission();

    if (_autoDetectionEnabled) {
      // 监听原生层的前台应用变化
      _channel.setMethodCallHandler(_handleMethodCall);
      // 启动周期性检查
      _startMonitoring();
    }
  }

  /// 检查并请求Usage Stats权限
  Future<bool> _checkAndRequestUsageStatsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkUsageStatsPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('检查Usage Stats权限失败: $e');
      return false;
    }
  }

  /// 显示手动导入入口
  ///
  /// 由于Android限制，自动检测需要特殊权限
  /// 提供手动导入作为可靠替代方案
  void showManualImportGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SafeArea(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.chat, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            '导入微信聊天记录',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.orange.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '关于自动检测',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '由于Android系统限制，自动检测微信使用情况需要"使用情况访问权限"，该权限需要用户在系统设置中手动开启。',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '推荐方法：手动导入',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildStepTile(
                        number: 1,
                        title: '在微信中选择消息',
                        description: '长按重要消息 → 多选 → 选择多条消息',
                      ),
                      _buildStepTile(
                        number: 2,
                        title: '合并转发',
                        description: '点击"转发" → "合并转发" → 选择"文件传输助手"',
                      ),
                      _buildStepTile(
                        number: 3,
                        title: '复制或截图',
                        description: '打开文件传输助手的合并消息，长按复制文本或截图保存',
                      ),
                      _buildStepTile(
                        number: 4,
                        title: '导入到MemoryPal',
                        description: '点击下方按钮，粘贴文本或选择截图',
                        isLast: true,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _createNoteFromWeChat(context);
                        },
                        icon: const Icon(Icons.note_add),
                        label: const Text('创建微信笔记'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _importFromImage(context);
                        },
                        icon: const Icon(Icons.image),
                        label: const Text('从截图导入（OCR）'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_autoDetectionEnabled)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _openUsageStatsSettings();
                          },
                          icon: const Icon(Icons.settings),
                          label: const Text('开启自动检测（需系统设置）'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepTile({
    required int number,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  /// 打开系统设置中的Usage Stats权限页面
  Future<void> _openUsageStatsSettings() async {
    try {
      await _channel.invokeMethod('openUsageStatsSettings');
    } catch (e) {
      debugPrint('打开设置失败: $e');
    }
  }

  /// 从图片导入（OCR）
  Future<void> _importFromImage(BuildContext context) async {
    // 调用FileImportService导入图片并OCR
    // 这里简化处理，实际需要集成
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请在首页点击"导入文件"选择微信截图')),
    );
  }

  /// 处理原生层回调
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAppForegroundChanged':
        final packageName = call.arguments as String?;
        _handleAppChange(packageName);
        break;
    }
  }

  /// 处理应用切换
  void _handleAppChange(String? packageName) {
    final isWeChatNow = packageName == 'com.tencent.mm';

    if (isWeChatNow && !_isWeChatActive) {
      // 进入微信
      _isWeChatActive = true;
      _weChatStartTime = DateTime.now();
      _startUsageTimer();
    } else if (!isWeChatNow && _isWeChatActive) {
      // 离开微信
      _isWeChatActive = false;
      _stopUsageTimer();

      // 如果使用时间超过阈值，标记需要导入提醒
      if (_weChatUsageSeconds >= _reminderThreshold) {
        _markImportReminderNeeded();
      }

      _weChatUsageSeconds = 0;
    }
  }

  /// 启动监控（简化版：通过定期检测）
  void _startMonitoring() {
    // 每5秒检查一次前台应用
    Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final packageName = await _channel.invokeMethod('getForegroundApp');
        _handleAppChange(packageName as String?);
      } catch (e) {
        // 原生方法可能未实现，忽略错误
      }
    });
  }

  /// 启动使用计时器
  void _startUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _weChatUsageSeconds++;

      // 达到阈值时发送提醒
      if (_weChatUsageSeconds == _reminderThreshold) {
        _showImportReminder();
      }
    });
  }

  /// 停止使用计时器
  void _stopUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = null;
  }

  /// 显示导入提醒
  Future<void> _showImportReminder() async {
    await _notificationService.showAISuggestion(
      id: 9001,
      title: '微信聊天记录',
      suggestion: '检测到你在微信中聊了较长时间，有重要内容需要记录吗？',
      payload: 'wechat_import',
    );
  }

  /// 标记需要显示导入提醒
  Future<void> _markImportReminderNeeded() async {
    // 保存状态，当用户回到APP时显示提醒
    // 这里简化处理，实际可以保存到SharedPreferences
    debugPrint('需要显示微信导入提醒');
  }

  /// 检查是否需要显示导入提醒（在APP恢复时调用）
  Future<bool> shouldShowImportDialog() async {
    // 检查标记状态
    // 简化版：总是返回false，需要手动触发
    return false;
  }

  /// 显示微信导入对话框
  void showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.chat, color: Colors.green),
            SizedBox(width: 8),
            Text('导入微信聊天记录'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('导入步骤：'),
            SizedBox(height: 8),
            Text('1. 在微信中长按重要消息'),
            Text('2. 选择"多选" → "合并转发"'),
            Text('3. 转发到"文件传输助手"'),
            Text('4. 截图或复制文字内容'),
            Text('5. 回到本APP粘贴到笔记'),
            SizedBox(height: 16),
            Text(
              '提示：为保护隐私，我们不直接读取微信数据。请手动选择需要记录的内容。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createNoteFromWeChat(context);
            },
            child: const Text('创建笔记'),
          ),
        ],
      ),
    );
  }

  /// 创建来自微信的笔记
  void _createNoteFromWeChat(BuildContext context) {
    // 打开笔记编辑器，预设标题
    Navigator.pushNamed(
      context,
      '/text_note_editor',
      arguments: {
        'title': '微信记录 ${DateTime.now().month}/${DateTime.now().day}',
        'hint': '粘贴或输入微信聊天内容...',
      },
    );
  }

  /// 获取微信使用统计
  Map<String, dynamic> getUsageStats() {
    return {
      'is_active': _isWeChatActive,
      'usage_seconds': _weChatUsageSeconds,
      'start_time': _weChatStartTime?.toIso8601String(),
    };
  }

  /// 释放资源
  void dispose() {
    _usageTimer?.cancel();
  }
}

/// 微信导入工具类
class WeChatImportHelper {
  /// 解析微信聊天记录文本
  ///
  /// 支持格式：
  /// - 微信默认转发格式
  /// - 手动复制的聊天记录
  static WeChatChatRecord parseChatRecord(String text) {
    final lines = text.split('\n');
    final messages = <WeChatMessage>[];

    String? currentSender;
    StringBuffer currentContent = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 检测发送者（简化规则：包含时间戳的行可能是新消息）
      if (trimmed.contains(':') && _looksLikeTimestamp(trimmed)) {
        // 保存上一条消息
        if (currentSender != null && currentContent.isNotEmpty) {
          messages.add(WeChatMessage(
            sender: currentSender,
            content: currentContent.toString().trim(),
            timestamp: _parseTimestamp(trimmed),
          ));
        }

        // 解析新消息
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          currentSender = parts[0].trim();
          currentContent = StringBuffer(parts.sublist(1).join(':').trim());
        }
      } else {
        // 继续当前消息内容
        currentContent.writeln('\n$trimmed');
      }
    }

    // 保存最后一条消息
    if (currentSender != null && currentContent.isNotEmpty) {
      messages.add(WeChatMessage(
        sender: currentSender,
        content: currentContent.toString().trim(),
        timestamp: DateTime.now(),
      ));
    }

    return WeChatChatRecord(
      messages: messages,
      importedAt: DateTime.now(),
    );
  }

  /// 检测是否像时间戳
  static bool _looksLikeTimestamp(String text) {
    // 简单规则：包含数字和冒号
    return RegExp(r'\d{1,2}:\d{2}').hasMatch(text);
  }

  /// 解析时间戳
  static DateTime _parseTimestamp(String text) {
    // 简化版：返回当前时间
    // 实际应该解析文本中的时间
    return DateTime.now();
  }

  /// 提取关键词和重要信息
  static List<String> extractKeywords(WeChatChatRecord record) {
    final allText = record.messages.map((m) => m.content).join(' ');

    // 简单的关键词提取
    final keywords = <String>[];

    // 检测待办关键词
    final todoPatterns = ['记得', '需要', '应该', '必须', '别忘了', '要做'];
    for (final pattern in todoPatterns) {
      if (allText.contains(pattern)) {
        keywords.add('待办');
        break;
      }
    }

    // 检测会议关键词
    final meetingPatterns = ['开会', '会议', '讨论', '时间', '地点'];
    for (final pattern in meetingPatterns) {
      if (allText.contains(pattern)) {
        keywords.add('会议');
        break;
      }
    }

    return keywords;
  }

  /// 生成笔记标题
  static String generateTitle(WeChatChatRecord record) {
    if (record.messages.isEmpty) return '微信记录';

    final senders = record.messages.map((m) => m.sender).toSet().toList();
    if (senders.length == 1) {
      return '与 ${senders.first} 的聊天记录';
    } else if (senders.length == 2) {
      return '${senders[0]} 与 ${senders[1]} 的对话';
    } else {
      return '群聊记录 (${senders.length}人)';
    }
  }
}

/// 微信聊天记录
class WeChatChatRecord {
  final List<WeChatMessage> messages;
  final DateTime importedAt;

  WeChatChatRecord({
    required this.messages,
    required this.importedAt,
  });

  /// 转换为笔记内容
  String toNoteContent() {
    final buffer = StringBuffer();
    buffer.writeln('## 微信聊天记录');
    buffer.writeln('导入时间: ${importedAt.toString()}\n');

    for (final message in messages) {
      buffer.writeln('**${message.sender}** (${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}):');
      buffer.writeln('${message.content}\n');
    }

    return buffer.toString();
  }
}

/// 微信消息
class WeChatMessage {
  final String sender;
  final String content;
  final DateTime timestamp;

  WeChatMessage({
    required this.sender,
    required this.content,
    required this.timestamp,
  });
}
