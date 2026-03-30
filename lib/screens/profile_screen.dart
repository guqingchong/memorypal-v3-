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
}