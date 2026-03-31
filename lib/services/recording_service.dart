import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recording.dart';
import 'database_service.dart';
import 'location_service.dart';

// 录音服务 - 与原生层通信
class RecordingService {
  static const MethodChannel _channel = MethodChannel('com.memorypal/recording');
  static final RecordingService _instance = RecordingService._internal();

  factory RecordingService() => _instance;
  RecordingService._internal();

  final _databaseService = DatabaseService();
  final _locationService = LocationService();
  Recording? _currentRecording;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  LocationInfo? _currentLocation;

  // 状态流
  final _recordingStateController = StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get recordingState => _recordingStateController.stream;

  // 当前录音
  Recording? get currentRecording => _currentRecording;
  bool get isRecording => _currentRecording != null;

  // 初始化
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // 处理原生层回调
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onRecordingStarted':
        // 录音已开始
        break;
      case 'onRecordingStopped':
        // 录音已停止
        await _finalizeRecording();
        break;
      case 'onRecordingError':
        final error = call.arguments as String;
        _recordingStateController.add(RecordingState.error(error));
        break;
      case 'onSegmentSaved':
        // 分段保存完成
        final filePath = call.arguments as String;
        await _processSegment(filePath);
        break;
    }
  }

  // 开始录音
  Future<bool> startRecording({bool isVoiceNote = false}) async {
    if (_currentRecording != null) {
      return false; // 已有录音进行中
    }

    try {
      final directory = await _getRecordingDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/recording_$timestamp.m4a';

      // 尝试获取位置信息
      _currentLocation = await _locationService.getCurrentLocationInfo();

      final result = await _channel.invokeMethod('startRecording', {
        'filePath': filePath,
        'isVoiceNote': isVoiceNote,
      });

      if (result == true) {
        _currentRecording = Recording(
          filePath: filePath,
          startTime: DateTime.now(),
          endTime: DateTime.now(),
          durationSeconds: 0,
          latitude: _currentLocation?.latitude,
          longitude: _currentLocation?.longitude,
          locationName: _currentLocation?.address,
          isVoiceNote: isVoiceNote,
        );
        _recordingSeconds = 0;

        // 启动计时器
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          _recordingSeconds++;
          _recordingStateController.add(RecordingState.recording(_recordingSeconds));
        });

        _recordingStateController.add(RecordingState.recording(0));
        return true;
      }
      return false;
    } catch (e) {
      _recordingStateController.add(RecordingState.error(e.toString()));
      return false;
    }
  }

  // 停止录音
  Future<bool> stopRecording() async {
    if (_currentRecording == null) {
      return false;
    }

    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;

      final result = await _channel.invokeMethod('stopRecording');

      if (result == true) {
        await _finalizeRecording();
        return true;
      }
      return false;
    } catch (e) {
      _recordingStateController.add(RecordingState.error(e.toString()));
      return false;
    }
  }

  // 完成录音并保存到数据库
  Future<void> _finalizeRecording() async {
    if (_currentRecording == null) return;

    // 生成智能标题
    final smartTitle = await _generateSmartTitle(_currentRecording!, _recordingSeconds);

    final recording = _currentRecording!.copyWith(
      endTime: DateTime.now(),
      durationSeconds: _recordingSeconds,
      title: smartTitle,
    );

    try {
      final id = await _databaseService.insertRecording(recording);
      _recordingStateController.add(RecordingState.completed(id));
    } catch (e) {
      _recordingStateController.add(RecordingState.error(e.toString()));
    } finally {
      _currentRecording = null;
      _currentLocation = null;
      _recordingSeconds = 0;
    }
  }

  // 生成智能标题
  Future<String> _generateSmartTitle(Recording recording, int duration) async {
    final buffer = StringBuffer();

    // 1. 时间前缀（今早/下午/昨晚/昨天/周一等）
    final timePrefix = _getTimePrefix(recording.startTime);
    buffer.write(timePrefix);

    // 2. 场景标识
    if (recording.isVoiceNote) {
      buffer.write(' · 备忘');
    } else if (duration > 300) {
      // 超过5分钟认为是重要录音
      buffer.write(' · 录音');
    }

    // 3. 地点标识
    if (recording.locationName != null && recording.locationName!.isNotEmpty) {
      final shortLocation = _extractShortLocation(recording.locationName!);
      if (shortLocation.isNotEmpty) {
        buffer.write(' · $shortLocation');
      }
    }

    return buffer.toString();
  }

  // 获取时间前缀
  String _getTimePrefix(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordingDay = DateTime(time.year, time.month, time.day);
    final difference = today.difference(recordingDay).inDays;

    // 时段判断
    String period;
    final hour = time.hour;
    if (hour >= 6 && hour < 12) {
      period = '早';
    } else if (hour >= 12 && hour < 14) {
      period = '中午';
    } else if (hour >= 14 && hour < 18) {
      period = '下午';
    } else if (hour >= 18 && hour < 22) {
      period = '晚';
    } else {
      period = '深夜';
    }

    // 日期判断
    if (difference == 0) {
      return '今$period';
    } else if (difference == 1) {
      return '昨天$period';
    } else if (difference < 7) {
      final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return weekdays[time.weekday - 1];
    } else {
      return '${time.month}/${time.day}';
    }
  }

  // 提取简短地点名称
  String _extractShortLocation(String fullAddress) {
    // 尝试提取关键地点类型
    final keywords = ['公司', '办公室', '会议室', '家', '咖啡厅', '餐厅', '酒店', '机场'];
    for (final keyword in keywords) {
      if (fullAddress.contains(keyword)) {
        return keyword;
      }
    }

    // 如果地址太长，截取前10个字符
    if (fullAddress.length > 10) {
      return '${fullAddress.substring(0, 10)}...';
    }

    return fullAddress;
  }

  // 处理分段录音（24小时录音模式）
  Future<void> _processSegment(String filePath) async {
    // 获取当前位置信息
    final location = await _locationService.getCurrentLocationInfo();

    // 生成智能标题
    final startTime = DateTime.now().subtract(const Duration(minutes: 5));
    final title = await _generateSmartTitleForSegment(startTime, location);

    // 将分段录音保存到数据库
    final recording = Recording(
      filePath: filePath,
      startTime: startTime,
      endTime: DateTime.now(),
      durationSeconds: 300, // 5分钟分段
      title: title,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationName: location?.address,
    );

    await _databaseService.insertRecording(recording);
  }

  // 为后台录音分段生成标题
  Future<String> _generateSmartTitleForSegment(DateTime startTime, LocationInfo? location) async {
    final buffer = StringBuffer();

    // 时间前缀
    final timePrefix = _getTimePrefix(startTime);
    buffer.write(timePrefix);
    buffer.write(' · 环境录音');

    // 地点
    if (location?.address != null) {
      final shortLocation = _extractShortLocation(location!.address!);
      if (shortLocation.isNotEmpty) {
        buffer.write(' · $shortLocation');
      }
    }

    return buffer.toString();
  }

  // 获取录音目录
  Future<Directory> _getRecordingDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingDir = Directory('${appDir.path}/recordings');
    if (!await recordingDir.exists()) {
      await recordingDir.create(recursive: true);
    }
    return recordingDir;
  }

  // 获取所有录音
  Future<List<Recording>> getRecordings({int limit = 100}) async {
    return await _databaseService.getRecordings(limit: limit);
  }

  // 删除录音
  Future<void> deleteRecording(int id) async {
    final recording = await _databaseService.getRecording(id);
    if (recording != null) {
      // 删除文件
      final file = File(recording.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      // 删除数据库记录
      await _databaseService.deleteRecording(id);
    }
  }

  // 开始24小时环境录音（后台服务）
  Future<bool> startBackgroundRecording() async {
    try {
      final directory = await _getRecordingDirectory();
      final result = await _channel.invokeMethod('startBackgroundRecording', {
        'directory': directory.path,
        'segmentDuration': 300, // 5分钟分段
      });
      return result == true;
    } catch (e) {
      print('启动后台录音失败: $e');
      return false;
    }
  }

  // 停止24小时环境录音
  Future<bool> stopBackgroundRecording() async {
    try {
      final result = await _channel.invokeMethod('stopBackgroundRecording');
      return result == true;
    } catch (e) {
      print('停止后台录音失败: $e');
      return false;
    }
  }

  // 释放资源
  void dispose() {
    _recordingTimer?.cancel();
    _recordingStateController.close();
  }

  // 用于语音转写的临时录音（不保存到数据库）
  Future<bool> startRecordingForTranscription(String filePath) async {
    try {
      final result = await _channel.invokeMethod('startRecording', {
        'filePath': filePath,
        'isVoiceNote': false,
      });
      return result == true;
    } catch (e) {
      print('启动转写录音失败: $e');
      return false;
    }
  }

  // 停止转写录音
  Future<bool> stopRecordingForTranscription() async {
    try {
      final result = await _channel.invokeMethod('stopRecording');
      return result == true;
    } catch (e) {
      print('停止转写录音失败: $e');
      return false;
    }
  }
}

// 录音状态
abstract class RecordingState {
  const RecordingState();

  factory RecordingState.idle() = RecordingIdle;
  factory RecordingState.recording(int seconds) = RecordingInProgress;
  factory RecordingState.completed(int recordingId) = RecordingCompleted;
  factory RecordingState.error(String message) = RecordingError;
}

class RecordingIdle extends RecordingState {
  const RecordingIdle();
}

class RecordingInProgress extends RecordingState {
  final int seconds;
  const RecordingInProgress(this.seconds);
}

class RecordingCompleted extends RecordingState {
  final int recordingId;
  const RecordingCompleted(this.recordingId);
}

class RecordingError extends RecordingState {
  final String message;
  const RecordingError(this.message);
}
