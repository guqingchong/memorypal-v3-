import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/whisper_service.dart';
import '../services/recording_service.dart';
import '../services/agent_service.dart';
import '../services/second_brain_orchestrator.dart';
import '../utils/permission_manager.dart';
import '../models/user_profile.dart';

/// AI对话界面 - 与助理对话、自然语言检索、智能问答
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _databaseService = DatabaseService();
  final _whisperService = WhisperService();
  final _agentService = AgentService();
  final _secondBrain = SecondBrainOrchestrator();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  // 第二大脑消息流订阅
  StreamSubscription? _orchestratorSubscription;

  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _voiceInputPath;

  final _recordingService = RecordingService();

  // 用户画像
  UserProfile? _userProfile;

  // 快捷询问选项 - 更自然的对话引导
  List<String> get _quickQuestions {
    final questions = <String>[];

    // 根据用户画像个性化快捷问题
    if (_userProfile?.occupation != null) {
      questions.add('最近工作有什么进展？');
    }
    if (_userProfile?.shortTermGoals != null) {
      questions.add('我的目标完成得怎么样了？');
    }

    questions.addAll([
      '总结一下我最近的状态',
      '根据我的习惯，给我一些建议',
      '我今天有什么安排吗？',
      '帮我分析最近的思考模式',
    ]);

    return questions.take(4).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadChatHistory();
    _setupAgentCallbacks();
    _initializeSecondBrain();
  }

  // 初始化第二大脑系统
  Future<void> _initializeSecondBrain() async {
    await _secondBrain.initialize();

    // 订阅第二大脑的消息流
    _orchestratorSubscription = _secondBrain.messageStream.listen((message) {
      switch (message.type) {
        case MessageType.welcome:
          _addAssistantMessage(message.content);
          break;
        case MessageType.proactive:
          _addAssistantMessage(
            message.content,
            isProactive: true,
          );
          break;
        default:
          break;
      }
    });
  }

  // 添加助理消息（支持主动消息标识）
  void _addAssistantMessage(String content, {bool isProactive = false}) {
    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(
        isUser: false,
        content: content,
        timestamp: DateTime.now(),
        isProactive: isProactive,
      ));
    });

    _scrollToBottom();

    // 保存到数据库
    _databaseService.insertChatMessage({
      'is_user': 0,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_search_result': 0,
      'is_proactive': isProactive ? 1 : 0,
    });
  }

  // 设置智能体回调
  void _setupAgentCallbacks() {
    _agentService.onPlayRecording = (path) {
      // 使用Navigator跳转到播放页面
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在打开录音播放...')),
        );
      }
    };

    _agentService.onStartRecording = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开始录音...')),
        );
      }
    };

    _agentService.onShowTodoNotification = (content) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(content), duration: const Duration(seconds: 2)),
        );
      }
    };
  }

  // 加载对话历史
  Future<void> _loadChatHistory() async {
    try {
      final messages = await _databaseService.getChatMessages(limit: 100);
      if (messages.isNotEmpty) {
        setState(() {
          _messages.clear();
          for (final m in messages) {
            _messages.add(ChatMessage(
              isUser: (m['is_user'] as int) == 1,
              content: m['content'] as String,
              timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
              isSearchResult: (m['is_search_result'] as int? ?? 0) == 1,
            ));
          }
        });
      } else {
        _addWelcomeMessage();
      }
    } catch (e) {
      debugPrint('加载对话历史失败: $e');
      _addWelcomeMessage();
    }
  }

  // 加载用户画像
  Future<void> _loadUserProfile() async {
    try {
      final profile = await _databaseService.getUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
        });
      }
    } catch (e) {
      debugPrint('加载用户画像失败: $e');
    }
  }

  void _addWelcomeMessage() {
    String welcomeText;

    if (_userProfile != null) {
      final name = _userProfile!.name ?? '';
      final occupation = _userProfile!.occupation;
      final interests = _userProfile!.interests.take(2).toList();

      final buffer = StringBuffer();
      buffer.write('你好${name.isNotEmpty ? name : ''}！');
      buffer.write('我是你的MemoryPal智能助理。\n\n');

      if (occupation != null && interests.isNotEmpty) {
        buffer.write('作为$occupation，你对${interests.join('、')}充满热情。');
        buffer.write('我会基于这些了解为你提供个性化帮助。\n\n');
      } else if (occupation != null) {
        buffer.write('我了解你的职业背景，可以针对性地为你服务。\n\n');
      } else if (interests.isNotEmpty) {
        buffer.write('我知道你对${interests.join('、')}感兴趣，');
        buffer.write('会据此给出相关建议。\n\n');
      }

      buffer.write('我可以：\n');
      buffer.write('💬 与你自由对话，基于你的画像提供建议\n');
      buffer.write('📝 记录和分析你的生活与思考\n');
      buffer.write('🎯 帮你追踪目标和习惯养成\n');
      buffer.write('💡 主动发现你关心的话题\n\n');
      buffer.write('想聊点什么？比如：\n');
      buffer.write('"根据我的习惯给我一些建议"\n');
      buffer.write('"分析一下我最近的状态"');

      welcomeText = buffer.toString();
    } else {
      welcomeText = '你好！我是你的MemoryPal智能助理。\n\n'
          '我可以：\n'
          '💬 与你自由对话，回答各种问题\n'
          '📝 帮你记录和整理记忆\n'
          '🎯 提取待办和追踪目标\n'
          '💡 分析习惯并提供建议\n\n'
          '建议先在"我的"页面完善你的画像，我能更好地为你服务。\n\n'
          '有什么想聊的吗？';
    }

    _messages.add(ChatMessage(
      isUser: false,
      content: welcomeText,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _orchestratorSubscription?.cancel();
    _secondBrain.dispose();
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

    final userMessage = ChatMessage(
      isUser: true,
      content: content,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isProcessing = true;
    });

    // 保存用户消息到数据库
    await _databaseService.insertChatMessage({
      'is_user': 1,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_search_result': 0,
    });

    _textController.clear();
    _scrollToBottom();

    // 分析用户意图并响应
    final response = await _processQuery(content);

    final assistantMessage = ChatMessage(
      isUser: false,
      content: response,
      timestamp: DateTime.now(),
      isSearchResult: response.contains('📁') || response.contains('📝'),
    );

    setState(() {
      _messages.add(assistantMessage);
      _isProcessing = false;
    });

    // 保存AI回复到数据库
    await _databaseService.insertChatMessage({
      'is_user': 0,
      'content': response,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_search_result': assistantMessage.isSearchResult ? 1 : 0,
    });

    _scrollToBottom();
  }

  Future<String> _processQuery(String query) async {
    final lowerQuery = query.toLowerCase();

    // 只保留明确的数据查询指令，其他全部交给第二大脑处理
    // 1. 精确待办查询（用户明确要查待办列表）
    final todoPatterns = ['列出待办', '显示待办', '查看待办', '我的待办清单'];
    if (todoPatterns.any((p) => lowerQuery.contains(p))) {
      return await _getTodosResponse();
    }

    // 2. 精确文件查询
    final filePatterns = ['列出文件', '显示导入的文件', '我导入的文件'];
    if (filePatterns.any((p) => lowerQuery.contains(p))) {
      return await _searchFiles(query);
    }

    // 其他所有问题交给第二大脑处理（三层架构完整处理）
    return await _secondBrain.processUserInput(query);
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
      _voiceInputPath = '${tempDir.path}/voice_input_$timestamp.wav';

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
                  color: Colors.black.withValues(alpha: 0.05),
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
  final bool isProactive;  // 是否为主动触发的消息

  ChatMessage({
    required this.isUser,
    required this.content,
    required this.timestamp,
    this.isSearchResult = false,
    this.isProactive = false,
  });
}
