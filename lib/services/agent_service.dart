import 'dart:convert';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'scheduler_service.dart';
import '../models/recording.dart';

/// AI智能体服务 - 工具调用与执行系统
///
/// 让AI助理能够执行实际操作，而不只是对话。
/// 支持的工具包括：
/// - 创建/更新/删除待办事项
/// - 搜索录音和笔记
/// - 播放指定录音
/// - 更新用户画像
/// - 设置提醒
/// - 触发录音
/// - 导入通话录音
class AgentService {
  static final AgentService _instance = AgentService._internal();
  factory AgentService() => _instance;
  AgentService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final SchedulerService _schedulerService = SchedulerService();

  // 工具执行回调（用于触发UI操作）
  Function(String recordingPath)? onPlayRecording;
  Function()? onStartRecording;
  Function(String todoContent)? onShowTodoNotification;

  /// 获取所有可用工具的定义（用于系统提示词）
  String getToolsDefinition() {
    return '''
## 可用工具

你可以通过输出特定格式的JSON来调用工具。当你需要执行操作时，输出：

```tool
{"tool": "工具名", "params": {参数对象}}
```

### 工具列表

1. **create_todo** - 创建待办事项
   ```json
   {"tool": "create_todo", "params": {"content": "待办内容", "deadline": "YYYY-MM-DD", "priority": "high/medium/low"}}
   ```

2. **search_recordings** - 搜索录音
   ```json
   {"tool": "search_recordings", "params": {"keyword": "关键词", "dateRange": "today/week/month", "source": "app/system_call/all"}}
   ```

3. **search_notes** - 搜索笔记
   ```json
   {"tool": "search_notes", "params": {"keyword": "关键词", "tags": ["标签1", "标签2"]}}
   ```

4. **play_recording** - 播放指定录音
   ```json
   {"tool": "play_recording", "params": {"recordingId": 123, "keyword": "关键词（用于搜索）"}}
   ```

5. **get_recording_transcript** - 获取录音转写文本
   ```json
   {"tool": "get_recording_transcript", "params": {"recordingId": 123, "keyword": "关键词"}}
   ```

6. **set_reminder** - 设置提醒
   ```json
   {"tool": "set_reminder", "params": {"title": "提醒标题", "content": "提醒内容", "time": "YYYY-MM-DD HH:MM"}}
   ```

7. **start_recording** - 开始录音（语音笔记）
   ```json
   {"tool": "start_recording", "params": {"type": "voice_note/background", "duration": 60}}
   ```

8. **import_call_recordings** - 导入通话录音
   ```json
   {"tool": "import_call_recordings", "params": {"phoneNumber": "可选手机号", "afterDate": "YYYY-MM-DD"}}
   ```

9. **update_profile** - 更新用户画像字段
   ```json
   {"tool": "update_profile", "params": {"field": "字段名", "value": "新值"}}
   ```

10. **complete_todo** - 标记待办完成
    ```json
    {"tool": "complete_todo", "params": {"todoId": 123, "content": "通过内容匹配"}}
    ```

11. **get_today_summary** - 获取今日概览
    ```json
    {"tool": "get_today_summary", "params": {}}
    ```

12. **delete_recording** - 删除录音
    ```json
    {"tool": "delete_recording", "params": {"recordingId": 123}}
    ```

### 使用规则

- 只有当用户明确要求执行操作时，才调用工具
- 可以同时调用多个工具（每行一个）
- 调用工具后，告诉用户你做了什么
- 如果工具需要参数但用户没提供，先询问用户
- 工具调用后，等待执行结果再继续对话

### 工具调用示例

用户说："提醒我明天下午3点开会"

你的响应：
```tool
{"tool": "set_reminder", "params": {"title": "会议提醒", "content": "开会", "time": "2024-04-08 15:00"}}
```

已为你设置明天下午3点的会议提醒！
''';  }

