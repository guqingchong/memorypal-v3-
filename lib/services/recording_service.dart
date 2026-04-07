import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/recording.dart';
import 'database_service.dart';
import 'location_service.dart';
import 'developer_service.dart';
import 'whisper_service.dart';

// 录音服务 - 与原生层通信
class RecordingService {
  static const MethodChannel _channel = MethodChannel('com.memorypal/recording');
  static final RecordingService _instance = RecordingService._internal();

  factory RecordingService() => _instance;
  RecordingService._internal();

  final _databaseService = DatabaseService();
  final _locationService = LocationService();
  final _developerService = DeveloperService();
  Recording? _currentRecording;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  LocationInfo? _currentLocation;

  // 状态流
  final _recordingStateController = StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get recordingState => _recordingStateController.stream;

  // 后台录音状态流
  final _backgroundRecordingController = StreamController<bool>.broadcast();
  Stream<bool> get backgroundRecordingState => _backgroundRecordingController.stream;

  // 当前录音
  Recording? get currentRecording => _currentRecording;
  bool get isRecording => _currentRecording != null;

  // 是否正在后台录音
  bool _isBackgroundRecording = false;
  bool get isBackgroundRecording => _isBackgroundRecording;

  // 初始化
  Future<void> initialize() async {
    try {
      _channel.setMethodCallHandler(_handleMethodCall);
    } catch (e) {
      print('录音服务初始化失败: $e');
    }
  }

