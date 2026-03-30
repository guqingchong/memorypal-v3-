import 'dart:async';
import '../models/note.dart';
import 'database_service.dart';

/// 笔记服务
/// 管理文字笔记和语音笔记的CRUD操作
class NoteService {
  static final NoteService _instance = NoteService._internal();
  factory NoteService() => _instance;
  NoteService._internal();

  final _databaseService = DatabaseService();

  // 笔记变更流
  final _notesController = StreamController<List<Note>>.broadcast();
  Stream<List<Note>> get notesStream => _notesController.stream;

  /// 创建文字笔记
  Future<int> createTextNote({
    required String title,
    required String content,
    List<String> tags = const [],
    int? linkedRecordingId,
    double? latitude,
    double? longitude,
    String? locationName,
  }) async {
    final now = DateTime.now();
    final note = Note(
      type: NoteType.text,
      title: title.isEmpty ? '未命名笔记' : title,
      content: content,
      tags: tags,
      linkedRecordingId: linkedRecordingId,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      createdAt: now,
      updatedAt: now,
    );

    final id = await _databaseService.insertNote(note);
    await _refreshNotes();
    return id;
  }

  /// 创建语音笔记
  Future<int> createVoiceNote({
    required String title,
    required String audioPath,
    String? transcript,
    List<String> tags = const [],
    double? latitude,
    double? longitude,
    String? locationName,
  }) async {
    final now = DateTime.now();
    final note = Note(
      type: NoteType.voice,
      title: title.isEmpty ? '语音笔记 ${now.hour}:${now.minute}' : title,
      content: transcript ?? '',
      audioPath: audioPath,
      transcript: transcript,
      tags: tags,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      createdAt: now,
      updatedAt: now,
    );

    final id = await _databaseService.insertNote(note);
    await _refreshNotes();
    return id;
  }

  /// 更新笔记
  Future<int> updateNote(Note note) async {
    final updated = note.copyWith(
      updatedAt: DateTime.now(),
    );
    final result = await _databaseService.updateNote(updated);
    await _refreshNotes();
    return result;
  }

  /// 删除笔记
  Future<int> deleteNote(int id) async {
    final result = await _databaseService.deleteNote(id);
    await _refreshNotes();
    return result;
  }

  /// 获取所有笔记
  Future<List<Note>> getNotes({int limit = 100}) async {
    return await _databaseService.getNotes(limit: limit);
  }

  /// 搜索笔记
  Future<List<Note>> searchNotes(String query) async {
    return await _databaseService.searchNotes(query);
  }

  /// 按标签筛选笔记
  Future<List<Note>> getNotesByTag(String tag) async {
    final allNotes = await getNotes();
    return allNotes.where((note) => note.tags.contains(tag)).toList();
  }

  /// 获取所有标签
  Future<Set<String>> getAllTags() async {
    final notes = await getNotes();
    final tags = <String>{};
    for (final note in notes) {
      tags.addAll(note.tags);
    }
    return tags;
  }

  /// 刷新笔记流
  Future<void> _refreshNotes() async {
    final notes = await getNotes();
    _notesController.add(notes);
  }

  /// 释放资源
  void dispose() {
    _notesController.close();
  }
}