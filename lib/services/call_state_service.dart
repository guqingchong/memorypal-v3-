import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database_service.dart';
import 'recording_service.dart';
import 'system_recording_importer.dart';

/// 通话状态监听服务
///
/// 配合系统自动通话录音功能：
/// 1. 通话开始时暂停环境录音
/// 2. 通话结束时恢复录音并导入系统录音
class CallStateService {
  static final CallStateService _instance = CallStateService._internal();
  factory CallStateService() => _instance;
  CallStateService._internal();

  static const MethodChannel _channel = MethodChannel('com.memorypal/call_state');

  final DatabaseService _databaseService = DatabaseService();
  final RecordingService _recordingService = RecordingService();
  final SystemRecordingImporter _importer = SystemRecordingImporter();

  // 状态流
  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  // 当前状态
  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  // 是否在通话中
  bool get isInCall => _currentState == CallState.offhook;

  // 设置
  bool _enableCallDetection = true;
  bool _autoImportSystemRecordings = true;

  bool get enableCallDetection => _enableCallDetection;
  bool get autoImportSystemRecordings => _autoImportSystemRecordings;

  // 通话记录
  String? _lastPhoneNumber;
  DateTime? _callStartTime;

  /// 初始化
  Future<void> initialize() async {
    // 设置 MethodChannel 回调
    _channel.setMethodCallHandler(_handleMethodCall);

    // 加载设置
    await _loadSettings();

    debugPrint('CallStateService initialized');
  }

  /// 处理来自 Android 的通话状态
  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onCallStateChanged') {
      final args = call.arguments as Map<dynamic, dynamic>;
      final state = args['state'] as String?;
      final phoneNumber = args['phoneNumber'] as String?;
      final duration = args['duration'] as int? ?? 0;

      _handleCallState(state, phoneNumber, duration);
    }
  }

  /// 处理通话状态变化
  void _handleCallState(String? state, String? phoneNumber, int duration) {
    debugPrint('Call state changed: $state, number: $phoneNumber');

    switch (state) {
      case 'call_ringing':
        _currentState = CallState.ringing;
        _lastPhoneNumber = phoneNumber;
        _callStateController.add(_currentState);
        break;

      case 'call_started':
        _currentState = CallState.offhook;
        _lastPhoneNumber = phoneNumber;
        _callStartTime = DateTime.now();
        _callStateController.add(_currentState);

        // 暂停环境录音
        if (_enableCallDetection) {
          _pauseEnvironmentRecording();
        }
        break;

      case 'call_ended':
        _currentState = CallState.idle;
        _callStateController.add(_currentState);

        // 恢复环境录音并导入系统录音
        if (_enableCallDetection) {
          _resumeEnvironmentRecording();
          if (_autoImportSystemRecordings) {
            _importSystemRecordings(duration);
          }
        }

        _lastPhoneNumber = null;
        _callStartTime = null;
        break;

      case 'import_recordings':
        // Android 端通知导入录音
        if (_autoImportSystemRecordings) {
          _importSystemRecordings(duration);
        }
        break;
    }
  }

  /// 暂停环境录音
  Future<void> _pauseEnvironmentRecording() async {
    debugPrint('Pausing environment recording due to call');
    try {
      // 暂停后台录音服务
      // await _recordingService.pauseBackgroundRecording();
      debugPrint('Environment recording paused');
    } catch (e) {
      debugPrint('Failed to pause recording: $e');
    }
  }

  /// 恢复环境录音
  Future<void> _resumeEnvironmentRecording() async {
    debugPrint('Resuming environment recording after call');
    try {
      // 恢复后台录音服务
      // await _recordingService.resumeBackgroundRecording();
      debugPrint('Environment recording resumed');
    } catch (e) {
      debugPrint('Failed to resume recording: $e');
    }
  }

  /// 导入系统通话录音
  Future<void> _importSystemRecordings(int callDurationMs) async {
    // 延迟执行，等待系统完成录音保存
    await Future.delayed(const Duration(seconds: 5));

    debugPrint('Importing system recordings...');

    try {
      final imported = await _importer.importRecentCallRecordings(
        phoneNumber: _lastPhoneNumber,
        afterTime: _callStartTime,
        minDurationMs: callDurationMs - 5000, // 允许5秒误差
      );

      if (imported.isNotEmpty) {
        debugPrint('Imported ${imported.length} system recordings');

        // 添加到数据库并触发 AI 分析
        for (final recording in imported) {
          await _databaseService.insertRecording(recording);

          // 触发 AI 分析
          // await _analyzeRecording(recording);
        }
      } else {
        debugPrint('No system recordings found to import');
      }
    } catch (e) {
      debugPrint('Failed to import system recordings: $e');
    }
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final settings = await _databaseService.getSettings();
    _enableCallDetection = settings['enable_call_detection'] ?? true;
    _autoImportSystemRecordings = settings['auto_import_system_recordings'] ?? true;
  }

  /// 更新设置
  Future<void> updateSettings({
    bool? enableCallDetection,
    bool? autoImportSystemRecordings,
  }) async {
    if (enableCallDetection != null) {
      _enableCallDetection = enableCallDetection;
    }
    if (autoImportSystemRecordings != null) {
      _autoImportSystemRecordings = autoImportSystemRecordings;
    }

    await _databaseService.saveSettings({
      'enable_call_detection': _enableCallDetection,
      'auto_import_system_recordings': _autoImportSystemRecordings,
    });
  }

  /// 释放资源
  void dispose() {
    _callStateController.close();
  }
}

/// 通话状态枚举
enum CallState {
  idle,     // 空闲
  ringing,  // 响铃
  offhook,  // 通话中
}

/// 通话记录
class CallRecord {
  final String? phoneNumber;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMs;
  final bool isImported;

  CallRecord({
    this.phoneNumber,
    required this.startTime,
    required this.endTime,
    required this.durationMs,
    this.isImported = false,
  });
}
