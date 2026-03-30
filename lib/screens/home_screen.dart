import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../models/note.dart';
import '../services/recording_service.dart';
import '../services/database_service.dart';
import '../services/note_service.dart';
import 'note_list_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'text_note_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recordingService = RecordingService();
  final _databaseService = DatabaseService();

  int _currentIndex = 0;

  final _screens = const [
    _HomeContent(),
    NoteListScreen(),
    SearchScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '笔记'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
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
  final _noteService = NoteService();

  List<Recording> _recentRecordings = [];
  List<Note> _recentNotes = [];
  bool _isRecording = false;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _recordingService.recordingState.listen(_onRecordingStateChanged);
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
    if (_isRecording) {
      await _recordingService.stopRecording();
    } else {
      await _recordingService.startRecording();
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
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.blue),
            SizedBox(width: 8),
            Text('MemoryPal', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: 打开设置
            },
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

  Widget _buildRecordingButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      onLongPress: () {
        // TODO: 显示录音选项（语音笔记/环境录音）
      },
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: _isRecording ? Colors.red.shade50 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isRecording ? Colors.red : Colors.blue,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRecording ? Icons.stop_circle : Icons.mic,
              size: 48,
              color: _isRecording ? Colors.red : Colors.blue,
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording ? '录音中 ${_formatDuration(_recordingSeconds)}' : '点击开始录音',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isRecording ? Colors.red : Colors.blue,
              ),
            ),
            if (!_isRecording)
              const Text(
                '长按选择模式',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.mic, // 语音笔记图标
            title: '语音笔记',
            color: Colors.orange,
            onTap: () {
              // TODO: 打开语音笔记录制
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.upload_file,
            title: '导入文件',
            color: Colors.purple,
            onTap: () {
              // TODO: 打开文件导入
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssistantMessages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '今日助理消息',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMessageItem(Icons.lightbulb, '记得今晚准备明天的汇报', Colors.yellow),
                const Divider(),
                _buildMessageItem(Icons.check_circle, '你有2个待办事项今天到期', Colors.green),
                const Divider(),
                _buildMessageItem(Icons.wb_sunny, '早安！今天有3个会议', Colors.orange),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // TODO: 查看全部
              },
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._recentRecordings.map((r) => _buildRecordingItem(r)),
        ..._recentNotes.map((n) => _buildNoteItem(n)),
        if (_recentRecordings.isEmpty && _recentNotes.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('今天还没有记录', style: TextStyle(color: Colors.grey)),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingItem(Recording recording) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.mic, color: Colors.blue),
        title: Text('录音 ${_formatTime(recording.startTime)}'),
        subtitle: Text(recording.transcript ?? '暂无转写'),
        trailing: Text('${recording.durationSeconds}s'),
      ),
    );
  }

  Widget _buildNoteItem(Note note) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          note.type == NoteType.voice ? Icons.mic : Icons.note,
          color: note.type == NoteType.voice ? Colors.orange : Colors.green,
        ),
        title: Text(note.title),
        subtitle: Text(
          note.content.length > 50 ? '${note.content.substring(0, 50)}...' : note.content,
        ),
        trailing: Text(_formatTime(note.createdAt)),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
