import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/recording.dart';
import '../models/note.dart';
import '../models/user_profile.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'memorypal.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // 录音表
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        transcript TEXT,
        summary TEXT,
        tags TEXT,
        is_processed INTEGER DEFAULT 0,
        latitude REAL,
        longitude REAL,
        location_name TEXT
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
  }

  // 录音相关操作
  Future<int> insertRecording(Recording recording) async {
    final db = await database;
    return await db.insert('recordings', recording.toMap());
  }

  Future<List<Recording>> getRecordings({int limit = 100, int offset = 0}) async {
    final db = await database;
    final maps = await db.query(
      'recordings',
      orderBy: 'start_time DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => Recording.fromMap(m)).toList();
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
    final db = await database;
    return await db.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final db = await database;
    final maps = await db.query(
      'notes',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => Note.fromMap(m)).toList();
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
    final db = await database;
    final maps = await db.query('user_profile');
    if (maps.isEmpty) return null;
    return UserProfile.fromMap(maps.first);
  }

  Future<int> saveUserProfile(UserProfile profile) async {
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
  Future<int> insertTodo(Map<String, dynamic> todo) async {
    final db = await database;
    return await db.insert('todos', todo);
  }

  Future<List<Map<String, dynamic>>> getTodos({bool includeCompleted = false}) async {
    final db = await database;
    return await db.query(
      'todos',
      where: includeCompleted ? null : 'is_completed = 0',
      orderBy: 'deadline ASC, priority DESC',
    );
  }

  Future<int> completeTodo(int id) async {
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
  }

  // 获取设置
  Future<Map<String, dynamic>> getSettings() async {
    final db = await database;
    final maps = await db.query('user_settings');
    if (maps.isEmpty) {
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
      return await getSettings();
    }
    return maps.first;
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
  Future<int> insertImportedFile(Map<String, dynamic> file) async {
    final db = await database;
    return await db.insert('imported_files', file);
  }

  Future<List<Map<String, dynamic>>> getImportedFiles({int limit = 100}) async {
    final db = await database;
    return await db.query(
      'imported_files',
      orderBy: 'imported_at DESC',
      limit: limit,
    );
  }

  Future<int> deleteImportedFile(int id) async {
    final db = await database;
    return await db.delete(
      'imported_files',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
