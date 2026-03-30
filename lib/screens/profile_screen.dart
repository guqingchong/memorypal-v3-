import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';
import '../widgets/ai_insight_card.dart';
import 'profile_edit_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _databaseService = DatabaseService();
  UserProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final profile = await _databaseService.getUserProfile();
    setState(() {
      _profile = profile ?? UserProfile(lastUpdated: DateTime.now());
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    if (_profile != null) {
      await _databaseService.saveUserProfile(_profile!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的画像'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileEditScreen(profile: _profile!),
                ),
              ).then((_) => _loadProfile());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_profile == null) {
      return const Center(child: Text('暂无画像数据'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 基础信息
        _buildSection(
          title: '👤 基础信息',
          children: [
            _buildInfoItem('姓名', _profile!.name),
            _buildInfoItem('职业', _profile!.occupation),
            _buildInfoItem('地址', _profile!.address),
          ],
        ),

        const SizedBox(height: 16),

        // AI观察到的
        _buildSection(
          title: '🧠 AI观察到的你',
          children: [
            _buildInfoItemWithConfidence(
              '性格',
              _profile!.personality,
              _profile!.getConfidence('personality'),
            ),
            if (_profile!.habits.isNotEmpty)
              _buildTagItem('习惯', _profile!.habits),
            if (_profile!.interests.isNotEmpty)
              _buildTagItem('兴趣', _profile!.interests),
            if (_profile!.workCircle.isNotEmpty)
              _buildTagItem('工作圈', _profile!.workCircle),
          ],
        ),

        const SizedBox(height: 16),

        // 待确认观察（本周）
        _buildPendingConfirmationsSection(),

        const SizedBox(height: 16),

        // AI 洞察卡片
        AIInsightCard(profile: _profile!),

        const SizedBox(height: 16),

        // 目标与困惑
        _buildSection(
          title: '🎯 目标与困惑',
          children: [
            _buildInfoItem('短期目标', _profile!.shortTermGoals ?? '未设置'),
            _buildInfoItem('长期理想', _profile!.longTermDreams ?? '未设置'),
            _buildInfoItem('当前困惑', _profile!.currentConfusions ?? '未设置'),
          ],
        ),

        const SizedBox(height: 32),

        // 操作按钮
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: 导出数据
                },
                icon: const Icon(Icons.download),
                label: const Text('导出数据'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: 清除数据
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('清除全部', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '未知',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItemWithConfidence(String label, String? value, double confidence) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value ?? '未知',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: confidence,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    confidence > 0.8 ? Colors.green : confidence > 0.5 ? Colors.orange : Colors.red,
                  ),
                ),
                Text(
                  '置信度: ${(confidence * 100).toInt()}%',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagItem(String label, List<String> tags) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: tags.map((tag) => Chip(
                label: Text(tag),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 待确认观察部分
  Widget _buildPendingConfirmationsSection() {
    // 模拟待确认数据
    final pendingItems = _getPendingConfirmations();

    if (pendingItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSection(
      title: '📋 待确认观察（本周）',
      children: [
        Text(
          'AI检测到以下可能符合你的信息，请确认：',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        ...pendingItems.map((item) => _buildPendingItem(item)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _confirmAllPending(pendingItems),
                child: const Text('确认全部'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _dismissAllPending(),
                child: const Text('都不对'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<_PendingItem> _getPendingConfirmations() {
    // 从profile中提取待确认项（置信度0.5-0.8）
    final pending = <_PendingItem>[];

    _profile?.confidence.forEach((field, confidence) {
      if (confidence >= 0.5 && confidence < 0.8) {
        String? value;
        String description = '';

        switch (field) {
          case 'personality':
            value = _profile?.personality;
            description = '性格特点';
            break;
          case 'habits':
            if (_profile!.habits.isNotEmpty) {
              value = _profile!.habits.last;
              description = '生活习惯';
            }
            break;
          case 'interests':
            if (_profile!.interests.isNotEmpty) {
              value = _profile!.interests.last;
              description = '兴趣爱好';
            }
            break;
        }

        if (value != null) {
          pending.add(_PendingItem(
            field: field,
            value: value,
            description: description,
            confidence: confidence,
          ));
        }
      }
    });

    return pending;
  }

  Widget _buildPendingItem(_PendingItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Checkbox(
            value: false,
            onChanged: (v) {},
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.description}: ${item.value}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: item.confidence,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(Colors.orange),
                ),
                Text(
                  '置信度: ${(item.confidence * 100).toInt()}%',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmAllPending(List<_PendingItem> items) {
    // 更新置信度为0.9（已确认）
    for (final item in items) {
      _profile?.confidence[item.field] = 0.9;
    }
    _saveProfile();
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已确认观察项')),
    );
  }

  void _dismissAllPending() {
    // 移除低置信度观察
    _profile?.confidence.removeWhere((k, v) => v < 0.8);
    _saveProfile();
    setState(() {});
  }
}

class _PendingItem {
  final String field;
  final String value;
  final String description;
  final double confidence;

  _PendingItem({
    required this.field,
    required this.value,
    required this.description,
    required this.confidence,
  });
}