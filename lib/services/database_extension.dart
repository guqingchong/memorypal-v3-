import 'dart:convert';
import 'package:flutter/material.dart';
import 'database_service.dart';

/// DatabaseService 扩展方法
///
/// 为第二大脑系统提供额外的数据库操作
extension DatabaseExtension on DatabaseService {
  // ==================== 情绪状态管理 ====================

  Future<int> insertEmotionalState(Map<String, dynamic> state) async {
    try {
      final db = await database;
      // 确保表存在
      await db.execute('''
        CREATE TABLE IF NOT EXISTS emotional_states (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          state TEXT NOT NULL,
          source TEXT,
          context TEXT,
          timestamp INTEGER NOT NULL
        )
      ''');
      return await db.insert('emotional_states', state);
    } catch (e) {
      debugPrint('插入情绪状态失败: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getEmotionalStates({
    required int limit,
    int? since,
  }) async {
    try {
      final db = await database;
      String? where;
      List<dynamic>? whereArgs;
      if (since != null) {
        where = 'timestamp >= ?';
        whereArgs = [since];
      }
      return await db.query(
        'emotional_states',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('获取情绪状态失败: $e');
      return [];
    }
  }

  // ==================== 进化日志管理 ====================

  Future<int> insertEvolutionLog(Map<String, dynamic> log) async {
    try {
      final db = await database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS evolution_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          field TEXT NOT NULL,
          new_value TEXT NOT NULL,
          confidence REAL,
          reason TEXT,
          timestamp INTEGER NOT NULL
        )
      ''');
      return await db.insert('evolution_logs', log);
    } catch (e) {
      debugPrint('插入进化日志失败: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getEvolutionLogs({required int limit}) async {
    try {
      final db = await database;
      return await db.query(
        'evolution_logs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('获取进化日志失败: $e');
      return [];
    }
  }

  // ==================== 行为模式管理 ====================

  Future<int> insertBehaviorPattern(Map<String, dynamic> pattern) async {
    try {
      final db = await database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS behavior_patterns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pattern_type TEXT NOT NULL,
          frequency INTEGER,
          detected_at INTEGER NOT NULL,
          last_triggered INTEGER
        )
      ''');
      return await db.insert('behavior_patterns', pattern);
    } catch (e) {
      debugPrint('插入行为模式失败: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getBehaviorPatterns({required int limit}) async {
    try {
      final db = await database;
      return await db.query(
        'behavior_patterns',
        orderBy: 'detected_at DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('获取行为模式失败: $e');
      return [];
    }
  }

  // ==================== 主动消息管理 ====================

  Future<int> insertProactiveMessage(Map<String, dynamic> message) async {
    try {
      final db = await database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS proactive_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          priority TEXT,
          timestamp INTEGER NOT NULL
        )
      ''');
      return await db.insert('proactive_messages', message);
    } catch (e) {
      debugPrint('插入主动消息失败: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getProactiveMessages({
    required int limit,
    DateTime? since,
  }) async {
    try {
      final db = await database;
      String? where;
      List<dynamic>? whereArgs;
      if (since != null) {
        where = 'timestamp >= ?';
        whereArgs = [since.millisecondsSinceEpoch];
      }
      return await db.query(
        'proactive_messages',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('获取主动消息失败: $e');
      return [];
    }
  }

  // ==================== 行为记录管理 ====================

  Future<int> recordBehavior({
    required String action,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final db = await database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_behaviors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          metadata TEXT,
          hour INTEGER,
          weekday INTEGER,
          timestamp INTEGER NOT NULL
        )
      ''');

      final now = DateTime.now();
      return await db.insert('user_behaviors', {
        'action': action,
        'metadata': jsonEncode(metadata),
        'hour': now.hour,
        'weekday': now.weekday,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('记录行为失败: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getRecentBehaviors({
    required int hours,
  }) async {
    try {
      final db = await database;
      final since = DateTime.now().subtract(Duration(hours: hours));
      return await db.query(
        'user_behaviors',
        where: 'timestamp >= ?',
        whereArgs: [since.millisecondsSinceEpoch],
        orderBy: 'timestamp DESC',
      );
    } catch (e) {
      debugPrint('获取行为记录失败: $e');
      return [];
    }
  }
}
