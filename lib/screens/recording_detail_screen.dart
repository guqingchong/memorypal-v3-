import 'dart:async';
import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../services/database_service.dart';
import '../services/transcription_service.dart';

/// 录音详情/播放页面
///
/// 功能：
/// 1. 播放录音
/// 2. 显示转写文本
/// 3. 从转写文本选中内容快速创建待办
/// 4. 显示录音元数据（时间、地点、标签）
class RecordingDetailScreen extends StatefulWidget {
  final Recording recording;

  const RecordingDetailScreen({
    super.key,
    required this.recording,
  });

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  final _databaseService = DatabaseService();
  final _transcriptionService = TranscriptionService();

  bool _isPlaying = false;
  double _currentPosition = 0;
  double _duration = 0;
  Timer? _progressTimer;

  // 转写文本选择相关
  TextEditingController? _textSelectionController;
  String? _selectedText;

  // 自动提取的待办
  List<ExtractedTodo> _extractedTodos = [];
  bool _isExtractingTodos = false;
  bool _showExtractedTodos = false;

  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<int> _searchMatchIndices = [];  // 匹配位置的索引
  int _currentMatchIndex = -1;
  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _duration = widget.recording.durationSeconds.toDouble();
    // 如果有转写内容，自动提取待办
    if (widget.recording.transcript?.isNotEmpty == true &&
        !widget.recording.transcript!.contains('[离线模式]')) {
      _extractTodosFromTranscript();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _textSelectionController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _startProgressTimer();
      } else {
        _progressTimer?.cancel();
      }
    });
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_currentPosition < _duration) {
        setState(() {
          _currentPosition += 0.1;
        });
      } else {
        setState(() {
          _isPlaying = false;
          _currentPosition = 0;
        });
        _progressTimer?.cancel();
      }
    });
  }

  void _seek(double position) {
    setState(() {
      _currentPosition = position.clamp(0, _duration);
    });
  }

  // 显示创建待办对话框
  void _showCreateTodoDialog({String? initialContent}) {
    final contentController = TextEditingController(text: initialContent ?? '');
    String priority = 'medium';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.task_alt, color: Colors.blue),
              SizedBox(width: 8),
              Text('创建待办'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: contentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '待办内容...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('优先级:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildPriorityChip('高', 'high', priority, (p) {
                    setState(() => priority = p);
                  }),
                  const SizedBox(width: 8),
                  _buildPriorityChip('中', 'medium', priority, (p) {
                    setState(() => priority = p);
                  }),
                  const SizedBox(width: 8),
                  _buildPriorityChip('低', 'low', priority, (p) {
                    setState(() => priority = p);
                  }),
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
                if (contentController.text.trim().isEmpty) return;

                await _createTodo(
                  content: contentController.text.trim(),
                  priority: priority,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('待办已创建')),
                  );
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityChip(
    String label,
    String value,
    String currentValue,
    Function(String) onSelect,
  ) {
    final isSelected = value == currentValue;
    Color color;
    switch (value) {
      case 'high':
        color = Colors.red;
        break;
      case 'medium':
        color = Colors.orange;
        break;
      case 'low':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withOpacity(0.2),
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(color: isSelected ? color : Colors.black87),
      onSelected: (_) => onSelect(value),
    );
  }

  Future<void> _createTodo({
    required String content,
    String priority = 'medium',
  }) async {
    await _databaseService.insertTodo({
      'content': content,
      'priority': priority,
      'source_type': 'recording',
      'source_id': widget.recording.id,
      'is_completed': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // 从转写文本中选择内容
  void _showSelectionMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.task_alt, color: Colors.blue),
              title: const Text('创建待办'),
              subtitle: Text(
                '从选中内容: "${_selectedText?.substring(0, _selectedText!.length > 20 ? 20 : _selectedText!.length)}${_selectedText!.length > 20 ? '...' : ''}"',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showCreateTodoDialog(initialContent: _selectedText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.grey),
              title: const Text('复制选中内容'),
              onTap: () {
                Navigator.pop(context);
                // 复制到剪贴板
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 请求云端转写
  Future<void> _requestCloudTranscription() async {
    if (widget.recording.filePath.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在转写...'),
          ],
        ),
      ),
    );

    final result = await _transcriptionService.transcribe(
      widget.recording.filePath,
      recordingMeta: widget.recording,
    );

    if (mounted) {
      Navigator.pop(context);

      if (result != null) {
        // 更新录音的转写结果
        final updatedRecording = widget.recording.copyWith(
          transcript: result.text,
          tags: result.tags,
        );
        await _databaseService.updateRecording(updatedRecording);

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('转写完成')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('转写失败，请检查网络连接'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatDateTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // 从转写文本提取待办
  Future<void> _extractTodosFromTranscript() async {
    if (widget.recording.transcript?.isEmpty ?? true) return;

    setState(() {
      _isExtractingTodos = true;
    });

    final todos = await _transcriptionService.extractTodosFromTranscript(
      widget.recording.transcript!,
    );

    if (mounted) {
      setState(() {
        _extractedTodos = todos;
        _isExtractingTodos = false;
        _showExtractedTodos = todos.isNotEmpty;
      });
    }
  }

  // 搜索转写文本
  void _searchInTranscript(String query) {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchMatchIndices = [];
        _currentMatchIndex = -1;
      });
      return;
    }

    final transcript = widget.recording.transcript;
    if (transcript == null || transcript.isEmpty) return;

    final matches = <int>[];
    int index = 0;

    // 找到所有匹配位置
    while (true) {
      index = transcript.toLowerCase().indexOf(query.toLowerCase(), index);
      if (index == -1) break;
      matches.add(index);
      index += query.length;
    }

    setState(() {
      _isSearching = true;
      _lastSearchQuery = query;
      _searchMatchIndices = matches;
      _currentMatchIndex = matches.isNotEmpty ? 0 : -1;
    });

    // 如果有匹配，滚动到第一个匹配位置
    if (matches.isNotEmpty) {
      _scrollToMatch(matches.first);
    }
  }

  // 跳转到下一个匹配
  void _nextMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatchIndices.length;
    });
    _scrollToMatch(_searchMatchIndices[_currentMatchIndex]);
  }

  // 跳转到上一个匹配
  void _previousMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _searchMatchIndices.length) % _searchMatchIndices.length;
    });
    _scrollToMatch(_searchMatchIndices[_currentMatchIndex]);
  }

  // 滚动到匹配位置
  void _scrollToMatch(int position) {
    // 估算时间戳并跳转（简化版）
    final transcript = widget.recording.transcript;
    if (transcript == null || transcript.isEmpty) return;

    // 根据字符位置估算时间
    final ratio = position / transcript.length;
    final estimatedTime = ratio * _duration;
    _seek(estimatedTime);
  }

  // 清除搜索
  void _clearSearch() {
    setState(() {
      _isSearching = false;
      _searchMatchIndices = [];
      _currentMatchIndex = -1;
      _lastSearchQuery = '';
    });
    _searchController.clear();
  }

  // 批量添加提取的待办
  Future<void> _addExtractedTodos() async {
    final selectedTodos = _extractedTodos.where((t) => t.isSelected).toList();
    if (selectedTodos.isEmpty) return;

    for (final todo in selectedTodos) {
      await _createTodo(
        content: todo.content,
        priority: todo.priority,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${selectedTodos.length} 个待办')),
      );
      setState(() {
        _showExtractedTodos = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.recording;
    final hasTranscript = recording.transcript != null && recording.transcript!.isNotEmpty;
    final isOfflineTranscript = recording.transcript?.contains('[离线模式]') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(recording.title ?? '录音详情'),
        actions: [
          // 快速创建待办按钮
          IconButton(
            icon: const Icon(Icons.task_alt),
            tooltip: '创建待办',
            onPressed: () => _showCreateTodoDialog(),
          ),
          // 更多选项
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'transcribe':
                  await _requestCloudTranscription();
                  break;
                case 'delete':
                  _confirmDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (isOfflineTranscript || !hasTranscript)
                const PopupMenuItem(
                  value: 'transcribe',
                  child: Row(
                    children: [
                      Icon(Icons.transcribe, size: 20),
                      SizedBox(width: 8),
                      Text('云端转写'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('删除', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 播放器控制区
          _buildPlayerControls(),

          const Divider(),

          // 信息区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 录音元数据
                  _buildMetadataCard(recording),

                  const SizedBox(height: 16),

                  // 标签
                  if (recording.tags.isNotEmpty) ...[
                    _buildTagsSection(recording.tags),
                    const SizedBox(height: 16),
                  ],

                  // AI提取的待办事项
                  if (hasTranscript && !isOfflineTranscript) ...[
                    _buildExtractedTodosSection(),
                    const SizedBox(height: 16),
                  ],

                  // 转写文本
                  _buildTranscriptSection(recording, hasTranscript, isOfflineTranscript),
                ],
              ),
            ),
          ),

          // 底部快捷操作栏
          _buildBottomActionBar(hasTranscript),
        ],
      ),
    );
  }

  Widget _buildPlayerControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 进度条
          Slider(
            value: _currentPosition,
            max: _duration > 0 ? _duration : 1,
            onChanged: _seek,
          ),

          // 时间显示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_currentPosition)),
                Text(_formatDuration(_duration)),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 播放控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, size: 36),
                onPressed: () => _seek(_currentPosition - 10),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.forward_10, size: 36),
                onPressed: () => _seek(_currentPosition + 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(Recording recording) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '录音信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.access_time, '时间', _formatDateTime(recording.startTime)),
            if (recording.locationName != null)
              _buildInfoRow(Icons.location_on, '地点', recording.locationName!),
            _buildInfoRow(Icons.timer, '时长', '${recording.durationSeconds}秒'),
            if (recording.isVoiceNote)
              _buildInfoRow(Icons.note_alt, '类型', '语音笔记'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection(List<String> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '识别标签',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            return Chip(
              label: Text(tag),
              backgroundColor: Colors.blue.shade50,
              labelStyle: const TextStyle(color: Colors.blue),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildExtractedTodosSection() {
    if (_isExtractingTodos) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('AI正在分析待办事项...'),
            ],
          ),
        ),
      );
    }

    if (_extractedTodos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text('未识别到待办事项'),
              ),
              TextButton(
                onPressed: _extractTodosFromTranscript,
                child: Text('重新提取'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_showExtractedTodos) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_fix_high, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      '识别到 ${_extractedTodos.length} 个待办',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _showExtractedTodos = false;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._extractedTodos.asMap().entries.map((entry) {
              final index = entry.key;
              final todo = entry.value;
              return _buildExtractedTodoItem(todo, index);
            }),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addExtractedTodos,
                    icon: Icon(Icons.add_task),
                    label: Text('添加选中的待办'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedTodoItem(ExtractedTodo todo, int index) {
    Color priorityColor;
    switch (todo.priority) {
      case 'high':
        priorityColor = Colors.red;
        break;
      case 'medium':
        priorityColor = Colors.orange;
        break;
      case 'low':
        priorityColor = Colors.green;
        break;
      default:
        priorityColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: todo.isSelected,
            onChanged: (value) {
              setState(() {
                todo.isSelected = value ?? true;
              });
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todo.content,
                  style: TextStyle(
                    decoration: todo.isSelected ? null : TextDecoration.lineThrough,
                    color: todo.isSelected ? Colors.black87 : Colors.grey,
                  ),
                ),
                if (todo.context != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '原文: ${todo.context}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getPriorityText(todo.priority),
                        style: TextStyle(
                          fontSize: 11,
                          color: priorityColor,
                        ),
                      ),
                    ),
                    if (todo.type != 'task') ...[
                      const SizedBox(width: 8),
                      Text(
                        _getTypeText(todo.type),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getPriorityText(String priority) {
    switch (priority) {
      case 'high':
        return '高优先级';
      case 'medium':
        return '中优先级';
      case 'low':
        return '低优先级';
      default:
        return '普通';
    }
  }

  String _getTypeText(String type) {
    switch (type) {
      case 'meeting':
        return '会议';
      case 'reminder':
        return '提醒';
      case 'deadline':
        return '截止日期';
      default:
        return '任务';
    }
  }

  Widget _buildTranscriptSection(
    Recording recording,
    bool hasTranscript,
    bool isOfflineTranscript,
  ) {
    if (!hasTranscript) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.transcribe, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text('暂无转写内容'),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _requestCloudTranscription,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('开始转写'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '转写内容',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                // 搜索按钮
                IconButton(
                  icon: Icon(
                    _isSearching ? Icons.close : Icons.search,
                    size: 20,
                    color: _isSearching ? Colors.red : Colors.blue,
                  ),
                  onPressed: () {
                    if (_isSearching) {
                      _clearSearch();
                    } else {
                      setState(() {
                        _isSearching = true;
                      });
                    }
                  },
                ),
                if (isOfflineTranscript)
                  TextButton.icon(
                    onPressed: _requestCloudTranscription,
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: const Text('云端转写'),
                  ),
              ],
            ),
          ],
        ),

        // 搜索框
        if (_isSearching) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索转写内容...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _clearSearch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: _searchInTranscript,
          ),
          // 搜索结果导航
          if (_searchMatchIndices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(
                    '${_currentMatchIndex + 1} / ${_searchMatchIndices.length}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: _previousMatch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 20),
                    onPressed: _nextMatch,
                  ),
                ],
              ),
            ),
        ],

        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _isSearching && _searchMatchIndices.isNotEmpty
                ? _buildHighlightedText(recording.transcript!, _lastSearchQuery)
                : SelectableText(
                    recording.transcript!,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                    onSelectionChanged: (selection, cause) {
                      if (!selection.isCollapsed) {
                        final text = recording.transcript!;
                        if (selection.start >= 0 && selection.end <= text.length) {
                          _selectedText = text.substring(selection.start, selection.end);
                        }
                      }
                    },
                  ),
          ),
        ),
      ],
    );
  }

  // 构建高亮显示的文本
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 15, height: 1.6));
    }

    final spans = <TextSpan>[];
    int start = 0;
    int index = 0;

    while (true) {
      index = text.toLowerCase().indexOf(query.toLowerCase(), start);
      if (index == -1) break;

      // 添加普通文本
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: const TextStyle(fontSize: 15, height: 1.6),
        ));
      }

      // 添加高亮文本
      final isCurrentMatch = _searchMatchIndices.isNotEmpty &&
          _searchMatchIndices[_currentMatchIndex] == index;
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          backgroundColor: isCurrentMatch ? Colors.orange : Colors.yellow,
          fontWeight: isCurrentMatch ? FontWeight.bold : FontWeight.normal,
        ),
      ));

      start = index + query.length;
    }

    // 添加剩余文本
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: const TextStyle(fontSize: 15, height: 1.6),
      ));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: spans,
      ),
    );
  }

  Widget _buildBottomActionBar(bool hasTranscript) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showCreateTodoDialog(),
                icon: const Icon(Icons.task_alt),
                label: const Text('创建待办'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (hasTranscript) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // 复制转写内容
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('转写内容已复制')),
                    );
                  },
                  icon: const Icon(Icons.content_copy),
                  label: const Text('复制内容'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除录音'),
        content: const Text('确定要删除这条录音吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (widget.recording.id != null) {
                await _databaseService.deleteRecording(widget.recording.id!);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('录音已删除')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
