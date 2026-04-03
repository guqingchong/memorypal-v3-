import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/database_service.dart';

/// 笔记详情页面
class NoteDetailScreen extends StatefulWidget {
  final Note note;

  const NoteDetailScreen({
    super.key,
    required this.note,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  final _databaseService = DatabaseService();
  late Note _note;
  bool _isEditing = false;

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _titleController.text = _note.title;
    _contentController.text = _note.content;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final updatedNote = _note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: DateTime.now(),
    );

    await _databaseService.updateNote(updatedNote);

    setState(() {
      _note = updatedNote;
      _isEditing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isEditing ? const Text('编辑笔记') : Text(_note.title),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveNote,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isEditing ? _buildEditView() : _buildReadView(),
      ),
    );
  }

  Widget _buildReadView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            _note.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 元信息
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                _formatDateTime(_note.createdAt),
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (_note.locationName != null) ...[
                const SizedBox(width: 16),
                Icon(Icons.location_on, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  _note.locationName!,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
          const Divider(height: 32),
          // 内容
          Text(
            _note.content,
            style: const TextStyle(
              fontSize: 16,
              height: 1.6,
            ),
          ),
          // 标签
          if (_note.tags.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _note.tags.map((tag) => Chip(
                label: Text(tag),
                backgroundColor: Colors.blue.shade50,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditView() {
    return Column(
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TextField(
            controller: _contentController,
            decoration: const InputDecoration(
              labelText: '内容',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
