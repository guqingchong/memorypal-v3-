import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _notificationService = NotificationService();
  final _databaseService = DatabaseService();

  bool _notificationsEnabled = true;
  bool _autoRecording = false;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // TODO: 从SharedPreferences加载设置
  }

  @override
  Widget build(BuildContext context) {
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
              onChanged: (value) {
                setState(() => _notificationsEnabled = value);
              },
            ),
          ]),

          // 录音设置
          _buildSection('录音设置', [
            SwitchListTile(
              title: const Text('自动环境录音'),
              subtitle: const Text('在特定时间段自动开始录音'),
              value: _autoRecording,
              onChanged: (value) {
                setState(() => _autoRecording = value);
              },
            ),
            ListTile(
              title: const Text('录音质量'),
              trailing: DropdownButton<String>(
                value: '标准',
                items: ['低', '标准', '高'].map((e) =>
                  DropdownMenuItem(value: e, child: Text(e))
                ).toList(),
                onChanged: (value) {},
              ),
            ),
          ]),

          // AI设置
          _buildSection('AI设置', [
            ListTile(
              title: const Text('AI模型'),
              subtitle: const Text('配置AI分析接口'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: 打开AI配置页面
              },
            ),
            ListTile(
              title: const Text('置信度阈值'),
              subtitle: const Text('设置AI识别置信度'),
              trailing: const Text('0.7'),
              onTap: () {},
            ),
          ]),

          // 数据管理
          _buildSection('数据管理', [
            ListTile(
              title: const Text('导出所有数据'),
              leading: const Icon(Icons.download),
              onTap: _exportData,
            ),
            ListTile(
              title: const Text('导入数据'),
              leading: const Icon(Icons.upload),
              onTap: _importData,
            ),
            ListTile(
              title: const Text('清除所有数据', style: TextStyle(color: Colors.red)),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              onTap: _clearAllData,
            ),
          ]),

          // 关于
          _buildSection('关于', [
            const ListTile(
              title: Text('版本'),
              trailing: Text('1.0.0'),
            ),
            ListTile(
              title: const Text('隐私政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              title: const Text('使用条款'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ]),
        ],
      ),
    );
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

  Future<void> _exportData() async {
    // TODO: 实现数据导出
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('数据导出功能开发中')),
    );
  }

  Future<void> _importData() async {
    // TODO: 实现数据导入
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('数据导入功能开发中')),
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
      // TODO: 清除所有数据
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有数据已清除')),
      );
    }
  }
}