  // 处理原生层回调
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    _developerService.log('收到原生层回调: ${call.method}', tag: 'Recording');
    switch (call.method) {
      case 'onRecordingStarted':
        // 录音已开始
        _developerService.log('原生层报告录音已开始', tag: 'Recording');
        break;
      case 'onRecordingStopped':
        // 录音已停止
        _developerService.log('原生层报告录音已停止，准备完成录音', tag: 'Recording');
        await _finalizeRecording();
        break;
      case 'onRecordingError':
        final error = call.arguments as String;
        _developerService.log('原生层报告录音错误: $error', level: LogLevel.error, tag: 'Recording');
        _recordingStateController.add(RecordingState.error(error));
        break;
      case 'onSegmentSaved':
        // 分段保存完成 - 处理Map参数
        final args = call.arguments as Map<dynamic, dynamic>;
        final filePath = args['filePath'] as String;
        final duration = args['duration'] as int? ?? 0;
        _developerService.log('后台录音分段已保存: $filePath, 时长: ${duration}ms', tag: 'Recording');
        await _processSegment(filePath, duration);
        break;
    }
  }

  // 开始录音
  Future<bool> startRecording({bool isVoiceNote = false}) async {
    if (_currentRecording != null) {
      _developerService.log('录音启动失败：已有录音进行中', level: LogLevel.warning, tag: 'Recording');
      return false; // 已有录音进行中
    }

    try {
      _developerService.log('开始录音，isVoiceNote=$isVoiceNote', tag: 'Recording');

      final directory = await _getRecordingDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/recording_$timestamp.wav';

      // 尝试获取位置信息
      _currentLocation = await _locationService.getCurrentLocationInfo();
      _developerService.log('位置信息: ${_currentLocation?.address ?? "未获取"}', tag: 'Recording');

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
        _developerService.log('录音已启动: $filePath', tag: 'Recording');
        return true;
      }
      _developerService.log('录音启动失败：原生返回false', level: LogLevel.error, tag: 'Recording');
      return false;
    } catch (e, stack) {
      _developerService.log(
        '录音启动异常',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
      _recordingStateController.add(RecordingState.error(e.toString()));
      return false;
    }
  }

  // 停止录音
  Future<bool> stopRecording() async {
    if (_currentRecording == null) {
      _developerService.log('停止录音失败：没有正在进行的录音', level: LogLevel.warning, tag: 'Recording');
      return false;
    }

    try {
      _developerService.log('正在停止录音...', tag: 'Recording');
      _recordingTimer?.cancel();
      _recordingTimer = null;

      final result = await _channel.invokeMethod('stopRecording');

      if (result == true) {
        _developerService.log('录音已停止，正在保存...', tag: 'Recording');
        await _finalizeRecording();
        return true;
      }
      _developerService.log('停止录音失败：原生返回false', level: LogLevel.error, tag: 'Recording');
      return false;
    } catch (e, stack) {
      _developerService.log(
        '停止录音异常',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
      _recordingStateController.add(RecordingState.error(e.toString()));
      return false;
    }
  }

  // 完成录音并保存到数据库
  Future<void> _finalizeRecording() async {
    if (_currentRecording == null) return;

    _developerService.log('完成录音并保存，时长: ${_recordingSeconds}秒', tag: 'Recording');

    // 生成智能标题
    final smartTitle = await _generateSmartTitle(_currentRecording!, _recordingSeconds);
    _developerService.log('生成智能标题: $smartTitle', tag: 'Recording');

    final recording = _currentRecording!.copyWith(
      endTime: DateTime.now(),
      durationSeconds: _recordingSeconds,
      title: smartTitle,
    );

    try {
      final id = await _databaseService.insertRecording(recording);
      _developerService.log('录音已保存到数据库，ID: $id', tag: 'Recording');

      // 自动触发转写
      if (id > 0) {
        startTranscription(id, recording.filePath);
      }

      _recordingStateController.add(RecordingState.completed(id));
    } catch (e, stack) {
      _developerService.log(
        '保存录音到数据库失败',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
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
  Future<void> _processSegment(String filePath, int durationMs) async {
    _developerService.log('处理后台录音分段: $filePath, 时长: ${durationMs}ms', tag: 'Recording');

    try {
      // 验证文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        _developerService.log('录音文件不存在: $filePath', level: LogLevel.error, tag: 'Recording');
        return;
      }

      // 获取文件大小
      final fileSize = await file.length();
      if (fileSize < 1024) { // 小于1KB的录音不保存
        _developerService.log('录音文件太小(${fileSize}bytes)，跳过保存', level: LogLevel.warning, tag: 'Recording');
        return;
      }

      // 获取当前位置信息
      LocationInfo? location;
      try {
        location = await _locationService.getCurrentLocationInfo().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _developerService.log('获取位置超时', level: LogLevel.warning, tag: 'Recording');
            return null;
          },
        );
      } catch (e) {
        _developerService.log('获取位置失败: $e', level: LogLevel.warning, tag: 'Recording');
      }

      // 计算实际时长（毫秒转秒），至少1秒
      final durationSeconds = math.max(1, (durationMs / 1000).round());
      // 计算开始时间
      final endTime = DateTime.now();
      final startTime = endTime.subtract(Duration(milliseconds: durationMs));

      // 生成智能标题
      final title = await _generateSmartTitleForSegment(startTime, location);

      // 提取文件名
      final fileName = path.basename(filePath);

      // 将分段录音保存到数据库
      final recording = Recording(
        filePath: filePath,
        fileName: fileName,
        startTime: startTime,
        endTime: endTime,
        durationSeconds: durationSeconds,
        title: title,
        latitude: location?.latitude,
        longitude: location?.longitude,
        locationName: location?.address,
        isVoiceNote: false,
        source: 'background',
      );

      final id = await _databaseService.insertRecording(recording);
      _developerService.log('后台录音分段已保存到数据库，ID: $id, 时长: ${durationSeconds}秒, 大小: ${fileSize}bytes', tag: 'Recording');

      // 自动触发转写（后台录音也自动转写）
      if (id > 0) {
        startTranscription(id, recording.filePath);
      }
    } catch (e, stack) {
      _developerService.log(
        '处理后台录音分段失败',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
    }
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
    try {
      _developerService.log('正在删除录音 ID: $id', tag: 'Recording');
      final recording = await _databaseService.getRecording(id);
      if (recording != null) {
        // 删除文件
        final file = File(recording.filePath);
        if (await file.exists()) {
          await file.delete();
          _developerService.log('已删除录音文件: ${recording.filePath}', tag: 'Recording');
        } else {
          _developerService.log('录音文件不存在: ${recording.filePath}', level: LogLevel.warning, tag: 'Recording');
        }
        // 删除数据库记录
        await _databaseService.deleteRecording(id);
        _developerService.log('已删除录音记录 ID: $id', tag: 'Recording');
      } else {
        _developerService.log('录音记录不存在 ID: $id', level: LogLevel.warning, tag: 'Recording');
      }
    } catch (e, stack) {
      _developerService.log(
        '删除录音失败 ID: $id',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 开始24小时环境录音（后台服务）
  Future<bool> startBackgroundRecording() async {
    try {
      _developerService.log('正在启动24小时后台录音...', tag: 'Recording');
      final directory = await _getRecordingDirectory();
      _developerService.log('录音目录: ${directory.path}', tag: 'Recording');

      final result = await _channel.invokeMethod('startBackgroundRecording', {
        'directory': directory.path,
        'segmentDuration': 300, // 5分钟分段
      });

      if (result == true) {
        _isBackgroundRecording = true;
        _backgroundRecordingController.add(true);
        _developerService.log('后台录音启动成功', level: LogLevel.info, tag: 'Recording');
        // 定期检查状态
        _startBackgroundStatusCheck();
      } else {
        _developerService.log('后台录音启动失败：原生返回false', level: LogLevel.error, tag: 'Recording');
      }
      return result == true;
    } catch (e, stack) {
      _developerService.log(
        '启动后台录音异常',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  // 停止24小时环境录音
  Future<bool> stopBackgroundRecording() async {
    try {
      _developerService.log('正在停止后台录音...', tag: 'Recording');
      final result = await _channel.invokeMethod('stopBackgroundRecording');
      if (result == true) {
        _isBackgroundRecording = false;
        _backgroundRecordingController.add(false);
        _backgroundStatusTimer?.cancel();
        _developerService.log('后台录音已停止', tag: 'Recording');
      } else {
        _developerService.log('停止后台录音失败：原生返回false', level: LogLevel.error, tag: 'Recording');
      }
      return result == true;
    } catch (e, stack) {
      _developerService.log(
        '停止后台录音异常',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  Timer? _backgroundStatusTimer;

  // 定期检查后台录音状态
  void _startBackgroundStatusCheck() {
    _backgroundStatusTimer?.cancel();
    _developerService.log('开始定期检查后台录音状态', tag: 'Recording');
    // 降低检查频率：从5秒改为30秒，减少电池消耗
    _backgroundStatusTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final isRunning = await _channel.invokeMethod('isBackgroundRecordingRunning');
        if (isRunning != _isBackgroundRecording) {
          _developerService.log('后台录音状态变化: $_isBackgroundRecording -> $isRunning', tag: 'Recording');
          _isBackgroundRecording = isRunning == true;
          _backgroundRecordingController.add(_isBackgroundRecording);
        }
        if (!isRunning) {
          _backgroundStatusTimer?.cancel();
          _developerService.log('后台录音已停止，取消状态检查', tag: 'Recording');
        }
      } catch (e, stack) {
        _developerService.log(
          '检查后台录音状态失败',
          level: LogLevel.error,
          tag: 'Recording',
          error: e,
          stackTrace: stack,
        );
      }
    });
  }

  // 检查后台录音是否运行
  Future<bool> isBackgroundRecordingRunning() async {
    try {
      final result = await _channel.invokeMethod('isBackgroundRecordingRunning');
      _isBackgroundRecording = result == true;
      _developerService.log('查询后台录音状态: $_isBackgroundRecording', tag: 'Recording');
      return _isBackgroundRecording;
    } catch (e, stack) {
      _developerService.log(
        '查询后台录音状态失败',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  // 开始自动转写（公开方法，供其他服务调用）
  Future<void> startTranscription(int recordingId, String filePath) async {
    _developerService.log('开始自动转写录音 ID: $recordingId', tag: 'Whisper');

    try {
      final whisperService = WhisperService();

      // 先初始化Whisper（如果还没初始化）
      final initialized = await whisperService.initialize();
      if (!initialized) {
        _developerService.log('Whisper初始化失败，跳过转写', level: LogLevel.error, tag: 'Whisper');
        return;
      }

      // 执行转写
      final result = await whisperService.transcribe(filePath);

      if (result != null && result.text.isNotEmpty) {
        _developerService.log('转写完成，ID: $recordingId, 内容长度: ${result.text.length}', tag: 'Whisper');

        // 更新数据库中的转写内容
        final recording = await _databaseService.getRecording(recordingId);
        if (recording != null) {
          final updatedRecording = recording.copyWith(
            transcript: result.text,
          );
          await _databaseService.updateRecording(updatedRecording);
          _developerService.log('转写内容已保存到数据库，ID: $recordingId', tag: 'Whisper');
        }
      } else {
        _developerService.log('转写结果为空，ID: $recordingId', level: LogLevel.warning, tag: 'Whisper');
      }
    } catch (e, stack) {
      _developerService.log(
        '自动转写失败，ID: $recordingId',
        level: LogLevel.error,
        tag: 'Whisper',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 释放资源
  void dispose() {
    _developerService.log('释放录音服务资源', tag: 'Recording');
    _recordingTimer?.cancel();
    _backgroundStatusTimer?.cancel();
    _recordingStateController.close();
    _backgroundRecordingController.close();
  }

  // 用于语音转写的临时录音（不保存到数据库）
  Future<bool> startRecordingForTranscription(String filePath) async {
    try {
      _developerService.log('启动转写录音: $filePath', tag: 'Recording');
      final result = await _channel.invokeMethod('startRecording', {
        'filePath': filePath,
        'isVoiceNote': false,
      });
      if (result == true) {
        _developerService.log('转写录音启动成功', tag: 'Recording');
      } else {
        _developerService.log('转写录音启动失败：原生返回false', level: LogLevel.error, tag: 'Recording');
      }
      return result == true;
    } catch (e, stack) {
      _developerService.log(
        '启动转写录音失败',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  // 停止转写录音
  Future<bool> stopRecordingForTranscription() async {
    try {
      _developerService.log('停止转写录音...', tag: 'Recording');
      final result = await _channel.invokeMethod('stopRecording');
      if (result == true) {
        _developerService.log('转写录音已停止', tag: 'Recording');
      } else {
        _developerService.log('停止转写录音失败：原生返回false', level: LogLevel.error, tag: 'Recording');
      }
      return result == true;
    } catch (e, stack) {
      _developerService.log(
        '停止转写录音异常',
        level: LogLevel.error,
        tag: 'Recording',
        error: e,
        stackTrace: stack,
      );
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
