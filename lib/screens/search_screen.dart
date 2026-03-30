import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/recording.dart';
import '../services/database_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _databaseService = DatabaseService();
  final _searchController = TextEditingController();

  List<Note> _notes = [];
  List<Recording> _recordings = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _notes = [];
        _recordings = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final notes = await _databaseService.searchNotes(query);

    setState(() {
      _notes = notes;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: '搜索笔记、录音...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: _search,
          autofocus: true,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _search('');
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return _buildEmptyState('输入关键词开始搜索');
    }

    if (_notes.isEmpty && _recordings.isEmpty) {
      return _buildEmptyState('未找到相关结果');
    }

    return ListView(
      children: [
        if (_notes.isNotEmpty) ...[
          _buildSectionHeader('笔记 (${_notes.length})'),
          ..._notes.map((note) => _buildNoteTile(note)),
        ],
        if (_recordings.isNotEmpty) ...[
          _buildSectionHeader('录音 (${_recordings.length})'),
          ..._recordings.map((recording) => _buildRecordingTile(recording)),
        ],
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildNoteTile(Note note) {
    return ListTile(
      leading: Icon(
        note.type == NoteType.voice ? Icons.mic : Icons.note,
        color: note.type == NoteType.voice ? Colors.orange : Colors.green,
      ),
      title: Text(note.title),
      subtitle: Text(
        note.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        // TODO: 打开笔记详情
      },
    );
  }

  Widget _buildRecordingTile(Recording recording) {
    return ListTile(
      leading: const Icon(Icons.mic, color: Colors.blue),
      title: Text('录音 ${_formatTime(recording.startTime)}'),
      subtitle: Text(recording.transcript ?? '暂无转写'),
      trailing: Text('${recording.durationSeconds}s'),
      onTap: () {
        // TODO: 打开录音详情
      },
    );
  }

  String _formatTime(DateTime time) {
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}