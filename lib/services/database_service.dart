import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/recording.dart';
import '../models/note.dart';
import '../models/user_profile.dart';
import 'developer_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  final _developerService = DeveloperService();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'memorypal.db');
    _developerService.log('初始化数据库: $path');

    try {
      final db = await openDatabase(
        path,
        version: 6,  // 升级到版本6，添加chat_messages表
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      );
      _developerService.log('数据库初始化成功');
      return db;
    } catch (e, stack) {
      _developerService.log(
        '数据库初始化失败',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    _developerService.log('数据库升级: $oldVersion -> $newVersion');

    if (oldVersion < 6) {
      // 版本6：添加AI对话历史表
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            is_user INTEGER NOT NULL,
            content TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            is_search_result INTEGER DEFAULT 0,
            session_id TEXT DEFAULT 'default'
          )
        ''');
        _developerService.log('数据库升级：创建chat_messages表');
      } catch (e) {
        _developerService.log('创建chat_messages表失败: $e');
      }
    }

    if (oldVersion < 2) {
      // 添加is_voice_note字段到录音表
      try {
        await db.execute('ALTER TABLE recordings ADD COLUMN is_voice_note INTEGER DEFAULT 0');
      } catch (e) {
        _developerService.log('升级数据库失败（可能字段已存在）: $e');
      }

      // 添加事项追踪表
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS tracked_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            source_id INTEGER,
            source_type TEXT,
            created_at INTEGER NOT NULL,
            last_activity_at INTEGER NOT NULL,
            is_stalled INTEGER DEFAULT 0,
            is_completed INTEGER DEFAULT 0,
            completed_at INTEGER
          )
        ''');
      } catch (e) {
        _developerService.log('创建事项追踪表失败: $e');
      }
    }

    if (oldVersion < 3) {
      // 添加title字段到录音表（版本3）
      try {
        await db.execute('ALTER TABLE recordings ADD COLUMN title TEXT');
        _developerService.log('数据库升级：添加title字段到recordings表');
      } catch (e) {
        _developerService.log('添加title字段失败（可能已存在）: $e');
      }
    }

    if (oldVersion < 4) {
      // 版本4：添加file_name和source字段
      try {
        await db.execute('ALTER TABLE recordings ADD COLUMN file_name TEXT');
        _developerService.log('数据库升级：添加file_name字段到recordings表');
      } catch (e) {
        _developerService.log('添加file_name字段失败（可能已存在）: $e');
      }
      try {
        await db.execute('ALTER TABLE recordings ADD COLUMN source TEXT DEFAULT "app"');
        _developerService.log('数据库升级：添加source字段到recordings表');
      } catch (e) {
        _developerService.log('添加source字段失败（可能已存在）: $e');
      }
    }

    if (oldVersion < 5) {
      // 版本5：添加imported_files表
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS imported_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_type TEXT NOT NULL,
            extracted_text TEXT,
            imported_at INTEGER NOT NULL
          )
        ''');
        _developerService.log('数据库升级：创建imported_files表');
      } catch (e) {
        _developerService.log('创建imported_files表失败: $e');
      }
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // 录音表
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        file_name TEXT,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        title TEXT,
        transcript TEXT,
        summary TEXT,
        tags TEXT,
        is_processed INTEGER DEFAULT 0,
        is_voice_note INTEGER DEFAULT 0,
        latitude REAL,
        longitude REAL,
        location_name TEXT,
        source TEXT DEFAULT 'app'
      )
    ''');

    // 笔记表
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        audio_path TEXT,
        transcript TEXT,
        tags TEXT,
        linked_recording_id INTEGER,
        latitude REAL,
        longitude REAL,
        location_name TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 用户画像表
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        gender TEXT,
        age INTEGER,
        identity TEXT,
        address TEXT,
        occupation TEXT,
        interests TEXT,
        habits TEXT,
        personality TEXT,
        strengths TEXT,
        family_members TEXT,
        work_circle TEXT,
        social_circle TEXT,
        short_term_goals TEXT,
        long_term_dreams TEXT,
        current_confusions TEXT,
        last_updated INTEGER NOT NULL,
        evidence TEXT,
        confidence TEXT
      )
    ''');

    // 事项追踪表
    await db.execute('''
      CREATE TABLE tracked_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT DEFAULT 'active',
        progress INTEGER DEFAULT 0,
        related_notes TEXT,
        related_recordings TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');

    // 用户设置表
    await db.execute('''
      CREATE TABLE user_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        max_suggestions_per_day INTEGER DEFAULT 3,
        active_start_hour INTEGER DEFAULT 8,
        active_end_hour INTEGER DEFAULT 22,
        allow_location_based INTEGER DEFAULT 1,
        allow_time_based INTEGER DEFAULT 1,
        daily_summary_time TEXT DEFAULT '08:00',
        night_analysis_enabled INTEGER DEFAULT 1,
        enable_cloud_analysis INTEGER DEFAULT 1,
        monthly_api_budget REAL DEFAULT 0,
        recording_retention_days INTEGER DEFAULT 30
      )
    ''');

    // 地理编码缓存表
    await db.execute('''
      CREATE TABLE location_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lat_approx REAL NOT NULL,
        lon_approx REAL NOT NULL,
        address TEXT,
        place_name TEXT,
        place_type TEXT,
        first_seen INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        visit_count INTEGER DEFAULT 1
      )
    ''');

    // 待办事项表
    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        deadline INTEGER,
        priority TEXT DEFAULT 'medium',
        source_type TEXT,
        source_id INTEGER,
        is_completed INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');

    // 导入文件表
    await db.execute('''
      CREATE TABLE imported_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        extracted_text TEXT,
        imported_at INTEGER NOT NULL
      )
    ''');

    // 插入默认设置
    await db.insert('user_settings', {
      'max_suggestions_per_day': 3,
      'active_start_hour': 8,
      'active_end_hour': 22,
      'allow_location_based': 1,
      'allow_time_based': 1,
      'daily_summary_time': '08:00',
      'night_analysis_enabled': 1,
      'enable_cloud_analysis': 1,
      'monthly_api_budget': 0,
      'recording_retention_days': 30,
    });

    // AI对话历史表
    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        is_user INTEGER NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_search_result INTEGER DEFAULT 0,
        session_id TEXT DEFAULT 'default'
      )
    ''');
  }

  // 录音相关操作
  Future<int> insertRecording(Recording recording) async {
    try {
      final db = await database;
      final id = await db.insert('recordings', recording.toMap());
      _developerService.log('录音已插入数据库，ID: $id, 路径: ${recording.filePath}');
      return id;
    } catch (e, stack) {
      _developerService.log(
        '插入录音失败',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<List<Recording>> getRecordings({int limit = 100, int offset = 0}) async {
    try {
      final db = await database;
      final maps = await db.query(
        'recordings',
        orderBy: 'start_time DESC',
        limit: limit,
        offset: offset,
      );
      _developerService.log('查询录音列表，返回 ${maps.length} 条记录');
      return maps.map((m) => Recording.fromMap(m)).toList();
    } catch (e, stack) {
      _developerService.log(
        '查询录音列表失败',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  Future<Recording?> getRecording(int id) async {
    final db = await database;
    final maps = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Recording.fromMap(maps.first);
  }

  Future<Recording?> getRecordingByFilePath(String filePath) async {
    try {
      final db = await database;
      final maps = await db.query(
        'recordings',
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
      if (maps.isEmpty) return null;
      return Recording.fromMap(maps.first);
    } catch (e, stack) {
      _developerService.log(
        '按路径查询录音失败',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  Future<int> updateRecording(Recording recording) async {
    final db = await database;
    return await db.update(
      'recordings',
      recording.toMap(),
      where: 'id = ?',
      whereArgs: [recording.id],
    );
  }

  Future<int> deleteRecording(int id) async {
    try {
      final db = await database;
      final result = await db.delete(
        'recordings',
        where: 'id = ?',
        whereArgs: [id],
      );
      _developerService.log('删除录音记录，ID: $id, 影响行数: $result');
      return result;
    } catch (e, stack) {
      _developerService.log(
        '删除录音记录失败，ID: $id',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<int> deleteRecordings(List<int> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final db = await database;
      final placeholders = List.filled(ids.length, '?').join(',');
      final result = await db.delete(
        'recordings',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      _developerService.log('批量删除录音记录，数量: ${ids.length}, 影响行数: $result');
      return result;
    } catch (e, stack) {
      _developerService.log(
        '批量删除录音记录失败',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 删除旧录音（循环覆盖策略）
  Future<int> deleteOldRecordings(int retentionDays) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    return await db.delete(
      'recordings',
      where: 'start_time < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  // 笔记相关操作
  Future<int> insertNote(Note note) async {
    final db = await database;
    return await db.insert('notes', note.toMap());
  }

  Future<List<Note>> getNotes({int limit = 100, int offset = 0}) async {
    try {
      final db = await database;
      _developerService.log('查询笔记列表，limit=$limit, offset=$offset');

      final maps = await db.query(
        'notes',
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );

      _developerService.log('查询到 ${maps.length} 条原始笔记数据');

      final notes = <Note>[];
      for (var i = 0; i < maps.length; i++) {
        try {
          final note = Note.fromMap(maps[i]);
          notes.add(note);
        } catch (e, stack) {
          _developerService.log(
            '解析笔记第 $i 条失败: $e',
            level: LogLevel.error,
            tag: 'Database',
            error: e,
            stackTrace: stack,
          );
          // 继续解析下一条
        }
      }

      _developerService.log('成功解析 ${notes.length}/${maps.length} 条笔记');
      return notes;
    } catch (e, stack) {
      _developerService.log(
        '查询笔记列表失败',
        level: LogLevel.error,
        tag: 'Database',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  Future<int> updateNote(Note note) async {
    final db = await database;
    return await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 搜索笔记
  Future<List<Note>> searchNotes(String query) async {
    final db = await database;
    final maps = await db.query(
      'notes',
      where: 'title LIKE ? OR content LIKE ? OR transcript LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  // 用户画像操作
  Future<UserProfile?> getUserProfile() async {
    try {
      final db = await database;
      final maps = await db.query('user_profile', limit: 1);
      if (maps.isEmpty) return null;
      return UserProfile.fromMap(maps.first);
    } catch (e) {
      _developerService.log('获取用户画像失败: $e');
      return null;
    }
  }

  Future<int> saveUserProfile(UserProfile profile) async {
    try {
      final db = await database;
      final existing = await getUserProfile();
      if (existing != null) {
        return await db.update(
          'user_profile',
          profile.toMap(),
          where: 'id = ?',
          whereArgs: [1],
        );
      } else {
        return await db.insert('user_profile', profile.toMap());
      }
    } catch (e) {
      _developerService.log('保存用户画像失败: $e');
      return -1;
    }
  }

  // 地理编码缓存操作
  Future<String?> getCachedAddress(double lat, double lon) async {
    final db = await database;
    // 近似到0.001度（约100米）
    final latApprox = (lat * 1000).round() / 1000;
    final lonApprox = (lon * 1000).round() / 1000;

    final maps = await db.query(
      'location_cache',
      where: 'lat_approx = ? AND lon_approx = ?',
      whereArgs: [latApprox, lonApprox],
    );

    if (maps.isNotEmpty) {
      // 更新访问计数和最后访问时间
      final cache = maps.first;
      await db.update(
        'location_cache',
        {
          'last_seen': DateTime.now().millisecondsSinceEpoch,
          'visit_count': (cache['visit_count'] as int) + 1,
        },
        where: 'id = ?',
        whereArgs: [cache['id']],
      );
      return cache['address'] as String?;
    }
    return null;
  }

  Future<int> cacheAddress(double lat, double lon, String address, {String? placeName, String? placeType}) async {
    final db = await database;
    final latApprox = (lat * 1000).round() / 1000;
    final lonApprox = (lon * 1000).round() / 1000;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.insert('location_cache', {
      'lat_approx': latApprox,
      'lon_approx': lonApprox,
      'address': address,
      'place_name': placeName,
      'place_type': placeType,
      'first_seen': now,
      'last_seen': now,
      'visit_count': 1,
    });
  }

  // 待办事项操作
  Future<int?> insertTodo(Map<String, dynamic> todo) async {
    try {
      final db = await database;
      return await db.insert('todos', todo);
    } catch (e) {
      _developerService.log('插入待办失败: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getTodos({bool includeCompleted = false}) async {
    try {
      final db = await database;
      return await db.query(
        'todos',
        where: includeCompleted ? null : 'is_completed = 0',
        orderBy: 'deadline ASC, priority DESC',
      );
    } catch (e) {
      _developerService.log('获取待办列表失败: $e');
      return [];
    }
  }

  Future<int> completeTodo(int id) async {
    try {
      final db = await database;
      return await db.update(
        'todos',
        {
          'is_completed': 1,
          'completed_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      _developerService.log('完成待办失败: $e');
      return 0;
    }
  }

  Future<int> deleteTodo(int id) async {
    try {
      final db = await database;
      return await db.delete(
        'todos',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      _developerService.log('删除待办失败: $e');
      return 0;
    }
  }

  // 获取设置
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final db = await database;
      final maps = await db.query('user_settings', limit: 1);
      if (maps.isEmpty) {
        // 插入默认设置并返回
        final defaultSettings = {
          'max_suggestions_per_day': 3,
          'active_start_hour': 8,
          'active_end_hour': 22,
          'allow_location_based': 1,
          'allow_time_based': 1,
          'daily_summary_time': '08:00',
          'night_analysis_enabled': 1,
          'enable_cloud_analysis': 1,
          'monthly_api_budget': 0,
          'recording_retention_days': 30,
        };
        await db.insert('user_settings', defaultSettings);
        return defaultSettings;
      }
      return maps.first;
    } catch (e) {
      _developerService.log('获取设置失败: $e');
      // 返回默认设置
      return {
        'max_suggestions_per_day': 3,
        'active_start_hour': 8,
        'active_end_hour': 22,
        'allow_location_based': 1,
        'allow_time_based': 1,
        'daily_summary_time': '08:00',
        'night_analysis_enabled': 1,
        'enable_cloud_analysis': 1,
        'monthly_api_budget': 0,
        'recording_retention_days': 30,
      };
    }
  }

  // 更新设置
  Future<int> updateSettings(Map<String, dynamic> settings) async {
    final db = await database;
    return await db.update(
      'user_settings',
      settings,
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  // 导入文件操作
  Future<int?> insertImportedFile(Map<String, dynamic> file) async {
    try {
      final db = await database;
      return await db.insert('imported_files', file);
    } catch (e) {
      _developerService.log('插入导入文件记录失败: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getImportedFiles({int limit = 100}) async {
    try {
      final db = await database;
      return await db.query(
        'imported_files',
        orderBy: 'imported_at DESC',
        limit: limit,
      );
    } catch (e) {
      _developerService.log('获取导入文件列表失败: $e');
      return [];
    }
  }

  Future<int> deleteImportedFile(int id) async {
    try {
      final db = await database;
      return await db.delete(
        'imported_files',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      _developerService.log('删除导入文件记录失败: $e');
      return 0;
    }
  }

  Future<int> deleteImportedFiles(List<int> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final db = await database;
      final placeholders = List.filled(ids.length, '?').join(',');
      return await db.delete(
        'imported_files',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    } catch (e) {
      _developerService.log('批量删除导入文件记录失败: $e');
      return 0;
    }
  }

  // AI对话历史操作
  Future<int> insertChatMessage(Map<String, dynamic> message) async {
    try {
      final db = await database;
      return await db.insert('chat_messages', {
        'is_user': message['is_user'] as int,
        'content': message['content'] as String,
        'timestamp': message['timestamp'] as int,
        'is_search_result': message['is_search_result'] ?? 0,
        'session_id': message['session_id'] ?? 'default',
      });
    } catch (e) {
      _developerService.log('插入对话消息失败: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getChatMessages({String? sessionId, int limit = 100}) async {
    try {
      final db = await database;
      return await db.query(
        'chat_messages',
        where: sessionId != null ? 'session_id = ?' : null,
        whereArgs: sessionId != null ? [sessionId] : null,
        orderBy: 'timestamp ASC',
        limit: limit,
      );
    } catch (e) {
      _developerService.log('获取对话历史失败: $e');
      return [];
    }
  }

  Future<int> deleteChatMessage(int id) async {
    try {
      final db = await database;
      return await db.delete(
        'chat_messages',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      _developerService.log('删除对话消息失败: $e');
      return 0;
    }
  }

  Future<int> clearChatHistory(String sessionId) async {
    try {
      final db = await database;
      return await db.delete(
        'chat_messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      _developerService.log('清空对话历史失败: $e');
      return 0;
    }
  }

  // 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
