import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recording.dart';
import 'database_service.dart';

// 录音服务 - 与原生层通信
class RecordingService {
  static const MethodChannel _channel = MethodChannel('com.memorypal/recording');
  static final RecordingService _instance = RecordingService._internal();

  factory RecordingService() => _instance;
  RecordingService._internal();

  final _databaseService = DatabaseService();
  Recording? _currentRecording;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

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

    final recording = _currentRecording!.copyWith(
      endTime: DateTime.now(),
      durationSeconds: _recordingSeconds,
    );

    try {
      final id = await _databaseService.insertRecording(recording);
      _recordingStateController.add(RecordingState.completed(id));
    } catch (e) {
      _recordingStateController.add(RecordingState.error(e.toString()));
    } finally {
      _currentRecording = null;
      _recordingSeconds = 0;
    }
  }

  // 处理分段录音（24小时录音模式）
  Future<void> _processSegment(String filePath) async {
    // 将分段录音保存到数据库
    final recording = Recording(
      filePath: filePath,
      startTime: DateTime.now().subtract(const Duration(minutes: 5)),
      endTime: DateTime.now(),
      durationSeconds: 300, // 5分钟分段
    );

    await _databaseService.insertRecording(recording);
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
