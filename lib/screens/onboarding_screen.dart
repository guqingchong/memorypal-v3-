import 'package:flutter/material.dart';
import '../utils/permission_manager.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _permissionManager = PermissionManager();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.psychology,
      title: '欢迎使用 MemoryPal',
      description: '您的24小时贴身智能助理\n帮助记录、整理和回忆生活中的重要信息',
      color: Colors.blue,
    ),
    _OnboardingPage(
      icon: Icons.mic,
      title: '持续记录',
      description: '24小时环境录音\n自动转写和整理您说过的重要内容',
      color: Colors.orange,
    ),
    _OnboardingPage(
      icon: Icons.lightbulb,
      title: '智能助理',
      description: 'AI分析您的记录\n主动提醒待办事项，提供个性化建议',
      color: Colors.green,
    ),
    _OnboardingPage(
      icon: Icons.security,
      title: '隐私优先',
      description: '所有数据本地存储\n云端分析可完全关闭，您完全掌控自己的数据',
      color: Colors.purple,
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _requestPermissions();
    }
  }

  Future<void> _requestPermissions() async {
    final granted = await _permissionManager.requestAllPermissions(context);
    if (granted && mounted) {
      widget.onComplete();
    }
  }

  void _skip() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部快捷操作栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 快速开始按钮
                  TextButton.icon(
                    onPressed: _showQuickStartOptions,
                    icon: const Icon(Icons.flash_on, size: 18),
                    label: const Text('快速开始'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      backgroundColor: Colors.blue.withValues(alpha: 0.1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  // 跳过按钮
                  TextButton(
                    onPressed: _skip,
                    child: const Text('跳过引导'),
                  ),
                ],
              ),
            ),

            // 页面内容
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // 指示器
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index ? Colors.blue : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 下一步按钮
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: Colors.blue.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1 ? '开始使用' : '下一步',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 显示快速开始选项
  void _showQuickStartOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '快速开始',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '选择一种方式快速进入应用',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                _buildQuickStartOption(
                  icon: Icons.bolt,
                  title: '极速体验',
                  subtitle: '跳过所有设置，使用默认配置直接进入',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    _quickStartWithDefaults();
                  },
                ),
                const SizedBox(height: 12),
                _buildQuickStartOption(
                  icon: Icons.person_outline,
                  title: '商务用户',
                  subtitle: '预设会议、客户管理等商务场景优化',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    _quickStartWithBusinessProfile();
                  },
                ),
                const SizedBox(height: 12),
                _buildQuickStartOption(
                  icon: Icons.school_outlined,
                  title: '学生用户',
                  subtitle: '预设课程、学习笔记等学生场景优化',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    _quickStartWithStudentProfile();
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStartOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  // 极速体验 - 默认配置
  Future<void> _quickStartWithDefaults() async {
    // 只请求必要权限，不设置用户画像
    await _permissionManager.requestAllPermissions(context);
    if (mounted) {
      widget.onComplete();
    }
  }

  // 商务用户快速配置
  Future<void> _quickStartWithBusinessProfile() async {
    // 请求权限
    await _permissionManager.requestAllPermissions(context);
    // TODO: 保存商务用户预设配置
    if (mounted) {
      widget.onComplete();
    }
  }

  // 学生用户快速配置
  Future<void> _quickStartWithStudentProfile() async {
    // 请求权限
    await _permissionManager.requestAllPermissions(context);
    // TODO: 保存学生用户预设配置
    if (mounted) {
      widget.onComplete();
    }
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            page.icon,
            size: 120,
            color: page.color,
          ),
          const SizedBox(height: 48),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            page.description,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
