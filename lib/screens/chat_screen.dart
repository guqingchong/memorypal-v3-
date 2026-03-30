import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/recording.dart';
import '../services/database_service.dart';
import '../services/kimi_service.dart';
import '../services/whisper_service.dart';
import '../services/recording_service.dart';
import '../services/vector_search_service.dart';
import '../utils/permission_manager.dart';

/// AI对话界面 - 与助理对话、自然语言检索、智能问答
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _databaseService = DatabaseService();
  final _kimiService = KimiService();
  final _whisperService = WhisperService();
  final _vectorSearchService = VectorSearchService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _voiceInputPath;

  final _recordingService = RecordingService();

  // 快捷询问选项
  final List<String> _quickQuestions = [
    '我最近有什么待办？',
    '上周我记录了什么重要内容？',
    '我最近在忙什么项目？',
    '帮我找一下会议纪要',
  ];

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      isUser: false,
      content: '你好！我是你的MemoryPal智能助理。\n\n我可以帮你：\n• 查找过去的录音和笔记\n• 回答关于你记忆的问题\n• 提取待办事项\n• 分析你的习惯和偏好\n\n有什么可以帮你的吗？',
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        isUser: true,
        content: content,
        timestamp: DateTime.now(),
      ));
      _isProcessing = true;
    });

    _textController.clear();
    _scrollToBottom();

    // 分析用户意图并响应
    final response = await _processQuery(content);

    setState(() {
      _messages.add(ChatMessage(
        isUser: false,
        content: response,
        timestamp: DateTime.now(),
        isSearchResult: response.contains('📁') || response.contains('📝'),
      ));
      _isProcessing = false;
    });

    _scrollToBottom();
  }

  Future<String> _processQuery(String query) async {
    final lowerQuery = query.toLowerCase();

    // 1. 待办查询
    if (lowerQuery.contains('待办') || lowerQuery.contains('todo') || lowerQuery.contains('要做')) {
      return await _getTodosResponse();
    }

    // 2. 时间范围查询 (上周、昨天、今天等)
    if (lowerQuery.contains('上周') || lowerQuery.contains('最近') ||
        lowerQuery.contains('昨天') || lowerQuery.contains('今天') ||
        lowerQuery.contains('这几天')) {
      return await _getRecentContentResponse(query);
    }

    // 3. 特定人名查询
    if (lowerQuery.contains('李明') || lowerQuery.contains('王总') ||
        lowerQuery.contains('和') || lowerQuery.contains('聊')) {
      return await _searchByPersonOrTopic(query);
    }

    // 4. 文件/会议查询
    if (lowerQuery.contains('会议纪要') || lowerQuery.contains('ppt') ||
        lowerQuery.contains('文件') || lowerQuery.contains('文档')) {
      return await _searchFiles(query);
    }

    // 5. 项目/工作查询
    if (lowerQuery.contains('项目') || lowerQuery.contains('工作') ||
        lowerQuery.contains('忙什么')) {
      return await _getWorkSummary();
    }

    // 6. 使用AI回答复杂问题
    return await _askAI(query);
  }

  Future<String> _getTodosResponse() async {
    final todos = await _databaseService.getTodos(includeCompleted: false);

    if (todos.isEmpty) {
      return '你当前没有待办事项。需要我帮你从最近的录音中提取吗？';
    }

    final buffer = StringBuffer();
    buffer.writeln('📋 你的待办事项 (${todos.length}项)：\n');

    for (var i = 0; i < todos.take(5).length; i++) {
      final todo = todos[i];
      final priority = todo['priority'] as String? ?? 'medium';
      final priorityEmoji = priority == 'high' ? '🔴' : priority == 'medium' ? '🟡' : '🟢';
      buffer.writeln('$priorityEmoji ${todo['content']}');

      final deadline = todo['deadline'] as int?;
      if (deadline != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(deadline);
        final diff = date.difference(DateTime.now());
        if (diff.inDays >= 0) {
          buffer.writeln('   截止: ${date.month}/${date.day} (${diff.inDays}天后)');
        } else {
          buffer.writeln('   ⚠️ 已逾期 ${-diff.inDays} 天');
        }
      }
      buffer.writeln('');
    }

    if (todos.length > 5) {
      buffer.writeln('...还有 ${todos.length - 5} 项待办');
    }

    return buffer.toString();
  }

  Future<String> _getRecentContentResponse(String query) async {
    DateTime startDate;
    final now = DateTime.now();

    if (query.contains('今天')) {
      startDate = DateTime(now.year, now.month, now.day);
    } else if (query.contains('昨天')) {
      startDate = now.subtract(const Duration(days: 1));
    } else if (query.contains('上周') || query.contains('最近一周')) {
      startDate = now.subtract(const Duration(days: 7));
    } else {
      startDate = now.subtract(const Duration(days: 7)); // 默认最近一周
    }

    final recordings = await _databaseService.getRecordings(limit: 100);
    final notes = await _databaseService.getNotes(limit: 100);

    final recentRecordings = recordings.where((r) => r.startTime.isAfter(startDate)).toList();
    final recentNotes = notes.where((n) => n.createdAt.isAfter(startDate)).toList();

    if (recentRecordings.isEmpty && recentNotes.isEmpty) {
      return '这段时间内没有记录。开始录音或记笔记来记录你的生活吧！';
    }

    final buffer = StringBuffer();
    buffer.writeln('📊 ${query.contains('今天') ? '今天' : query.contains('昨天') ? '昨天' : '最近'}的记录概况：\n');
    buffer.writeln('🎙️ ${recentRecordings.length} 条录音');
    buffer.writeln('📝 ${recentNotes.length} 条笔记\n');

    if (recentRecordings.isNotEmpty) {
      buffer.writeln('🎙️ 最新录音：');
      for (final r in recentRecordings.take(3)) {
        buffer.writeln('• ${r.startTime.hour}:${r.startTime.minute.toString().padLeft(2, '0')} ${r.transcript?.substring(0, r.transcript!.length > 30 ? 30 : r.transcript!.length) ?? '无转写'}...');
      }
      buffer.writeln('');
    }

    if (recentNotes.isNotEmpty) {
      buffer.writeln('📝 最新笔记：');
      for (final n in recentNotes.take(3)) {
        buffer.writeln('• ${n.title}');
      }
    }

    return buffer.toString();
  }

  Future<String> _searchByPersonOrTopic(String query) async {
    // 使用语义搜索
    final result = await _vectorSearchService.semanticSearch(query, limit: 5);
    return _vectorSearchService.generateAnswer(query, result);
  }

  Future<String> _searchFiles(String query) async {
    final files = await _databaseService.getImportedFiles(limit: 50);

    if (files.isEmpty) {
      return '你还没有导入任何文件。可以在首页点击"导入文件"添加文档。';
    }

    final buffer = StringBuffer();
    buffer.writeln('📁 你的文件 (${files.length}个)：\n');

    for (final f in files.take(10)) {
      final fileName = f['file_name'] as String? ?? '未命名';
      final fileType = f['file_type'] as String? ?? '未知';
      final typeIcon = _getFileTypeIcon(fileType);
      buffer.writeln('$typeIcon $fileName');
    }

    if (files.length > 10) {
      buffer.writeln('\n...还有 ${files.length - 10} 个文件');
    }

    return buffer.toString();
  }

  String _getFileTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return '📕';
      case 'doc':
      case 'docx':
        return '📘';
      case 'ppt':
      case 'pptx':
        return '📊';
      case 'txt':
      case 'md':
        return '📝';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return '🖼️';
      default:
        return '📄';
    }
  }

  Future<String> _getWorkSummary() async {
    final recordings = await _databaseService.getRecordings(limit: 30);
    final notes = await _databaseService.getNotes(limit: 30);

    // 简单的关键词匹配分析
    final workKeywords = ['项目', '会议', '工作', '汇报', '方案', '客户', '需求'];
    int workMentions = 0;

    for (final r in recordings) {
      if (r.transcript != null && workKeywords.any((k) => r.transcript!.contains(k))) {
        workMentions++;
      }
    }

    for (final n in notes) {
      if (workKeywords.any((k) => n.content.contains(k) || n.title.contains(k))) {
        workMentions++;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('💼 工作情况概览\n');

    if (workMentions > 0) {
      buffer.writeln('最近你记录了 $workMentions 条工作相关内容');
      buffer.writeln('\n从记录中发现你可能在关注：');
      buffer.writeln('• 项目进展跟踪');
      buffer.writeln('• 会议讨论');
      buffer.writeln('• 工作汇报准备');
    } else {
      buffer.writeln('最近没有明显的工作相关记录。');
      buffer.writeln('\n提示：多录音记录工作想法，我可以帮你更好地管理。');
    }

    return buffer.toString();
  }

  Future<String> _askAI(String question) async {
    // 先尝试用Kimi API
    if (_kimiService.isAvailable) {
      // 获取相关上下文
      final recordings = await _databaseService.getRecordings(limit: 20);
      final notes = await _databaseService.getNotes(limit: 20);

      final context = <String>[];
      for (final r in recordings.take(10)) {
        if (r.transcript != null && r.transcript!.isNotEmpty) {
          context.add('[录音 ${r.startTime.month}/${r.startTime.day}] ${r.transcript}');
        }
      }
      for (final n in notes.take(5)) {
        context.add('[笔记 ${n.createdAt.month}/${n.createdAt.day}] ${n.title}: ${n.content.substring(0, n.content.length > 100 ? 100 : n.content.length)}');
      }

      final response = await _kimiService.askQuestion(question, context: context);
      if (response != null) {
        return response;
      }
    }

    // 离线模式：基于本地数据简单回答
    return _offlineAnswer(question);
  }

  String _offlineAnswer(String question) {
    final lower = question.toLowerCase();

    if (lower.contains('你好') || lower.contains('是谁')) {
      return '你好！我是MemoryPal，你的24小时智能助理。\n\n我可以帮你记录生活、整理思路、提醒待办。我的所有功能都可以离线使用，保护你的隐私。';
    }

    if (lower.contains('隐私') || lower.contains('安全')) {
      return '🔒 隐私保护说明\n\n• 所有数据存储在本地\n• 录音仅保存在你的设备上\n• AI分析优先使用本地模型\n• 云端分析可选且可关闭\n• 你可以随时导出或删除所有数据';
    }

    if (lower.contains('功能') || lower.contains('能做什么') || lower.contains('帮助')) {
      return '🤖 我可以帮你\n\n• 📱 24小时环境录音记录\n• 📝 语音/文字笔记\n• 🔍 自然语言搜索记忆\n• ⏰ 智能待办提醒\n• 💡 基于习惯的建议\n• 📊 每日记忆摘要\n\n试着问我："我最近有什么待办？" 或 "帮我找一下会议纪要"';
    }

    return '我理解你想了解 "$question"，但我的云端AI服务暂时不可用。\n\n你可以尝试：\n• 检查网络连接\n• 在设置中配置Kimi API密钥\n• 问我关于待办、最近记录等本地问题';
  }

  // 开始语音输入录音
  Future<void> _startVoiceInput() async {
    // 检查麦克风权限
    final hasPermission = await PermissionManager().checkMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能语音输入')),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });

    // 启动计时器
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _recordingSeconds++;
      });
    });

    // 开始录音（使用临时文件）
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _voiceInputPath = '${tempDir.path}/voice_input_$timestamp.m4a';

      await _recordingService.startRecordingForTranscription(_voiceInputPath!);
    } catch (e) {
      debugPrint('启动语音输入录音失败: $e');
      _stopVoiceInput();
    }
  }

  // 停止语音输入并进行转写
  Future<void> _stopVoiceInput() async {
    _recordingTimer?.cancel();

    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    // 停止录音
    await _recordingService.stopRecordingForTranscription();

    // 如果录音太短，放弃
    if (_recordingSeconds < 1) {
      _voiceInputPath = null;
      return;
    }

    // 显示转写中
    setState(() {
      _isTranscribing = true;
    });

    try {
      // 调用Whisper进行转写
      if (_voiceInputPath != null) {
        final result = await _whisperService.transcribe(_voiceInputPath!);

        if (result != null && result.text.isNotEmpty) {
          setState(() {
            _textController.text = result.text;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('未能识别语音，请重试')),
            );
          }
        }

        // 清理临时文件
        final file = File(_voiceInputPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _voiceInputPath = null;
      }
    } catch (e) {
      debugPrint('语音转写失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音转写失败，请检查网络或重试')),
        );
      }
    } finally {
      setState(() {
        _isTranscribing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.blue),
            SizedBox(width: 8),
            Text('与助理对话'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // TODO: 查看对话历史
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 快捷询问区域（仅在消息较少时显示）
          if (_messages.length <= 2)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '快捷询问',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickQuestions.map((q) => ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _sendMessage(q),
                    )).toList(),
                  ),
                ],
              ),
            ),

          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessageItem(_messages[index]),
            ),
          ),

          // 输入区域
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // 语音输入按钮
                  GestureDetector(
                    onTapDown: (_) => _startVoiceInput(),
                    onTapUp: (_) => _stopVoiceInput(),
                    onTapCancel: () => _stopVoiceInput(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: _isRecording ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 文本输入框
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: _isTranscribing
                            ? '正在识别语音...'
                            : _isRecording
                                ? '录音中 ${_recordingSeconds}s...'
                                : '输入文字或按住麦克风说话...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                      enabled: !_isProcessing && !_isTranscribing && !_isRecording,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 发送按钮
                  if (_isProcessing || _isTranscribing)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: () => _sendMessage(_textController.text),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? Colors.blue.shade100
                    : message.isSearchResult
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: message.isUser ? Colors.black87 : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

/// 聊天消息模型
class ChatMessage {
  final bool isUser;
  final String content;
  final DateTime timestamp;
  final bool isSearchResult;

  ChatMessage({
    required this.isUser,
    required this.content,
    required this.timestamp,
    this.isSearchResult = false,
  });
}
