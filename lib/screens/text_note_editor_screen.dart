import 'package:flutter/material.dart';
import '../services/note_service.dart';
import '../services/location_service.dart';

class TextNoteEditorScreen extends StatefulWidget {
  final int? noteId;

  const TextNoteEditorScreen({super.key, this.noteId});

  @override
  State<TextNoteEditorScreen> createState() => _TextNoteEditorScreenState();
}

class _TextNoteEditorScreenState extends State<TextNoteEditorScreen> {
  final _noteService = NoteService();
  final _locationService = LocationService();

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();

  List<String> _tags = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入笔记内容')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 获取当前位置
      final locationInfo = await _locationService.getCurrentLocationInfo();

      await _noteService.createTextNote(
        title: _titleController.text,
        content: _contentController.text,
        tags: _tags,
        latitude: locationInfo?.latitude,
        longitude: locationInfo?.longitude,
        locationName: locationInfo?.address,
      );

      if (mounted) {
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

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId == null ? '新建笔记' : '编辑笔记'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveNote,
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
      body: Column(
        children: [
          // 标题输入
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '标题（可选）',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // 标签栏
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _tags.map((tag) => Chip(
                  label: Text(tag),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => _removeTag(tag),
                )).toList(),
              ),
            ),

          // 添加标签
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      hintText: '添加标签',
                      prefixIcon: Icon(Icons.label_outline),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(
                  onPressed: _addTag,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),

          const Divider(),

          // 内容输入
          Expanded(
            child: TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: '开始输入笔记内容...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
        ],
      ),
    );
  }
}