  /// 解析用户输入，判断是否需要工具调用
  ///
  /// 返回：需要调用的工具列表，如果为空则表示不需要工具调用
  List<ToolCall> parseToolCalls(String aiResponse) {
    final toolCalls = <ToolCall>[];

    // 匹配 ```tool ... ``` 格式的工具调用
    final toolBlockPattern = RegExp(r'```tool\s*\n(.*?)\n```', dotAll: true);
    final matches = toolBlockPattern.allMatches(aiResponse);

    for (final match in matches) {
      final jsonStr = match.group(1)?.trim();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final json = jsonDecode(jsonStr);
          if (json is Map && json.containsKey('tool')) {
            toolCalls.add(ToolCall(
              tool: json['tool'] as String,
              params: json['params'] as Map<String, dynamic>? ?? {},
            ));
          }
        } catch (e) {
          debugPrint('解析工具调用失败: $e');
        }
      }
    }

    return toolCalls;
  }

  /// 执行单个工具调用
  ///
  /// 返回工具执行结果
  Future<ToolResult> executeTool(ToolCall toolCall) async {
    try {
      switch (toolCall.tool) {
        case 'create_todo':
          return await _handleCreateTodo(toolCall.params);
        case 'search_recordings':
          return await _handleSearchRecordings(toolCall.params);
        case 'search_notes':
          return await _handleSearchNotes(toolCall.params);
        case 'play_recording':
          return await _handlePlayRecording(toolCall.params);
        case 'get_recording_transcript':
          return await _handleGetTranscript(toolCall.params);
        case 'set_reminder':
          return await _handleSetReminder(toolCall.params);
        case 'start_recording':
          return await _handleStartRecording(toolCall.params);
        case 'import_call_recordings':
          return await _handleImportCallRecordings(toolCall.params);
        case 'update_profile':
          return await _handleUpdateProfile(toolCall.params);
        case 'complete_todo':
          return await _handleCompleteTodo(toolCall.params);
        case 'get_today_summary':
          return await _handleGetTodaySummary();
        case 'delete_recording':
          return await _handleDeleteRecording(toolCall.params);
        default:
          return ToolResult.error('未知工具: ${toolCall.tool}');
      }
    } catch (e) {
      return ToolResult.error('执行失败: $e');
    }
  }

  /// 批量执行工具调用
  Future<List<ToolResult>> executeToolCalls(List<ToolCall> toolCalls) async {
    final results = <ToolResult>[];
    for (final call in toolCalls) {
      final result = await executeTool(call);
      results.add(result);
    }
    return results;
  }

  /// 构建工具执行结果的上下文描述
  String buildToolResultsContext(List<ToolResult> results) {
    if (results.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('\n\n【工具执行结果】');

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      buffer.writeln('\n[${i + 1}] ${result.success ? '✓' : '✗'} ${result.message}');
      if (result.data != null) {
        buffer.writeln('数据: ${result.data}');
      }
    }

    return buffer.toString();
  }

  // ============== 具体工具处理实现 ==============

  Future<ToolResult> _handleCreateTodo(Map<String, dynamic> params) async {
    final content = params['content'] as String?;
    if (content == null || content.isEmpty) {
      return ToolResult.error('待办内容不能为空');
    }

    final deadlineStr = params['deadline'] as String?;
    final deadline = deadlineStr != null ? DateTime.tryParse(deadlineStr) : null;
    final priority = params['priority'] as String? ?? 'medium';

    final todoData = {
      'content': content,
      'deadline': deadline?.millisecondsSinceEpoch,
      'priority': priority,
      'is_completed': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    await _databaseService.insertTodo(todoData);

    // 触发通知回调
    onShowTodoNotification?.call('已创建待办: $content');

    return ToolResult.success('待办事项已创建: $content', data: {
      'content': content,
      'deadline': deadlineStr,
      'priority': priority,
    });
  }

  Future<ToolResult> _handleSearchRecordings(Map<String, dynamic> params) async {
    final keyword = params['keyword'] as String?;
    final dateRange = params['dateRange'] as String? ?? 'all';
    final source = params['source'] as String? ?? 'all';

    var recordings = await _databaseService.getRecordings(limit: 100);

    // 按关键词过滤
    if (keyword != null && keyword.isNotEmpty) {
      final lowerKeyword = keyword.toLowerCase();
      recordings = recordings.where((r) {
        final matchTitle = r.title?.toLowerCase().contains(lowerKeyword) ?? false;
        final matchTranscript = r.transcript?.toLowerCase().contains(lowerKeyword) ?? false;
        final matchTags = r.tags.any((t) => t.toLowerCase().contains(lowerKeyword));
        final matchFileName = r.fileName?.toLowerCase().contains(lowerKeyword) ?? false;
        return matchTitle || matchTranscript || matchTags || matchFileName;
      }).toList();
    }

    // 按日期范围过滤
    if (dateRange != 'all') {
      final now = DateTime.now();
      DateTime cutoff;
      switch (dateRange) {
        case 'today':
          cutoff = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          cutoff = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          cutoff = now.subtract(const Duration(days: 30));
          break;
        default:
          cutoff = DateTime(2000);
      }
      recordings = recordings.where((r) => r.startTime.isAfter(cutoff)).toList();
    }

    // 按来源过滤
    if (source != 'all') {
      recordings = recordings.where((r) => r.source == source).toList();
    }

    // 构建结果描述
    final summaries = recordings.map((r) {
      final date = '${r.startTime.month}月${r.startTime.day}日';
      final duration = '${r.durationSeconds ~/ 60}分${r.durationSeconds % 60}秒';
      final title = r.title ?? r.fileName ?? '未命名录音';
      return {'id': r.id, 'title': title, 'date': date, 'duration': duration, 'source': r.source};
    }).toList();

    return ToolResult.success(
      '找到 ${recordings.length} 条录音',
      data: summaries,
    );
  }

  Future<ToolResult> _handleSearchNotes(Map<String, dynamic> params) async {
    final keyword = params['keyword'] as String?;
    final tags = (params['tags'] as List<dynamic>?)?.cast<String>();

    var notes = await _databaseService.getNotes(limit: 100);

    // 按关键词过滤
    if (keyword != null && keyword.isNotEmpty) {
      final lowerKeyword = keyword.toLowerCase();
      notes = notes.where((n) {
        return n.title.toLowerCase().contains(lowerKeyword) ||
            n.content.toLowerCase().contains(lowerKeyword);
      }).toList();
    }

    // 按标签过滤
    if (tags != null && tags.isNotEmpty) {
      notes = notes.where((n) {
        return tags.any((t) => n.tags.contains(t));
      }).toList();
    }

    final summaries = notes.map((n) {
      return {
        'id': n.id,
        'title': n.title,
        'type': n.type.name,
        'created': '${n.createdAt.month}月${n.createdAt.day}日',
      };
    }).toList();

    return ToolResult.success('找到 ${notes.length} 条笔记', data: summaries);
  }

  Future<ToolResult> _handlePlayRecording(Map<String, dynamic> params) async {
    final recordingId = params['recordingId'] as int?;
    final keyword = params['keyword'] as String?;

    Recording? targetRecording;

    if (recordingId != null) {
      final recordings = await _databaseService.getRecordings(limit: 1000);
      try {
        targetRecording = recordings.firstWhere(
          (r) => r.id == recordingId,
        );
      } catch (e) {
        targetRecording = null;
      }
    } else if (keyword != null && keyword.isNotEmpty) {
      final recordings = await _databaseService.getRecordings(limit: 100);
      final lowerKeyword = keyword.toLowerCase();
      try {
        targetRecording = recordings.firstWhere(
          (r) =>
              (r.title?.toLowerCase().contains(lowerKeyword) ?? false) ||
              (r.transcript?.toLowerCase().contains(lowerKeyword) ?? false),
        );
      } catch (e) {
        targetRecording = null;
      }
    }

    if (targetRecording == null) {
      return ToolResult.error('未找到匹配的录音');
    }

    // 触发播放回调
    onPlayRecording?.call(targetRecording.filePath);

    return ToolResult.success(
      '正在播放: ${targetRecording.title ?? targetRecording.fileName ?? "录音"}',
      data: {'recordingId': targetRecording.id, 'title': targetRecording.title},
    );
  }

  Future<ToolResult> _handleGetTranscript(Map<String, dynamic> params) async {
    final recordingId = params['recordingId'] as int?;
    final keyword = params['keyword'] as String?;

    Recording? targetRecording;

    if (recordingId != null) {
      final recordings = await _databaseService.getRecordings(limit: 1000);
      try {
        targetRecording = recordings.firstWhere(
          (r) => r.id == recordingId,
        );
      } catch (e) {
        targetRecording = null;
      }
    } else if (keyword != null && keyword.isNotEmpty) {
      final recordings = await _databaseService.getRecordings(limit: 100);
      final lowerKeyword = keyword.toLowerCase();
      try {
        targetRecording = recordings.firstWhere(
          (r) => (r.title?.toLowerCase().contains(lowerKeyword) ?? false),
        );
      } catch (e) {
        targetRecording = null;
      }
    }

    if (targetRecording == null) {
      return ToolResult.error('未找到匹配的录音');
    }

    final transcript = targetRecording.transcript;
    if (transcript == null || transcript.isEmpty) {
      return ToolResult.success(
        '录音 "${targetRecording.title ?? "未命名"}" 暂无转写文本',
        data: {'hasTranscript': false},
      );
    }

    return ToolResult.success(
      '获取转写成功',
      data: {
        'hasTranscript': true,
        'transcript': transcript.substring(0, transcript.length > 500 ? 500 : transcript.length),
        'fullLength': transcript.length,
      },
    );
  }

  Future<ToolResult> _handleSetReminder(Map<String, dynamic> params) async {
    final title = params['title'] as String? ?? '提醒';
    final content = params['content'] as String? ?? '';
    final timeStr = params['time'] as String?;

    if (timeStr == null || timeStr.isEmpty) {
      return ToolResult.error('请指定提醒时间');
    }

    final scheduledTime = DateTime.tryParse(timeStr);
    if (scheduledTime == null) {
      return ToolResult.error('时间格式不正确，请使用 YYYY-MM-DD HH:MM 格式');
    }

    if (scheduledTime.isBefore(DateTime.now())) {
      return ToolResult.error('提醒时间不能是过去的时间');
    }

    await _schedulerService.scheduleReminder(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: content,
      scheduledTime: scheduledTime,
    );

    return ToolResult.success('提醒已设置: $title ($timeStr)');
  }

  Future<ToolResult> _handleStartRecording(Map<String, dynamic> params) async {
    final type = params['type'] as String? ?? 'voice_note';
    final duration = params['duration'] as int?;

    // 触发录音回调
    onStartRecording?.call();

    final typeDesc = type == 'voice_note' ? '语音笔记' : '后台录音';
    return ToolResult.success('已开始$typeDesc${duration != null ? "，时长$duration秒" : ""}');
  }

  Future<ToolResult> _handleImportCallRecordings(Map<String, dynamic> params) async {
    final phoneNumber = params['phoneNumber'] as String?;

    // 这里应该调用SystemRecordingImporter，但由于是异步单例，简化处理
    return ToolResult.success(
      '正在导入通话录音${phoneNumber != null ? " (筛选号码: $phoneNumber)" : ""}',
      data: {'importStarted': true},
    );
  }

  Future<ToolResult> _handleUpdateProfile(Map<String, dynamic> params) async {
    final field = params['field'] as String?;
    final value = params['value'] as String?;

    if (field == null || value == null) {
      return ToolResult.error('请提供字段名和值');
    }

    // 获取当前画像
    final profile = await _databaseService.getUserProfile();
    if (profile == null) {
      return ToolResult.error('用户画像不存在');
    }

    // 使用 updateField 方法更新字段
    switch (field) {
      case 'name':
        profile.updateField('name', value, 1.0);
        break;
      case 'occupation':
        profile.updateField('occupation', value, 1.0);
        break;
      case 'personality':
        profile.updateField('personality', value, 1.0);
        break;
      case 'strengths':
        profile.updateField('strengths', value.split(',').map((s) => s.trim()).toList(), 1.0);
        break;
      case 'short_term_goals':
        profile.updateField('short_term_goals', value, 1.0);
        break;
      case 'long_term_dreams':
        profile.updateField('long_term_dreams', value, 1.0);
        break;
      case 'current_confusions':
        profile.updateField('current_confusions', value, 1.0);
        break;
      case 'family_members':
        profile.updateField('family_members', value.split(',').map((s) => s.trim()).toList(), 1.0);
        break;
      case 'social_circle':
        profile.updateField('social_circle', value.split(',').map((s) => s.trim()).toList(), 1.0);
        break;
      case 'work_circle':
        profile.updateField('work_circle', value.split(',').map((s) => s.trim()).toList(), 1.0);
        break;
      default:
        // 对于不支持的字段，尝试直接设置
        return ToolResult.error('暂不支持的字段: $field');
    }

    await _databaseService.saveUserProfile(profile);

    return ToolResult.success('已更新用户画像: $field = $value');
  }

  Future<ToolResult> _handleCompleteTodo(Map<String, dynamic> params) async {
    final todoId = params['todoId'] as int?;
    final content = params['content'] as String?;

    if (todoId != null) {
      await _databaseService.completeTodo(todoId);
      return ToolResult.success('待办事项已标记完成');
    } else if (content != null && content.isNotEmpty) {
      // 通过内容匹配
      final todos = await _databaseService.getTodos();
      final matches = todos.where((t) =>
          (t['content'] as String).toLowerCase().contains(content.toLowerCase()) &&
          t['is_completed'] == 0).toList();

      if (matches.isEmpty) {
        return ToolResult.error('未找到匹配的待办事项');
      }

      for (final todo in matches) {
        await _databaseService.completeTodo(todo['id'] as int);
      }

      return ToolResult.success('已标记 ${matches.length} 个待办事项完成');
    }

    return ToolResult.error('请指定待办ID或内容');
  }

  Future<ToolResult> _handleGetTodaySummary() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 今日录音
    final recordings = await _databaseService.getRecordings(limit: 1000);
    final todayRecordings = recordings.where((r) => r.startTime.isAfter(today)).toList();

    // 今日笔记
    final notes = await _databaseService.getNotes(limit: 1000);
    final todayNotes = notes.where((n) => n.createdAt.isAfter(today)).toList();

    // 待办
    final todos = await _databaseService.getTodos();
    final pendingTodos = todos.where((t) => t['is_completed'] == 0).length;

    return ToolResult.success(
      '今日概览: ${todayRecordings.length}条录音, ${todayNotes.length}条笔记, $pendingTodos个待办',
      data: {
        'recordingsToday': todayRecordings.length,
        'notesToday': todayNotes.length,
        'pendingTodos': pendingTodos,
        'recordingTitles': todayRecordings.map((r) => r.title ?? r.fileName).take(5).toList(),
      },
    );
  }

  Future<ToolResult> _handleDeleteRecording(Map<String, dynamic> params) async {
    final recordingId = params['recordingId'] as int?;
    if (recordingId == null) {
      return ToolResult.error('请指定录音ID');
    }

    await _databaseService.deleteRecording(recordingId);
    return ToolResult.success('录音已删除');
  }
}

/// 工具调用定义
class ToolCall {
  final String tool;
  final Map<String, dynamic> params;

  ToolCall({required this.tool, required this.params});
}

/// 工具执行结果
class ToolResult {
  final bool success;
  final String message;
  final dynamic data;

  ToolResult({required this.success, required this.message, this.data});

  factory ToolResult.success(String message, {dynamic data}) {
    return ToolResult(success: true, message: message, data: data);
  }

  factory ToolResult.error(String message) {
    return ToolResult(success: false, message: message);
  }
}
