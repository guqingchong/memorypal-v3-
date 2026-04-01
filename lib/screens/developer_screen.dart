import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/developer_service.dart';
import '../services/recording_service.dart';

/// 开发者选项页面
///
/// 提供系统诊断、日志查看、问题报告等功能
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final _developerService = DeveloperService();
  final _recordingService = RecordingService();

  DiagnosticReport? _lastReport;
  bool _isRunningDiagnostic = false;
  bool _showAllLogs = false;

  @override
  void initState() {
    super.initState();
    _developerService.initialize();
  }

  @override
  void dispose() {
    _developerService.dispose();
    super.dispose();
  }

  Future<void> _runDiagnostic() async {
    setState(() => _isRunningDiagnostic = true);

    final report = await _developerService.runFullDiagnostic();

    if (mounted) {
      setState(() {
        _lastReport = report;
        _isRunningDiagnostic = false;
      });

      // 显示结果摘要
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(report.summary),
          backgroundColor: report.overallStatus == DiagnosticStatus.error
              ? Colors.red
              : report.overallStatus == DiagnosticStatus.warning
                  ? Colors.orange
                  : Colors.green,
        ),
      );
    }
  }

  Future<void> _exportLogs() async {
    // 显示选项菜单
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出日志'),
        content: const Text('选择导出方式：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'internal'),
            child: const Text('应用目录'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'download'),
            child: const Text('Download文件夹'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'share'),
            child: const Text('分享到微信/邮件'),
          ),
        ],
      ),
    );

    if (result == null) return;

    if (result == 'internal') {
      final path = await _developerService.exportLogs();
      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('日志已导出到: $path')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导出失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (result == 'download') {
      final path = await _developerService.exportLogsToDownloads();
      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('日志已保存到Download文件夹\n文件名: ${path.split('/').last}'),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导出到Download失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (result == 'share') {
      final success = await _developerService.shareLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '日志分享成功' : '日志分享失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateIssueReport() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在生成问题报告...'),
          ],
        ),
      ),
    );

    final report = await _developerService.generateIssueReport();

    if (mounted) {
      Navigator.pop(context);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('问题报告'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(report),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: report));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('报告已复制到剪贴板')),
                );
              },
              child: const Text('复制全部'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _testRecording() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('录音测试'),
        content: const Text('选择要测试的录音功能：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _testNormalRecording();
            },
            child: const Text('普通录音'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _testBackgroundRecording();
            },
            child: const Text('后台录音'),
          ),
        ],
      ),
    );
  }

  Future<void> _testNormalRecording() async {
    final hasPermission = await _checkPermission('麦克风');
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要麦克风权限'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _RecordingTestDialog(
          recordingService: _recordingService,
          onComplete: (success, message) {
            Navigator.pop(context);
            _developerService.log(
              '录音测试结果: $message',
              level: success ? LogLevel.info : LogLevel.error,
              tag: 'Test',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          },
        ),
      );
    }
  }

  Future<void> _testBackgroundRecording() async {
    final result = await _recordingService.startBackgroundRecording();
    _developerService.log(
      '后台录音测试: ${result ? "成功" : "失败"}',
      level: result ? LogLevel.info : LogLevel.error,
      tag: 'Test',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? '后台录音已启动' : '后台录音启动失败'),
          backgroundColor: result ? Colors.green : Colors.red,
          action: result
              ? SnackBarAction(
                  label: '停止',
                  onPressed: () async {
                    await _recordingService.stopBackgroundRecording();
                    _developerService.log('后台录音已停止', tag: 'Test');
                  },
                )
              : null,
        ),
      );
    }
  }

  Future<bool> _checkPermission(String permission) async {
    // 简化实现，实际需要检查具体权限
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者选项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _generateIssueReport,
            tooltip: '生成问题报告',
          ),
        ],
      ),
      body: ListView(
        children: [
          // 诊断卡片
          _buildDiagnosticCard(),

          // 快速测试
          _buildSection('功能测试', [
            ListTile(
              leading: const Icon(Icons.mic, color: Colors.blue),
              title: const Text('录音功能测试'),
              subtitle: const Text('测试普通录音和后台录音'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _testRecording,
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload, color: Colors.green),
              title: const Text('网络连接测试'),
              subtitle: const Text('测试Kimi API连接'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _developerService.log('网络测试待实现', tag: 'Test');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('网络测试功能开发中')),
                );
              },
            ),
          ]),

          // 日志管理
          _buildSection('日志管理', [
            ListTile(
              leading: const Icon(Icons.article, color: Colors.orange),
              title: const Text('查看日志'),
              subtitle: const Text('查看应用运行日志'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LogViewerScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.purple),
              title: const Text('导出日志'),
              subtitle: const Text('导出到Download或分享到微信'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportLogs,
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('清空日志'),
              subtitle: const Text('清除所有日志记录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认清空'),
                    content: const Text('确定要清空所有日志吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          _developerService.clearLogs();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日志已清空')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ]),

          // 系统信息
          _buildSection('系统信息', [
            const ListTile(
              leading: Icon(Icons.info, color: Colors.blue),
              title: Text('应用版本'),
              subtitle: Text('1.0.0 (Build 20240401)'),
            ),
            ListTile(
              leading: const Icon(Icons.storage, color: Colors.green),
              title: const Text('数据存储'),
              subtitle: const Text('点击检查存储状态'),
              onTap: () async {
                final dir = await _getAppDirectory();
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('存储信息'),
                      content: Text(dir ?? '无法获取存储路径'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ]),

          const SizedBox(height: 32),

          // 关闭开发者模式
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () async {
                await _developerService.disableDeveloperMode();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('开发者模式已关闭')),
                  );
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.exit_to_app),
              label: const Text('关闭开发者模式'),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDiagnosticCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '系统诊断',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_lastReport != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(_lastReport!.overallStatus),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _lastReport!.overallStatusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_lastReport != null) ...[
              Text(_lastReport!.summary),
              const SizedBox(height: 12),
              if (_lastReport!.errors.isNotEmpty)
                _buildIssueList('错误', _lastReport!.errors, Colors.red),
              if (_lastReport!.warnings.isNotEmpty)
                _buildIssueList('警告', _lastReport!.warnings, Colors.orange),
            ] else
              const Text('点击运行诊断检查系统状态'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRunningDiagnostic ? null : _runDiagnostic,
                icon: _isRunningDiagnostic
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isRunningDiagnostic ? '诊断中...' : '运行诊断'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueList(String title, List<DiagnosticResult> issues, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${issues.length})',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        ...issues.map((issue) => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Text(
                '• ${issue.name}: ${issue.message}',
                style: TextStyle(fontSize: 13, color: color),
              ),
            )),
        const SizedBox(height: 8),
      ],
    );
  }

  Color _getStatusColor(DiagnosticStatus status) {
    switch (status) {
      case DiagnosticStatus.ok:
        return Colors.green;
      case DiagnosticStatus.warning:
        return Colors.orange;
      case DiagnosticStatus.error:
        return Colors.red;
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

  Future<String?> _getAppDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stat = await dir.stat();
      return '路径: ${dir.path}\n修改时间: ${stat.modified}';
    } catch (e) {
      return '获取失败: $e';
    }
  }
}

