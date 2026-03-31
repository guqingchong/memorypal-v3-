import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/recording.dart';
import 'database_service.dart';

/// 系统通话录音导入服务
///
/// 扫描并导入华为、小米等品牌的系统通话录音
class SystemRecordingImporter {
  final DatabaseService _databaseService = DatabaseService();

  // 各品牌手机的录音目录
  static const Map<String, List<String>> RECORDING_PATHS = {
    'huawei': [
      '/storage/emulated/0/Sounds/Recorder/',
      '/storage/emulated/0/Recordings/',
    ],
    'xiaomi': [
      '/storage/emulated/0/MIUI/sound_recorder/',
      '/storage/emulated/0/MIUI/sound_recorder/call_rec/',
    ],
    'oppo': [
      '/storage/emulated/0/Recordings/',
    ],
    'vivo': [
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/录音机/',
    ],
    'samsung': [
      '/storage/emulated/0/Sounds/Recorder/',
      '/storage/emulated/0/Recordings/',
    ],
  };

  // 录音文件扩展名
  static const List<String> AUDIO_EXTENSIONS = [
    '.m4a',
    '.aac',
    '.amr',
    '.wav',
    '.mp3',
  ];

  /// 导入最近的通话录音
  ///
  /// [phoneNumber] 可选，筛选特定号码
  /// [afterTime] 可选，只导入该时间之后的录音
  /// [minDurationMs] 可选，最小通话时长
  Future<List<Recording>> importRecentCallRecordings({
    String? phoneNumber,
    DateTime? afterTime,
    int? minDurationMs,
  }) async {
    final List<Recording> imported = [];

    // 检查存储权限
    if (!await _checkPermission()) {
      debugPrint('Storage permission denied');
      return imported;
    }

    // 扫描所有可能的录音目录
    for (final entry in RECORDING_PATHS.entries) {
      final brand = entry.key;
      final paths = entry.value;

      for (final path in paths) {
        final dir = Directory(path);
        if (!await dir.exists()) continue;

        try {
          final files = await dir
              .list()
              .where((entity) => entity is File)
              .map((entity) => entity as File)
              .where((file) => _isAudioFile(file.path))
              .toList();

          for (final file in files) {
            final recording = await _processRecordingFile(
              file,
              brand: brand,
              phoneNumber: phoneNumber,
              afterTime: afterTime,
              minDurationMs: minDurationMs,
            );

            if (recording != null) {
              imported.add(recording);
            }
          }
        } catch (e) {
          debugPrint('Error scanning directory $path: $e');
        }
      }
    }

    return imported;
  }

  /// 检查存储权限
  Future<bool> _checkPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ 使用 READ_MEDIA_AUDIO
      if (await Permission.audio.request().isGranted) {
        return true;
      }
      // 旧版本使用存储权限
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      // 尝试管理外部存储（Android 11+）
      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
    }
    return false;
  }

  /// 检查是否为音频文件
  bool _isAudioFile(String path) {
    final lowerPath = path.toLowerCase();
    return AUDIO_EXTENSIONS.any((ext) => lowerPath.endsWith(ext));
  }

  /// 处理录音文件
  Future<Recording?> _processRecordingFile(
    File file, {
    required String brand,
    String? phoneNumber,
    DateTime? afterTime,
    int? minDurationMs,
  }) async {
    try {
      final stat = await file.stat();
      final modifiedTime = stat.modified;

      // 检查时间
      if (afterTime != null && modifiedTime.isBefore(afterTime)) {
        return null;
      }

      // 检查是否已导入
      if (await _isAlreadyImported(file.path)) {
        return null;
      }

      // 解析文件名获取信息
      final fileInfo = _parseRecordingFilename(file.path, brand);

      // 检查电话号码匹配
      if (phoneNumber != null &&
          fileInfo['phoneNumber'] != null &&
          !fileInfo['phoneNumber']!.contains(phoneNumber)) {
        return null;
      }

      // 复制到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/system_recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final fileName =
          'system_${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
      final destPath = '${recordingsDir.path}/$fileName';
      await file.copy(destPath);

      // 创建 Recording 对象
      final recording = Recording(
        id: null,
        filePath: destPath,
        fileName: fileName,
        startTime: modifiedTime,
        durationSeconds: fileInfo['duration'] ?? 0,
        isVoiceNote: false,
        locationName: null,
        tags: ['通话录音', brand, if (fileInfo['phoneNumber'] != null) fileInfo['phoneNumber']!],
        transcript: null,
        summary: null,
        source: 'system_call', // 标记为系统通话录音
      );

      debugPrint('Imported system recording: $fileName');
      return recording;
    } catch (e) {
      debugPrint('Error processing file ${file.path}: $e');
      return null;
    }
  }

  /// 解析录音文件名获取信息
  ///
  /// 不同品牌的文件名格式不同：
  /// - 华为: 录音文件_20240331_143022.m4a
  /// - 小米: 2024-03-31_14-30-22_电话号码.m4a
  Map<String, dynamic> _parseRecordingFilename(String path, String brand) {
    final fileName = path.split('/').last;
    final result = <String, dynamic>{
      'phoneNumber': null,
      'duration': null,
    };

    try {
      switch (brand) {
        case 'huawei':
          // 华为格式: 录音文件_20240331_143022.m4a
          final match = RegExp(r'(\d{8})_(\d{6})').firstMatch(fileName);
          if (match != null) {
            // date: match.group(1), time: match.group(2)
            // 可以从其他来源获取号码
          }
          break;

        case 'xiaomi':
          // 小米格式: 2024-03-31_14-30-22_13800138000.m4a
          final match = RegExp(r'(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})_(\d+)')
              .firstMatch(fileName);
          if (match != null) {
            result['phoneNumber'] = match.group(3);
          }
          break;

        case 'oppo':
        case 'vivo':
        case 'samsung':
          // 通用格式尝试解析
          final phoneMatch = RegExp(r'(\d{11})').firstMatch(fileName);
          if (phoneMatch != null) {
            result['phoneNumber'] = phoneMatch.group(1);
          }
          break;
      }
    } catch (e) {
      debugPrint('Error parsing filename: $e');
    }

    return result;
  }

  /// 检查文件是否已导入
  Future<bool> _isAlreadyImported(String originalPath) async {
    final recordings = await _databaseService.getRecordings();
    return recordings.any((r) =>
        r.source == 'system_call' &&
        r.filePath.contains(originalPath.split('/').last));
  }

  /// 扫描所有系统录音（不分品牌）
  Future<List<Recording>> scanAllSystemRecordings() async {
    return importRecentCallRecordings();
  }

  /// 获取导入的系统录音列表
  Future<List<Recording>> getImportedSystemRecordings() async {
    final allRecordings = await _databaseService.getRecordings();
    return allRecordings.where((r) => r.source == 'system_call').toList();
  }
}
