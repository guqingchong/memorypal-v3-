import 'dart:async';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// 事项追踪服务
///
/// 自动识别和跟踪用户正在进行的事项，检测进展和停滞
class ItemTrackingService {
  static final ItemTrackingService _instance = ItemTrackingService._internal();
  factory ItemTrackingService() => _instance;
  ItemTrackingService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final NotificationService _notificationService = NotificationService();

  Timer? _analysisTimer;
  bool _initialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    // 每天分析一次事项状态
    _analysisTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _analyzeItemsStatus();
    });

    _initialized = true;
    debugPrint('ItemTrackingService 初始化完成');
  }

  /// 分析事项状态
  Future<void> _analyzeItemsStatus() async {
    try {
      final items = await _getTrackedItems();

      for (final item in items) {
        // 检查是否有新进展
        final hasProgress = await _checkForProgress(item);
        // 检查是否停滞
        final isStalled = await _checkIfStalled(item);

        if (isStalled && !item.isStalled) {
          // 事项停滞，发送通知
          await _notifyItemStalled(item);
          await _updateItemStallStatus(item.id, true);
        } else if (hasProgress && item.isStalled) {
          // 事项恢复进展
          await _updateItemStallStatus(item.id, false);
        }
      }
    } catch (e) {
      debugPrint('分析事项状态失败: $e');
    }
  }

  /// 从录音和笔记中识别潜在事项
  Future<List<TrackedItem>> _getTrackedItems() async {
    final items = <TrackedItem>[];

    // 从数据库获取已有事项
    final db = await _databaseService.database;
    final maps = await db.query('tracked_items');

    for (final map in maps) {
      items.add(TrackedItem.fromMap(map));
    }

    // 从最近录音中识别新事项
    final recordings = await _databaseService.getRecordings(limit: 50);
    for (final r in recordings) {
      if (r.transcript != null && r.id != null) {
        final newItems = _extractItemsFromText(r.transcript!, r.id!, 'recording');
        for (final item in newItems) {
          if (!_itemExists(items, item.title)) {
            items.add(item);
            await _saveTrackedItem(item);
          }
        }
      }
    }

    // 从笔记中识别新事项
    final notes = await _databaseService.getNotes(limit: 50);
    for (final n in notes) {
      if (n.id == null) continue;
      final newItems = _extractItemsFromText('${n.title} ${n.content}', n.id!, 'note');
      for (final item in newItems) {
        if (!_itemExists(items, item.title)) {
          items.add(item);
          await _saveTrackedItem(item);
        }
      }
    }

    return items;
  }

  /// 从文本中提取事项
  List<TrackedItem> _extractItemsFromText(String text, int sourceId, String sourceType) {
    final items = <TrackedItem>[];

    // 事项关键词模式
    final patterns = [
      RegExp(r'(项目|任务|工作).{0,10}([\u4e00-\u9fa5]{2,20})'),
      RegExp(r'准备(.{2,20})(汇报|报告|材料)'),
      RegExp(r'完成(.{2,20})(方案|计划|文档)'),
      RegExp(r'和(.{2,10})(开会|讨论|沟通)'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        final title = match.group(0) ?? '';
        if (title.isNotEmpty && title.length < 50) {
          items.add(TrackedItem(
            id: 0, // 新事项
            title: title,
            description: '从${sourceType == 'recording' ? '录音' : '笔记'}中提取',
            sourceId: sourceId,
            sourceType: sourceType,
            createdAt: DateTime.now(),
            lastActivityAt: DateTime.now(),
          ));
        }
      }
    }

    return items;
  }

  /// 检查事项是否已存在
  bool _itemExists(List<TrackedItem> items, String title) {
    return items.any((i) => i.title == title || _isSimilar(i.title, title));
  }

  /// 判断两个标题是否相似
  bool _isSimilar(String title1, String title2) {
    // 简化版：计算共同字符比例
    final set1 = title1.split('').toSet();
    final set2 = title2.split('').toSet();
    final common = set1.intersection(set2).length;
    final similarity = common / (set1.length + set2.length - common);
    return similarity > 0.6; // 60%相似度阈值
  }

  /// 保存追踪事项到数据库
  Future<void> _saveTrackedItem(TrackedItem item) async {
    try {
      final db = await _databaseService.database;
      await db.insert('tracked_items', item.toMap());
    } catch (e) {
      debugPrint('保存事项失败: $e');
    }
  }

  /// 更新事项停滞状态
  Future<void> _updateItemStallStatus(int id, bool isStalled) async {
    try {
      final db = await _databaseService.database;
      await db.update(
        'tracked_items',
        {
          'is_stalled': isStalled ? 1 : 0,
          'last_activity_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('更新事项状态失败: $e');
    }
  }

  /// 检查事项是否有新进展
  Future<bool> _checkForProgress(TrackedItem item) async {
    // 检查最近7天是否有相关新内容
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    // 检查录音
    final recordings = await _databaseService.getRecordings(limit: 20);
    for (final r in recordings) {
      if (r.startTime.isAfter(cutoff) && r.transcript != null) {
        if (_isRelatedToItem(r.transcript!, item)) {
          return true;
        }
      }
    }

    // 检查笔记
    final notes = await _databaseService.getNotes(limit: 20);
    for (final n in notes) {
      if (n.createdAt.isAfter(cutoff)) {
        if (_isRelatedToItem('${n.title} ${n.content}', item)) {
          return true;
        }
      }
    }

    return false;
  }

  /// 判断内容是否与事项相关
  bool _isRelatedToItem(String text, TrackedItem item) {
    final itemKeywords = item.title.split('');
    final matchCount = itemKeywords.where((k) => text.contains(k)).length;
    return matchCount >= itemKeywords.length * 0.5; // 50%关键词匹配
  }

  /// 检查事项是否停滞（超过7天无进展）
  Future<bool> _checkIfStalled(TrackedItem item) async {
    final daysSinceActivity = DateTime.now().difference(item.lastActivityAt).inDays;
    return daysSinceActivity > 7;
  }

  /// 发送事项停滞通知
  Future<void> _notifyItemStalled(TrackedItem item) async {
    final daysStalled = DateTime.now().difference(item.lastActivityAt).inDays;

    await _notificationService.showItemTracking(
      id: 8000 + item.id,
      itemName: item.title,
      message: '已停滞$daysStalled天，是否重新安排或调整计划？',
    );
  }

  /// 手动标记事项完成
  Future<void> markItemCompleted(int itemId) async {
    try {
      final db = await _databaseService.database;
      await db.update(
        'tracked_items',
        {
          'is_completed': 1,
          'completed_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
    } catch (e) {
      debugPrint('标记事项完成失败: $e');
    }
  }

  /// 获取所有追踪事项
  Future<List<TrackedItem>> getAllItems() async {
    return await _getTrackedItems();
  }

  /// 释放资源
  void dispose() {
    _analysisTimer?.cancel();
  }
}

/// 追踪事项模型
class TrackedItem {
  final int id;
  final String title;
  final String description;
  final int sourceId;
  final String sourceType;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final bool isStalled;
  final bool isCompleted;

  TrackedItem({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceId,
    required this.sourceType,
    required this.createdAt,
    required this.lastActivityAt,
    this.isStalled = false,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'source_id': sourceId,
      'source_type': sourceType,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_activity_at': lastActivityAt.millisecondsSinceEpoch,
      'is_stalled': isStalled ? 1 : 0,
      'is_completed': isCompleted ? 1 : 0,
    };
  }

  factory TrackedItem.fromMap(Map<String, dynamic> map) {
    return TrackedItem(
      id: map['id'] as int,
      title: map['title'] as String,
      description: map['description'] as String,
      sourceId: map['source_id'] as int,
      sourceType: map['source_type'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastActivityAt: DateTime.fromMillisecondsSinceEpoch(map['last_activity_at'] as int),
      isStalled: map['is_stalled'] == 1,
      isCompleted: map['is_completed'] == 1,
    );
  }
}
