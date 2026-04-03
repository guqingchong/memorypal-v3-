import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note.dart';
import '../services/share_receiver_service.dart';
import '../services/database_service.dart';
import '../services/kimi_service.dart';

/// 保存记忆页面 - 接收并保存分享的内容
///
/// 支持：文本、链接、图片、PDF的保存
class SaveMemoryScreen extends StatefulWidget {
  final ShareData? shareData;

  const SaveMemoryScreen({
    super.key,
    this.shareData,
  });

  @override
  State<SaveMemoryScreen> createState() => _SaveMemoryScreenState();
}

class _SaveMemoryScreenState extends State<SaveMemoryScreen> {
  final _databaseService = DatabaseService();
  final _kimiService = KimiService();

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  ShareData? _shareData;
  bool _isAnalyzing = false;
  bool _isSaving = false;

  // AI分析结果
  String? _aiSummary;
  List<String>? _aiTags;
  List<String>? _aiTodos;

  @override
  void initState() {
    super.initState();
    _shareData = widget.shareData;
    _initializeContent();

    // 如果有Kimi API，自动分析内容
    if (_shareData != null && _kimiService.isAvailable) {
      _analyzeContent();
    }
  }

  void _initializeContent() {
    if (_shareData == null) return;

    switch (_shareData!.type) {
      case ShareType.text:
        _titleController.text = _shareData!.subject ?? '分享的文本';
        _contentController.text = _shareData!.text ?? '';
        break;
      case ShareType.link:
        _titleController.text = '收藏的链接';
        _contentController.text = _shareData!.url ?? '';
        break;
      case ShareType.image:
        _titleController.text = '保存的图片';
        _contentController.text = '图片路径: ${_shareData!.uri}';
        break;
      case ShareType.pdf:
        _titleController.text = 'PDF文档';
        _contentController.text = 'PDF路径: ${_shareData!.uri}';
        break;
      case ShareType.multipleImages:
        _titleController.text = '多张图片';
        _contentController.text = '图片数量: ${_shareData!.uris?.length ?? 0}';
        break;
      default:
        _titleController.text = '保存的内容';
    }
  }

  Future<void> _analyzeContent() async {
    if (_shareData == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final contentToAnalyze = _contentController.text;

      // 使用Kimi API分析内容
      final prompt = '''分析以下内容，提取关键信息：

$contentToAnalyze

请以JSON格式返回：
{
  "summary": "一句话摘要",
  "tags": ["标签1", "标签2", "标签3"],
  "todos": ["可能的待办1", "可能的待办2"]
}'';

      final response = await _kimiService.askQuestion(
        prompt,
        context: [],
      );

      if (response != null) {
        // 解析JSON响应
        _parseAIResponse(response);
      }
    } catch (e) {
      print('AI分析失败: $e');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _parseAIResponse(String response) {
    try {
      // 简单的JSON解析
      final summaryMatch = RegExp(r'"summary"\s*:\s*"([^"]+)"').firstMatch(response);
      final tagsMatch = RegExp(r'"tags"\s*:\s*\[([^\]]+)\]').firstMatch(response);
      final todosMatch = RegExp(r'"todos"\s*:\s*\[([^\]]+)\]').firstMatch(response);

      if (summaryMatch != null) {
        _aiSummary = summaryMatch.group(1);
      }

      if (tagsMatch != null) {
        final tagsStr = tagsMatch.group(1);
        _aiTags = tagsStr
            ?.split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (todosMatch != null) {
        final todosStr = todosMatch.group(1);
        _aiTodos = todosStr
            ?.split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (mounted) setState(() {});
    } catch (e) {
      print('解析AI响应失败: $e');
    }
  }

  Future<void> _saveMemory() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final note = Note(
        type: NoteType.text,
        title: _titleController.text,
        content: _contentController.text,
        tags: _aiTags ?? [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _databaseService.insertNote(note);

      // 保存待办事项
      if (_aiTodos != null && _aiTodos!.isNotEmpty) {
        for (final todo in _aiTodos!) {
          await _databaseService.insertTodo({
            'content': todo,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'is_completed': 0,
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记忆已保存')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存记忆'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveMemory,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 分享类型标识
            if (_shareData != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_shareData!.type.icon, size: 16),
                    const SizedBox(width: 8),
                    Text(_shareData!.type.displayName),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // 标题输入
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '给这段记忆起个名字',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            // 内容输入
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '内容',
                hintText: '记录你的想法...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 10,
              minLines: 5,
            ),

            const SizedBox(height: 24),

            // AI分析结果
            if (_isAnalyzing)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('AI正在分析内容...'),
                  ],
                ),
              )
            else if (_aiSummary != null || _aiTags != null || _aiTodos != null)
              _buildAIAnalysisCard(),

            const SizedBox(height: 24),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveMemory,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? '保存中...' : '保存到记忆库'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIAnalysisCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'AI分析',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_aiSummary != null) ...[
              Text(
                '摘要',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(_aiSummary!),
              const SizedBox(height: 12),
            ],
            if (_aiTags != null && _aiTags!.isNotEmpty) ...[
              Text(
                '标签',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Wrap(
                spacing: 8,
                children: _aiTags!
                    .map((tag) => Chip(
                          label: Text(tag),
                          backgroundColor: Colors.blue.shade100,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (_aiTodos != null && _aiTodos!.isNotEmpty) ...[
              Text(
                '可能的待办',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              ..._aiTodos!.map((todo) => ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(todo),
                    dense: true,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}