/// 录音测试对话框
class _RecordingTestDialog extends StatefulWidget {
  final RecordingService recordingService;
  final Function(bool success, String message) onComplete;

  const _RecordingTestDialog({
    required this.recordingService,
    required this.onComplete,
  });

  @override
  State<_RecordingTestDialog> createState() => _RecordingTestDialogState();
}

class _RecordingTestDialogState extends State<_RecordingTestDialog> {
  bool _isRecording = false;
  int _seconds = 0;

  Future<void> _startTest() async {
    setState(() => _isRecording = true);

    final result = await widget.recordingService.startRecording();

    if (!result) {
      widget.onComplete(false, '录音启动失败');
      return;
    }

    // 录制3秒
    for (var i = 0; i < 3; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() => _seconds++);
      }
    }

    await widget.recordingService.stopRecording();
    widget.onComplete(true, '录音测试成功 (${_seconds}秒)');
  }

  @override
  void initState() {
    super.initState();
    _startTest();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('录音测试中'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在录制测试音频... $_seconds秒'),
          const SizedBox(height: 8),
          const Text(
            '请对着麦克风说话',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.recordingService.stopRecording();
            widget.onComplete(false, '测试已取消');
          },
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 日志查看页面
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final _developerService = DeveloperService();
  LogLevel _minLevel = LogLevel.debug;

  @override
  void initState() {
    super.initState();
    _developerService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final logs = _developerService.getLogs(minLevel: _minLevel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('应用日志'),
        actions: [
          PopupMenuButton<LogLevel>(
            initialValue: _minLevel,
            onSelected: (level) {
              setState(() => _minLevel = level);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: LogLevel.verbose, child: Text('Verbose')),
              const PopupMenuItem(value: LogLevel.debug, child: Text('Debug')),
              const PopupMenuItem(value: LogLevel.info, child: Text('Info')),
              const PopupMenuItem(value: LogLevel.warning, child: Text('Warning')),
              const PopupMenuItem(value: LogLevel.error, child: Text('Error')),
            ],
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.builder(
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index];
                return _buildLogItem(log);
              },
            ),
    );
  }

  Widget _buildLogItem(AppLog log) {
    Color color;
    switch (log.level) {
      case LogLevel.error:
        color = Colors.red;
        break;
      case LogLevel.warning:
        color = Colors.orange;
        break;
      case LogLevel.info:
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }

    return ListTile(
      dense: true,
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        '[${log.tag}] ${log.message}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${log.formattedTime} [${log.level.name}]',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      onTap: log.error != null
          ? () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('错误详情'),
                  content: SingleChildScrollView(
                    child: Text(log.error!),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            }
          : null,
    );
  }
}
