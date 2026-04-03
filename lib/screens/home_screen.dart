import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../models/note.dart';
import '../services/recording_service.dart';
import '../services/database_service.dart';
import '../utils/permission_manager.dart';
import '../services/file_import_service.dart';
import 'recording_list_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'text_note_editor_screen.dart';
import 'settings_screen.dart';
import 'recording_detail_screen.dart';
import '../services/wechat_import_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recordingService = RecordingService();

  int _currentIndex = 0;

  final _screens = const [
    _HomeContent(),
    RecordingListScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music), label: '录音'),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: '助理'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recordingService.dispose();
    super.dispose();
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  final _recordingService = RecordingService();
  final _databaseService = DatabaseService();

  List<Recording> _recentRecordings = [];
  List<Note> _recentNotes = [];
  bool _isRecording = false;
  bool _isBackgroundRecording = false;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _recordingService.recordingState.listen(_onRecordingStateChanged);
    _recordingService.backgroundRecordingState.listen(_onBackgroundRecordingStateChanged);
    _checkBackgroundRecordingStatus();
  }

  void _onRecordingStateChanged(RecordingState state) {
    if (mounted) {
      setState(() {
        if (state is RecordingInProgress) {
          _isRecording = true;
          _recordingSeconds = state.seconds;
        } else if (state is RecordingCompleted || state is RecordingIdle) {
          _isRecording = false;
          _recordingSeconds = 0;
          _loadData();
        }
      });
    }
  }

  void _onBackgroundRecordingStateChanged(bool isRunning) {
    if (mounted) {
      setState(() {
        _isBackgroundRecording = isRunning;
      });
    }
  }

  // 检查后台录音状态
  Future<void> _checkBackgroundRecordingStatus() async {
    try {
      final isRunning = await _recordingService.isBackgroundRecordingRunning();
      if (mounted) {
        setState(() {
          _isBackgroundRecording = isRunning;
        });
      }
    } catch (e) {
      debugPrint('检查后台录音状态失败: $e');
    }
  }

  Future<void> _loadData() async {
    final recordings = await _databaseService.getRecordings(limit: 5);
    final notes = await _databaseService.getNotes(limit: 5);
    if (mounted) {
      setState(() {
        _recentRecordings = recordings;
        _recentNotes = notes;
      });
    }
  }

  Future<void> _toggleRecording() async {
    // 先申请麦克风权限
    final hasPermission = await PermissionManager().checkMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
      return;
    }

    if (_isRecording) {
      // 停止录音
      final result = await _recordingService.stopRecording();
      if (result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录音已保存')),
        );
      }
    } else {
      // 开始录音
      final result = await _recordingService.startRecording(isVoiceNote: false);
      if (result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开始录音...'), duration: Duration(seconds: 1)),
        );
      } else if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('启动录音失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importFile() async {
    final result = await FileImportService().importFile();
    if (result != null && result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        _loadData();
      }
    } else if (result != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.psychology, color: Colors.blue, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'MemoryPal',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.grey),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRecordingButton(),
            const SizedBox(height: 24),
            _buildQuickActions(),
            const SizedBox(height: 24),
            _buildAssistantMessages(),
            const SizedBox(height: 24),
            _buildTodaySection(),
          ],
        ),
      ),
    );
  }

  // 开始语音笔记录音
  Future<void> _startVoiceNoteRecording() async {
    final hasPermission = await PermissionManager().checkMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
      return;
    }

    // 启动录音（标记为语音笔记）
    final result = await _recordingService.startRecording(isVoiceNote: true);
    if (!result) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('启动录音失败')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音笔记录音中...'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  // 显示录音模式选择（长按菜单）
  void _showRecordingModeSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择录音模式',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // 普通录音选项（仅在未进行普通录音时显示）
            if (!_isRecording)
              ListTile(
                leading: const Icon(Icons.record_voice_over, color: Colors.blue),
                title: const Text('普通录音'),
                subtitle: const Text('常规录音，保存到录音列表'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleRecording();
                },
              ),
            // 停止普通录音选项
            if (_isRecording)
              ListTile(
                leading: const Icon(Icons.stop, color: Colors.red),
                title: const Text('停止普通录音'),
                subtitle: Text('已录音 $_recordingSeconds 秒'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleRecording();
                },
              ),
            const Divider(),
            // 24小时环境录音选项
            if (!_isBackgroundRecording)
              ListTile(
                leading: const Icon(Icons.settings_voice, color: Colors.green),
                title: const Text('启动24小时环境录音'),
                subtitle: const Text('后台服务，智能检测人声'),
                onTap: () {
                  Navigator.pop(context);
                  _showBackgroundRecordingDialog();
                },
              ),
            // 停止24小时环境录音选项
            if (_isBackgroundRecording)
              ListTile(
                leading: const Icon(Icons.stop_circle, color: Colors.orange),
                title: const Text('停止24小时环境录音'),
                subtitle: const Text('后台录音运行中'),
                onTap: () {
                  Navigator.pop(context);
                  _stopBackgroundRecording();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 停止后台录音
  Future<void> _stopBackgroundRecording() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停止24小时环境录音'),
        content: const Text('确定要停止后台环境录音吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('停止'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _recordingService.stopBackgroundRecording();
      setState(() {
        _isBackgroundRecording = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result ? '后台录音已停止' : '停止后台录音失败'),
            backgroundColor: result ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  // 显示后台录音设置对话框
  void _showBackgroundRecordingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('24小时环境录音'),
        content: const Text(
          '启动后台录音服务后，应用将在后台持续监听。\n\n'
          '注意：\n'
          '• 会显示持续通知\n'
          '• 仅在检测到人声时保存录音\n'
          '• 超过30天的录音将自动删除\n'
          '• 可能增加电量消耗',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startBackgroundRecording();
            },
            child: const Text('启动'),
          ),
        ],
      ),
    );
  }

  // 启动后台录音
  Future<void> _startBackgroundRecording() async {
    final hasPermission = await PermissionManager().checkMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限')),
        );
      }
      return;
    }

    // 显示启动中提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在启动24小时环境录音...')),
      );
    }

    final result = await _recordingService.startBackgroundRecording();
    if (result) {
      // 更新UI状态
      setState(() {
        _isBackgroundRecording = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('24小时环境录音已启动，将在后台持续监听'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      setState(() {
        _isBackgroundRecording = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('启动后台录音失败，请检查权限设置'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildRecordingButton() {
    // 确定当前状态
    final bool isAnyRecording = _isRecording || _isBackgroundRecording;
    final String statusText;
    final String subText;
    final IconData icon;

    if (_isRecording) {
      statusText = '普通录音中 ${_formatDuration(_recordingSeconds)}';
      subText = '点击停止录音';
      icon = Icons.stop_rounded;
    } else if (_isBackgroundRecording) {
      statusText = '24小时环境录音运行中';
      subText = '后台智能监听中...';
      icon = Icons.graphic_eq;
    } else {
      statusText = '点击开始录音';
      subText = '长按选择模式';
      icon = Icons.mic_rounded;
    }

    return GestureDetector(
      onTap: _isBackgroundRecording ? null : _toggleRecording,
      onLongPress: _showRecordingModeSelector,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 140,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isAnyRecording
                ? (_isBackgroundRecording
                    ? [Colors.green.shade400, Colors.green.shade700]
                    : [Colors.red.shade400, Colors.red.shade700])
                : [Colors.blue.shade400, Colors.blue.shade700],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (isAnyRecording
                      ? (_isBackgroundRecording ? Colors.green : Colors.red)
                      : Colors.blue)
                  .withOpacity(0.4),
              blurRadius: isAnyRecording ? 30 : 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 脉冲动画（录音中）
            if (isAnyRecording)
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 32,
                        color: _isBackgroundRecording
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              subText,
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.edit,
            title: '文字笔记',
            color: Colors.green,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TextNoteEditorScreen()),
              ).then((_) => _loadData());
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionCard(
            icon: Icons.mic,
            title: '语音笔记',
            color: Colors.orange,
            onTap: _startVoiceNoteRecording,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionCard(
            icon: Icons.upload_file,
            title: '导入文件',
            color: Colors.purple,
            onTap: _importFile,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionCard(
            icon: Icons.chat,
            title: '微信导入',
            color: Colors.green.shade600,
            onTap: _showWeChatImport,
          ),
        ),
      ],
    );
  }

  void _showWeChatImport() {
    WeChatImportService().showManualImportGuide(context);
  }

  Widget _buildAssistantMessages() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _databaseService.getTodos(includeCompleted: false),
      builder: (context, todoSnapshot) {
        final pendingTodos = todoSnapshot.data ?? [];
        final todayTodos = pendingTodos.where((t) {
          final deadline = t['deadline'] as int?;
          if (deadline == null) return false;
          final date = DateTime.fromMillisecondsSinceEpoch(deadline);
          final now = DateTime.now();
          return date.year == now.year && date.month == now.month && date.day == now.day;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '今日助理消息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (todayTodos.isNotEmpty) ...[
                      _buildMessageItem(
                        Icons.check_circle_rounded,
                        '你有 ${todayTodos.length} 个待办事项今天到期',
                        Colors.orange.shade400,
                      ),
                      Divider(color: Colors.grey.shade100, height: 24),
                    ],
                    if (pendingTodos.isNotEmpty) ...[
                      _buildMessageItem(
                        Icons.task_alt_rounded,
                        '共有 ${pendingTodos.length} 个待办事项等待处理',
                        Colors.blue.shade400,
                      ),
                      Divider(color: Colors.grey.shade100, height: 24),
                    ],
                    if (_recentRecordings.isEmpty && _recentNotes.isEmpty)
                      _buildMessageItem(
                        Icons.wb_sunny_rounded,
                        '早安！今天还没有记录，开始记录你的生活吧',
                        Colors.orange.shade400,
                      )
                    else
                      _buildMessageItem(
                        Icons.lightbulb_rounded,
                        '今天已记录 ${_recentRecordings.length} 条录音、${_recentNotes.length} 条笔记',
                        Colors.green.shade400,
                      ),
                    if (todayTodos.isEmpty && pendingTodos.isEmpty && _recentRecordings.isEmpty && _recentNotes.isEmpty) ...[
                      Divider(color: Colors.grey.shade100, height: 24),
                      _buildMessageItem(
                        Icons.psychology_rounded,
                        '试试对我说："我最近有什么待办？"',
                        Colors.purple.shade400,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessageItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '今天',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            TextButton(
              onPressed: () {
                // TODO: 查看全部
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recentRecordings.map((r) => _buildRecordingItem(r)),
        ..._recentNotes.map((n) => _buildNoteItem(n)),
        if (_recentRecordings.isEmpty && _recentNotes.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    '今天还没有记录',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingItem(Recording recording) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.blue, size: 22),
        ),
        title: Text(
          recording.title ?? '录音 ${_formatTime(recording.startTime)}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          recording.transcript?.isNotEmpty == true
              ? (recording.transcript!.length > 50
                  ? '${recording.transcript!.substring(0, 50)}...'
                  : recording.transcript!)
              : '暂无转写',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${recording.durationSeconds}s',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecordingDetailScreen(recording: recording),
            ),
          ).then((_) => _loadData());
        },
      ),
    );
  }

  Widget _buildNoteItem(Note note) {
    final isVoiceNote = note.type == NoteType.voice;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isVoiceNote ? Colors.orange : Colors.green).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isVoiceNote ? Icons.mic_rounded : Icons.notes_rounded,
            color: isVoiceNote ? Colors.orange : Colors.green,
            size: 22,
          ),
        ),
        title: Text(
          note.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          note.content.length > 50 ? '${note.content.substring(0, 50)}...' : note.content,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        trailing: Text(
          _formatTime(note.createdAt),
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
