import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';

class ProfileEditScreen extends StatefulWidget {
  final UserProfile profile;

  const ProfileEditScreen({super.key, required this.profile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _databaseService = DatabaseService();
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _occupationController;
  late TextEditingController _addressController;
  late TextEditingController _shortTermGoalsController;
  late TextEditingController _longTermDreamsController;
  late TextEditingController _currentConfusionsController;
  late TextEditingController _personalityController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _occupationController = TextEditingController(text: widget.profile.occupation);
    _addressController = TextEditingController(text: widget.profile.address);
    _shortTermGoalsController = TextEditingController(text: widget.profile.shortTermGoals ?? '');
    _longTermDreamsController = TextEditingController(text: widget.profile.longTermDreams ?? '');
    _currentConfusionsController = TextEditingController(text: widget.profile.currentConfusions ?? '');
    _personalityController = TextEditingController(text: widget.profile.personality ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _occupationController.dispose();
    _addressController.dispose();
    _shortTermGoalsController.dispose();
    _longTermDreamsController.dispose();
    _currentConfusionsController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final updatedProfile = UserProfile(
      name: _nameController.text.trim(),
      occupation: _occupationController.text.trim(),
      address: _addressController.text.trim(),
      personality: _personalityController.text.trim().isEmpty ? null : _personalityController.text.trim(),
      shortTermGoals: _shortTermGoalsController.text.trim().isEmpty ? null : _shortTermGoalsController.text.trim(),
      longTermDreams: _longTermDreamsController.text.trim().isEmpty ? null : _longTermDreamsController.text.trim(),
      currentConfusions: _currentConfusionsController.text.trim().isEmpty ? null : _currentConfusionsController.text.trim(),
      habits: widget.profile.habits,
      interests: widget.profile.interests,
      workCircle: widget.profile.workCircle,
      confidence: widget.profile.confidence,
      lastUpdated: DateTime.now(),
    );

    await _databaseService.saveUserProfile(updatedProfile);

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑画像'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 基础信息
            _buildSection(
              title: '基础信息',
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _occupationController,
                  decoration: const InputDecoration(
                    labelText: '职业',
                    prefixIcon: Icon(Icons.work),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: '地址',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // AI 观察到的
            _buildSection(
              title: 'AI 观察（可手动修正）',
              children: [
                TextFormField(
                  controller: _personalityController,
                  decoration: const InputDecoration(
                    labelText: '性格',
                    prefixIcon: Icon(Icons.psychology),
                    helperText: '例如：外向、内向、理性、感性等',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 目标与困惑
            _buildSection(
              title: '目标与困惑',
              children: [
                TextFormField(
                  controller: _shortTermGoalsController,
                  decoration: const InputDecoration(
                    labelText: '短期目标（3-6个月）',
                    prefixIcon: Icon(Icons.flag),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _longTermDreamsController,
                  decoration: const InputDecoration(
                    labelText: '长期理想（3-5年）',
                    prefixIcon: Icon(Icons.star),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _currentConfusionsController,
                  decoration: const InputDecoration(
                    labelText: '当前困惑/疑问',
                    prefixIcon: Icon(Icons.help_outline),
                  ),
                  maxLines: 3,
                ),
              ],
            ),

            const SizedBox(height: 32),

            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 会持续学习和更新您的画像。您提供的信息越准确，AI 的建议就越个性化。',
                      style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
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

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}
