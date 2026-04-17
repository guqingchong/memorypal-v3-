import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';
import 'developer_service.dart';

/// 数据导出服务
///
/// 导出用户使用数据为JSON格式，用于：
/// 1. 用户备份自己的数据
/// 2. 分享给开发者进行优化建议
/// 3. 迁移到新设备
class DataExportService {
  static final DataExportService _instance = DataExportService._internal();
  factory DataExportService() => _instance;
  DataExportService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final DeveloperService _developerService = DeveloperService();

  /// 导出完整数据
  ///
  /// [anonymize] - 是否匿名化（移除敏感信息如姓名、地址等）
  Future<DataExportResult> exportAllData({bool anonymize = false}) async {
    try {
      _developerService.log('开始导出数据', tag: 'DataExport');

      final exportData = await _collectAllData(anonymize);
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      // 保存到临时文件
      final tempDir = await getTemporaryDirectory();
      final fileName = 'memorypal_export_${_formatDateTime(DateTime.now())}.json';
      final filePath = '${tempDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(jsonString);

      _developerService.log('数据导出完成: $filePath', tag: 'DataExport');

      return DataExportResult(
        success: true,
        filePath: filePath,
        fileName: fileName,
        recordCount: _calculateRecordCount(exportData),
        dataSize: jsonString.length,
      );
    } catch (e, stack) {
      _developerService.log(
        '数据导出失败',
        level: LogLevel.error,
        tag: 'DataExport',
        error: e,
        stackTrace: stack,
      );
      return DataExportResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 导出匿名化数据（用于分享优化建议）
  Future<DataExportResult> exportForOptimization() async {
    return exportAllData(anonymize: true);
  }

  /// 导出最近的数据（最近7天）
  Future<DataExportResult> exportRecentData({bool anonymize = false}) async {
    try {
      _developerService.log('开始导出近期数据', tag: 'DataExport');

      final exportData = await _collectRecentData(anonymize);
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      final tempDir = await getTemporaryDirectory();
      final fileName = 'memorypal_recent_${_formatDateTime(DateTime.now())}.json';
      final filePath = '${tempDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(jsonString);

      _developerService.log('近期数据导出完成: $filePath', tag: 'DataExport');

      return DataExportResult(
        success: true,
        filePath: filePath,
        fileName: fileName,
        recordCount: _calculateRecordCount(exportData),
        dataSize: jsonString.length,
      );
    } catch (e, stack) {
      _developerService.log(
        '近期数据导出失败',
        level: LogLevel.error,
        tag: 'DataExport',
        error: e,
        stackTrace: stack,
      );
      return DataExportResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 导出统计摘要
  Future<DataExportResult> exportStatsSummary() async {
    try {
      _developerService.log('开始导出统计摘要', tag: 'DataExport');

      final stats = await _collectStats();
      final jsonString = const JsonEncoder.withIndent('  ').convert(stats);

      final tempDir = await getTemporaryDirectory();
      final fileName = 'memorypal_stats_${_formatDateTime(DateTime.now())}.json';
      final filePath = '${tempDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(jsonString);

      _developerService.log('统计摘要导出完成: $filePath', tag: 'DataExport');

      return DataExportResult(
        success: true,
        filePath: filePath,
        fileName: fileName,
        recordCount: 1,
        dataSize: jsonString.length,
      );
    } catch (e, stack) {
      _developerService.log(
        '统计摘要导出失败',
        level: LogLevel.error,
        tag: 'DataExport',
        error: e,
        stackTrace: stack,
      );
      return DataExportResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 分享导出的文件
  Future<void> shareExportedFile(String filePath, {String? subject}) async {
    final file = XFile(filePath);
    await Share.shareXFiles(
      [file],
      subject: subject ?? 'MemoryPal 数据导出',
      text: '这是我的 MemoryPal 使用数据，请帮我分析优化建议。',
    );
  }

  /// 收集所有数据
  Future<Map<String, dynamic>> _collectAllData(bool anonymize) async {
    final data = <String, dynamic>{
      'export_info': {
        'version': '1.0',
        'export_time': DateTime.now().toIso8601String(),
        'anonymized': anonymize,
      },
    };

    // 录音记录
    try {
      final recordings = await _databaseService.getRecordings(limit: 10000);
      data['recordings'] = recordings.map((r) {
        final map = r.toMap();
        if (anonymize) {
          map.remove('file_path');
          map.remove('file_name');
          map.remove('latitude');
          map.remove('longitude');
          map.remove('location_name');
        }
        return map;
      }).toList();
    } catch (e) {
      data['recordings_error'] = e.toString();
    }

    // 笔记
    try {
      final notes = await _databaseService.getNotes(limit: 10000);
      data['notes'] = notes.map((n) {
        final map = n.toMap();
        if (anonymize) {
          map.remove('latitude');
          map.remove('longitude');
          map.remove('location_name');
        }
        return map;
      }).toList();
    } catch (e) {
      data['notes_error'] = e.toString();
    }

    // 用户画像
    try {
      final profile = await _databaseService.getUserProfile();
      if (profile != null) {
        final map = profile.toMap();
        if (anonymize) {
          map['name'] = '***';
          map['address'] = '***';
          map.remove('work_circle');
          map.remove('social_circle');
          map.remove('family_members');
        }
        data['user_profile'] = map;
      }
    } catch (e) {
      data['user_profile_error'] = e.toString();
    }

    // 待办事项
    try {
      final todos = await _databaseService.getTodos(includeCompleted: true);
      data['todos'] = todos;
    } catch (e) {
      data['todos_error'] = e.toString();
    }

    // 设置
    try {
      final settings = await _databaseService.getSettings();
      data['settings'] = settings;
    } catch (e) {
      data['settings_error'] = e.toString();
    }

    // AI对话历史（最近100条）
    try {
      final chatMessages = await _databaseService.getChatMessages(limit: 100);
      data['chat_history'] = chatMessages.map((m) {
        if (anonymize) {
          // 匿名化：截断消息内容
          return {
            'is_user': m['is_user'],
            'timestamp': m['timestamp'],
            'content_length': (m['content'] as String).length,
          };
        }
        return m;
      }).toList();
    } catch (e) {
      data['chat_history_error'] = e.toString();
    }

    // 统计摘要
    data['summary'] = await _collectStats();

    return data;
  }

  /// 收集最近7天的数据
  Future<Map<String, dynamic>> _collectRecentData(bool anonymize) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final cutoffMs = cutoff.millisecondsSinceEpoch;

    final data = await _collectAllData(anonymize);

    // 过滤录音
    if (data['recordings'] != null) {
      data['recordings'] = (data['recordings'] as List)
          .where((r) => (r['start_time'] as int) > cutoffMs)
          .toList();
    }

    // 过滤笔记
    if (data['notes'] != null) {
      data['notes'] = (data['notes'] as List)
          .where((n) => (n['created_at'] as int) > cutoffMs)
          .toList();
    }

    // 过滤对话历史
    if (data['chat_history'] != null) {
      data['chat_history'] = (data['chat_history'] as List)
          .where((m) => (m['timestamp'] as int) > cutoffMs)
          .toList();
    }

    data['export_info'] = {
      'version': '1.0',
      'export_time': DateTime.now().toIso8601String(),
      'anonymized': anonymize,
      'date_range': 'last_7_days',
    };

    return data;
  }

  /// 收集统计信息
  Future<Map<String, dynamic>> _collectStats() async {
    final stats = <String, dynamic>{
      'generated_at': DateTime.now().toIso8601String(),
    };

    // 录音统计
    try {
      final recordings = await _databaseService.getRecordings(limit: 10000);
      final totalDuration = recordings.fold<int>(
        0,
        (sum, r) => sum + r.durationSeconds,
      );

      stats['recordings'] = {
        'total_count': recordings.length,
        'total_duration_seconds': totalDuration,
        'total_duration_minutes': (totalDuration / 60).round(),
        'avg_duration_seconds': recordings.isNotEmpty
            ? (totalDuration / recordings.length).round()
            : 0,
        'processed_count': recordings.where((r) => r.isProcessed).length,
        'voice_note_count': recordings.where((r) => r.isVoiceNote).length,
      };
    } catch (e) {
      stats['recordings_error'] = e.toString();
    }

    // 笔记统计
    try {
      final notes = await _databaseService.getNotes(limit: 10000);
      stats['notes'] = {
        'total_count': notes.length,
        'with_audio': notes.where((n) => n.audioPath != null).length,
        'with_transcript': notes.where((n) => n.transcript != null).length,
      };
    } catch (e) {
      stats['notes_error'] = e.toString();
    }

    // 待办统计
    try {
      final todos = await _databaseService.getTodos(includeCompleted: true);
      stats['todos'] = {
        'total_count': todos.length,
        'completed': todos.where((t) => t['is_completed'] == 1).length,
        'pending': todos.where((t) => t['is_completed'] == 0).length,
      };
    } catch (e) {
      stats['todos_error'] = e.toString();
    }

    // 使用频率（按天统计）
    try {
      final recordings = await _databaseService.getRecordings(limit: 1000);
      final dailyUsage = <String, int>{};

      for (final r in recordings) {
        final date = r.startTime;
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        dailyUsage[key] = (dailyUsage[key] ?? 0) + 1;
      }

      stats['usage_frequency'] = {
        'active_days': dailyUsage.length,
        'daily_average': dailyUsage.isNotEmpty
            ? recordings.length / dailyUsage.length
            : 0,
        'daily_breakdown': dailyUsage,
      };
    } catch (e) {
      stats['usage_frequency_error'] = e.toString();
    }

    return stats;
  }

  /// 计算记录总数
  int _calculateRecordCount(Map<String, dynamic> data) {
    int count = 0;
    if (data['recordings'] is List) {
      count += (data['recordings'] as List).length;
    }
    if (data['notes'] is List) {
      count += (data['notes'] as List).length;
    }
    if (data['todos'] is List) {
      count += (data['todos'] as List).length;
    }
    return count;
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 清理临时导出文件
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();

      for (final file in files) {
        if (file is File && file.path.contains('memorypal_export')) {
          await file.delete();
          _developerService.log('清理临时文件: ${file.path}', tag: 'DataExport');
        }
      }
    } catch (e) {
      _developerService.log('清理临时文件失败: $e', tag: 'DataExport');
    }
  }
}

/// 导出结果
class DataExportResult {
  final bool success;
  final String? filePath;
  final String? fileName;
  final int? recordCount;
  final int? dataSize;
  final String? errorMessage;

  DataExportResult({
    required this.success,
    this.filePath,
    this.fileName,
    this.recordCount,
    this.dataSize,
    this.errorMessage,
  });

  String get dataSizeFormatted {
    if (dataSize == null) return '0 B';
    if (dataSize! < 1024) return '$dataSize B';
    if (dataSize! < 1024 * 1024) return '${(dataSize! / 1024).toStringAsFixed(1)} KB';
    return '${(dataSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
