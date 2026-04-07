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
  // 涵盖市场上主流品牌的系统录音路径
  static const Map<String, List<String>> RECORDING_PATHS = {
    'huawei': [
      // 用户反馈的常用路径（优先检查）
      '/storage/emulated/0/sound/',
      '/storage/emulated/0/sounds/',
      '/sdcard/sound/',
      '/sdcard/sounds/',
      // 标准路径
      '/storage/emulated/0/Sounds/Recorder/',
      '/storage/emulated/0/Sounds/Recorder/call/',
      '/storage/emulated/0/Sounds/Recorder/callrecord/',
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/Pictures/Sounds/Recorder/',
      '/sdcard/Sounds/Recorder/',
      '/sdcard/Recordings/',
      // HarmonyOS 额外路径
      '/storage/emulated/0/Music/Sounds/Recorder/',
      '/storage/emulated/0/Audio/Recorder/',
      '/storage/emulated/0/Huawei/Recorder/',
      '/storage/emulated/0/Documents/Recorder/',
      '/storage/emulated/0/CallRecordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/录音机/',
      '/storage/emulated/0/通话录音/',
      '/storage/emulated/0/Call Recording/',
      '/storage/emulated/0/Record/PhoneRecord/',
    ],
    'xiaomi': [
      '/storage/emulated/0/MIUI/sound_recorder/',
      '/storage/emulated/0/MIUI/sound_recorder/call_rec/',
      '/storage/emulated/0/MIUI/sound_recorder/app_rec/',
      '/sdcard/MIUI/sound_recorder/',
      '/sdcard/MIUI/sound_recorder/call_rec/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/录音机/',
    ],
    'oppo': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/OPPO/Recorder/',
      '/storage/emulated/0/ColorOS/Recorder/',
      '/sdcard/Recordings/',
      '/storage/emulated/0/DCIM/Recordings/',
    ],
    'vivo': [
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/录音机/',
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/vivo/Recorder/',
      '/storage/emulated/0/FuntouchOS/Recorder/',
      '/storage/emulated/0/通话录音/',
    ],
    'samsung': [
      '/storage/emulated/0/Sounds/Recorder/',
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/Samsung/Recorder/',
      '/sdcard/Sounds/Recorder/',
      '/storage/emulated/0/Call/',
      '/storage/emulated/0/通话录音/',
    ],
    'oneplus': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/一加录音/',
      '/storage/emulated/0/OxygenOS/Recorder/',
      '/storage/emulated/0/Sounds/Recorder/',
    ],
    'realme': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/Realme/Recorder/',
      '/storage/emulated/0/ColorOS/Recorder/',
    ],
    'meizu': [
      '/storage/emulated/0/Recorder/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/录音机/',
      '/storage/emulated/0/Recordings/',
    ],
    'honor': [
      '/storage/emulated/0/Sounds/Recorder/',
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/Honor/Recorder/',
    ],
    'lenovo': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/Lenovo/Recorder/',
    ],
    'motorola': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/Motorola/Recorder/',
    ],
    'asus': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/ASUS/Recorder/',
    ],
    'google': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/Sounds/Recorder/',
      '/storage/emulated/0/录音/',
    ],
    'sony': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/Sony/Recorder/',
    ],
    'nokia': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/Nokia/Recorder/',
    ],
    'zte': [
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/ZTE/Recorder/',
    ],
    // 通用路径（不区分品牌，扫描所有常见路径）
    'generic': [
      '/storage/emulated/0/sound/',
      '/storage/emulated/0/sounds/',
      '/storage/emulated/0/Sound/',
      '/storage/emulated/0/Sounds/',
      '/sdcard/sound/',
      '/sdcard/sounds/',
      '/sdcard/Sound/',
      '/sdcard/Sounds/',
      '/storage/emulated/0/Recordings/',
      '/storage/emulated/0/recordings/',
      '/sdcard/Recordings/',
      '/storage/emulated/0/录音/',
      '/storage/emulated/0/通话录音/',
      '/storage/emulated/0/电话录音/',
      '/storage/emulated/0/CallRecordings/',
    ],
  };

  // 录音文件扩展名
  // 支持各品牌手机的各种通话录音格式
  static const List<String> AUDIO_EXTENSIONS = [
    '.m4a',      // iPhone/华为/小米通用格式
    '.aac',      // 高级音频编码
    '.amr',      // 诺基亚/老款安卓常用
    '.wav',      // 无损格式
    '.mp3',      // 通用格式
    '.ogg',      // OPPO/vivo/一加常用
    '.oga',      // Ogg Audio
    '.opus',     // 微信/现代通话常用
    '.flac',     // 无损压缩
    '.wma',      // Windows Media Audio
    '.3gp',      // 早期安卓录音格式
    '.mp4',      // 部分品牌用视频容器存音频
    '.awb',      // AMR-WB 宽带语音
    '.slk',      // Silk格式(Skype/微信语音)
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
      // Android 13+ (API 33+) 使用 READ_MEDIA_AUDIO
      final audioStatus = await Permission.audio.status;
      if (audioStatus.isGranted) {
        debugPrint('已有音频权限');
        return true;
      }
      if (await Permission.audio.request().isGranted) {
        debugPrint('音频权限已获取');
        return true;
      }

      // Android 11+ (API 30+) 使用 MANAGE_EXTERNAL_STORAGE
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) {
        debugPrint('已有管理外部存储权限');
        return true;
      }
      if (await Permission.manageExternalStorage.request().isGranted) {
        debugPrint('管理外部存储权限已获取');
        return true;
      }

      // 旧版本使用存储权限
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) {
        debugPrint('已有存储权限');
        return true;
      }
      if (await Permission.storage.request().isGranted) {
        debugPrint('存储权限已获取');
        return true;
      }

      // 检查是否永久拒绝
      if (await Permission.storage.isPermanentlyDenied) {
        debugPrint('存储权限被永久拒绝，需要引导用户去设置开启');
      }
    }
    debugPrint('权限检查失败');
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
  /// - 华为: 录音文件_20240331_143022.m4a / 2024-03-31_14-30-22.m4a
  /// - 小米: 2024-03-31_14-30-22_13800138000.m4a / 通话录音_号码_时间.m4a
  /// - OPPO: 2024-03-31 14-30-22.m4a / Recording_20240331_143022.m4a
  /// - vivo: Recording_20240331_143022.m4a / 2024-03-31_14-30-22.m4a
  /// - 三星: 20240331_143022.m4a / Voice_2024-03-31_14-30-22.m4a
  /// - 一加: 2024-03-31_14-30-22.m4a / OnePlus_20240331_143022.m4a
  Map<String, dynamic> _parseRecordingFilename(String path, String brand) {
    final fileName = path.split('/').last;
    final result = <String, dynamic>{
      'phoneNumber': null,
      'duration': null,
    };

    try {
      switch (brand) {
        case 'huawei':
        case 'honor':
          // 华为/荣耀格式:
          // - 录音文件_20240331_143022.m4a
          // - 2024-03-31_14-30-22.m4a
          // - 通话录音_20240331_143022.m4a
          final huaweiMatch = RegExp(r'(\d{8})_(\d{6})').firstMatch(fileName);
          if (huaweiMatch != null) {
            // 尝试从文件名提取号码（有些版本会在文件名中包含）
            final numberMatch = RegExp(r'(1\d{10})').firstMatch(fileName);
            if (numberMatch != null) {
              result['phoneNumber'] = numberMatch.group(1);
            }
          }
          break;

        case 'xiaomi':
        case 'redmi':
          // 小米格式:
          // - 2024-03-31_14-30-22_13800138000.m4a (带号码)
          // - 通话录音_13800138000_20240331_143022.m4a
          // - 2024-03-31_14-30-22.m4a (不带号码)
          final xiaomiMatch = RegExp(
            r'(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})_(\d+)',
          ).firstMatch(fileName);
          if (xiaomiMatch != null) {
            result['phoneNumber'] = xiaomiMatch.group(3);
          } else {
            // 尝试匹配 通话录音_号码_时间 格式
            final callMatch = RegExp(r'通话录音[_-](\d{11})[_-]').firstMatch(fileName);
            if (callMatch != null) {
              result['phoneNumber'] = callMatch.group(1);
            }
          }
          break;

        case 'oppo':
        case 'realme':
          // OPPO/Realme格式:
          // - Recording_20240331_143022.m4a
          // - 2024-03-31 14-30-22.m4a
          // - 通话录音_2024-03-31_14-30-22.m4a
          final oppoMatch = RegExp(
            r'(\d{4}-\d{2}-\d{2})\s*[_-]?\s*(\d{2}-\d{2}-\d{2})',
          ).firstMatch(fileName);
          if (oppoMatch != null) {
            // 尝试提取号码
            final numberMatch = RegExp(r'(1\d{10})').firstMatch(fileName);
            if (numberMatch != null) {
              result['phoneNumber'] = numberMatch.group(1);
            }
          }
          break;

        case 'vivo':
        case 'iqoo':
          // vivo/iQOO格式:
          // - Recording_20240331_143022.m4a
          // - 2024-03-31_14-30-22.m4a
          final vivoMatch = RegExp(
            r'(\d{4}-\d{2}-\d{2})[_-](\d{2}-\d{2}-\d{2})',
          ).firstMatch(fileName);
          if (vivoMatch != null) {
            final numberMatch = RegExp(r'(1\d{10})').firstMatch(fileName);
            if (numberMatch != null) {
              result['phoneNumber'] = numberMatch.group(1);
            }
          }
          break;

        case 'samsung':
          // 三星格式:
          // - 20240331_143022.m4a
          // - Voice_2024-03-31_14-30-22.m4a
          // - Call_2024-03-31_14-30-22.m4a
          final samsungMatch = RegExp(
            r'(?:Voice|Call|Recording)?[_-]?(\d{4}-?\d{2}-?\d{2})[_-](\d{2}-?\d{2}-?\d{2})',
          ).firstMatch(fileName);
          if (samsungMatch != null) {
            final numberMatch = RegExp(r'(1\d{10})').firstMatch(fileName);
            if (numberMatch != null) {
              result['phoneNumber'] = numberMatch.group(1);
            }
          }
          break;

        case 'oneplus':
          // 一加格式:
          // - OnePlus_20240331_143022.m4a
          // - 2024-03-31_14-30-22.m4a
          final oneplusMatch = RegExp(
            r'(?:OnePlus)?[_-]?(\d{4}-?\d{2}-?\d{2})[_-](\d{2}-?\d{2}-?\d{2})',
          ).firstMatch(fileName);
          if (oneplusMatch != null) {
            final numberMatch = RegExp(r'(1\d{10})').firstMatch(fileName);
            if (numberMatch != null) {
              result['phoneNumber'] = numberMatch.group(1);
            }
          }
          break;

        default:
          // 通用格式尝试解析手机号
          // 匹配11位手机号 (1开头)
          final phoneMatch = RegExp(r'(1\d{10})').firstMatch(fileName);
          if (phoneMatch != null) {
            result['phoneNumber'] = phoneMatch.group(1);
          }

          // 尝试匹配固话号码 (区号-号码格式)
          final landlineMatch = RegExp(r'(0\d{2,3}-?\d{7,8})').firstMatch(fileName);
          if (landlineMatch != null) {
            result['phoneNumber'] = landlineMatch.group(1);
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
    debugPrint('开始扫描系统录音...');

    // 检查权限
    final hasPermission = await _checkPermission();
    if (!hasPermission) {
      debugPrint('存储权限未授予，无法扫描');
      throw Exception('需要存储权限才能扫描系统录音。请前往设置开启存储权限。');
    }

    final imported = <Recording>[];
    int totalDirsChecked = 0;
    int totalDirsExist = 0;

    // 扫描所有可能的录音目录
    for (final entry in RECORDING_PATHS.entries) {
      final brand = entry.key;
      final paths = entry.value;

      debugPrint('扫描 $brand 的录音目录...');

      for (final path in paths) {
        totalDirsChecked++;
        final dir = Directory(path);
        debugPrint('检查目录: $path');

        try {
          if (!await dir.exists()) {
            debugPrint('目录不存在: $path');
            continue;
          }

          totalDirsExist++;
          debugPrint('目录存在，开始扫描文件...');

          // 尝试列出文件
          List<FileSystemEntity> entities;
          try {
            entities = await dir.list().toList();
          } catch (e) {
            debugPrint('无法读取目录 $path: $e');
            continue;
          }

          final files = entities
              .where((entity) => entity is File)
              .map((entity) => entity as File)
              .where((file) => _isAudioFile(file.path))
              .toList();

          debugPrint('在 $path 找到 ${files.length} 个音频文件');

          for (final file in files) {
            final recording = await _processRecordingFile(
              file,
              brand: brand,
            );

            if (recording != null) {
              imported.add(recording);
              debugPrint('导入录音: ${file.path.split('/').last}');
            }
          }
        } catch (e) {
          debugPrint('扫描目录 $path 时出错: $e');
        }
      }
    }

    debugPrint('扫描完成: 检查了 $totalDirsChecked 个目录, $totalDirsExist 个存在, 导入 ${imported.length} 条录音');
    return imported;
  }

  /// 获取导入的系统录音列表
  Future<List<Recording>> getImportedSystemRecordings() async {
    final allRecordings = await _databaseService.getRecordings();
    return allRecordings.where((r) => r.source == 'system_call').toList();
  }
}
