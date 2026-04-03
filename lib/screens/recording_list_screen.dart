import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../services/database_service.dart';
import '../services/recording_service.dart';
import 'recording_detail_screen.dart';

/// 24小时录音列表页面 - 展示所有录音记录
class RecordingListScreen extends StatefulWidget {
  const RecordingListScreen({super.key});

  @override
  State<RecordingListScreen> createState() => _RecordingListScreenState();
}

class _RecordingListScreenState extends State<RecordingListScreen> {
  final _databaseService = DatabaseService();
  final _recordingService = RecordingService();
  List<Recording> _recordings = [];
  bool _isLoading = true;
  bool _isBackgroundRecording = false;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    _checkBackgroundRecordingStatus();
    _recordingService.backgroundRecordingState.listen(_onBackgroundRecordingStateChanged);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onBackgroundRecordingStateChanged(bool isRunning) {
    if (mounted) {
      setState(() {
        _isBackgroundRecording = isRunning;
      });
    }
  }

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

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    try {
      final recordings = await _databaseService.getRecordings(limit: 200);
      if (mounted) {
        setState(() {
          _recordings = recordings;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载录音列表失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载录音列表失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteRecording(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条录音吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && recording.id != null) {
      await _recordingService.deleteRecording(recording.id!);
      _loadRecordings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录音记录'),
        actions: [
          // 后台录音状态指示器
          if (_isBackgroundRecording)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '24h录音中',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
              ? _buildEmptyState()
              : _buildRecordingList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '还没有录音记录',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '开启24小时环境录音或手动录音',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // 返回首页启动录音
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.mic),
            label: const Text('去录音'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingList() {
    // 按日期分组
    final groupedRecordings = _groupRecordingsByDate();

    return RefreshIndicator(
      onRefresh: _loadRecordings,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedRecordings.length,
        itemBuilder: (context, index) {
          final group = groupedRecordings[index];
          return _buildDateGroup(group);
        },
      ),
    );
  }

  List<DateGroup> _groupRecordingsByDate() {
    final groups = <DateGroup>[];
    DateTime? currentDate;
    List<Recording> currentGroup = [];

    for (final recording in _recordings) {
      final date = DateTime(
        recording.startTime.year,
        recording.startTime.month,
        recording.startTime.day,
      );

      if (currentDate == null || currentDate != date) {
        if (currentGroup.isNotEmpty) {
          groups.add(DateGroup(currentDate!, currentGroup));
        }
        currentDate = date;
        currentGroup = [recording];
      } else {
        currentGroup.add(recording);
      }
    }

    if (currentGroup.isNotEmpty && currentDate != null) {
      groups.add(DateGroup(currentDate, currentGroup));
    }

    return groups;
  }

  Widget _buildDateGroup(DateGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDateHeader(group.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.recordings.length}条录音',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        // 录音列表
        ...group.recordings.map((r) => _buildRecordingCard(r)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRecordingCard(Recording recording) {
    final isVoiceNote = recording.isVoiceNote;
    final isBackgroundRecording = recording.source == 'background';
    final hasTranscript = recording.transcript != null && recording.transcript!.isNotEmpty;

    return Dismissible(
      key: Key('recording_${recording.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteRecording(recording),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecordingDetailScreen(recording: recording),
              ),
            ).then((_) => _loadRecordings());
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 录音类型图标
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isVoiceNote
                        ? Colors.orange.withOpacity(0.1)
                        : isBackgroundRecording
                            ? Colors.green.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isVoiceNote
                        ? Icons.mic
                        : isBackgroundRecording
                            ? Icons.timer
                            : Icons.graphic_eq,
                    color: isVoiceNote
                        ? Colors.orange
                        : isBackgroundRecording
                            ? Colors.green
                            : Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // 录音信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording.title ??
                            (isVoiceNote ? '语音笔记' : '录音 ${_formatTime(recording.startTime)}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (hasTranscript)
                        Text(
                          recording.transcript!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.3,
                          ),
                        )
                      else
                        Row(
                          children: [
                            Icon(Icons.pending, size: 12, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(
                              '等待转写',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(recording.startTime),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.timer_outlined, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(recording.durationSeconds),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          if (recording.locationName != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.location_on, size: 12, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                recording.locationName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 播放箭头
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return '今天';
    } else if (dateToCheck == yesterday) {
      return '昨天';
    } else {
      return '${date.month}月${date.day}日 ${['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1]}';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}秒';
    } else if (seconds < 3600) {
      return '${seconds ~/ 60}分${seconds % 60}秒';
    } else {
      return '${seconds ~/ 3600}时${(seconds % 3600) ~/ 60}分';
    }
  }
}

/// 日期分组数据类
class DateGroup {
  final DateTime date;
  final List<Recording> recordings;

  DateGroup(this.date, this.recordings);
}
