import 'dart:async';
import 'package:flutter/foundation.dart';

/// 转写状态服务 - 跟踪和管理转写任务状态
///
/// 提供全局转写状态广播，让UI可以实时显示转写进度
class TranscriptionStatusService {
  static final TranscriptionStatusService _instance = TranscriptionStatusService._internal();
  factory TranscriptionStatusService() => _instance;
  TranscriptionStatusService._internal();

  // 状态流控制器
  final _statusController = StreamController<TranscriptionStatus>.broadcast();
  Stream<TranscriptionStatus> get statusStream => _statusController.stream;

  // 当前状态
  TranscriptionStatus _currentStatus = TranscriptionStatus.idle();
  TranscriptionStatus get currentStatus => _currentStatus;

  // 转写历史
  final List<TranscriptionTask> _taskHistory = [];
  List<TranscriptionTask> get taskHistory => List.unmodifiable(_taskHistory);

  /// 开始转写任务
  void startTranscription(String recordingId, String fileName) {
    final task = TranscriptionTask(
      id: recordingId,
      fileName: fileName,
      startTime: DateTime.now(),
      status: TranscriptionStep.initializing,
    );

    _taskHistory.add(task);
    _updateStatus(TranscriptionStatus.transcribing(task));
  }

  /// 更新转写进度
  void updateProgress(String recordingId, double progress, {String? message}) {
    final task = _findTask(recordingId);
    if (task != null) {
      task.progress = progress;
      task.message = message ?? task.message;
      _updateStatus(TranscriptionStatus.transcribing(task));
    }
  }

  /// 转写步骤更新
  void updateStep(String recordingId, TranscriptionStep step, {String? message}) {
    final task = _findTask(recordingId);
    if (task != null) {
      task.status = step;
      task.message = message ?? _getDefaultMessage(step);
      _updateStatus(TranscriptionStatus.transcribing(task));
    }
  }

  /// 转写完成
  void completeTranscription(String recordingId, String text, {List<String>? tags}) {
    final task = _findTask(recordingId);
    if (task != null) {
      task.status = TranscriptionStep.completed;
      task.progress = 1.0;
      task.resultText = text;
      task.tags = tags ?? [];
      task.endTime = DateTime.now();
      _updateStatus(TranscriptionStatus.completed(task));
    }
  }

  /// 转写失败
  void failTranscription(String recordingId, String error) {
    final task = _findTask(recordingId);
    if (task != null) {
      task.status = TranscriptionStep.failed;
      task.error = error;
      task.endTime = DateTime.now();
      _updateStatus(TranscriptionStatus.failed(task));
    }
  }

  /// 空闲状态
  void setIdle() {
    _updateStatus(TranscriptionStatus.idle());
  }

  /// 查找任务
  TranscriptionTask? _findTask(String recordingId) {
    try {
      return _taskHistory.lastWhere((t) => t.id == recordingId);
    } catch (e) {
      return null;
    }
  }

  /// 更新状态
  void _updateStatus(TranscriptionStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  /// 获取步骤默认消息
  String _getDefaultMessage(TranscriptionStep step) {
    switch (step) {
      case TranscriptionStep.initializing:
        return '初始化转写引擎...';
      case TranscriptionStep.loadingModel:
        return '加载Whisper模型...';
      case TranscriptionStep.preprocessing:
        return '预处理音频...';
      case TranscriptionStep.transcribing:
        return '正在转写...';
      case TranscriptionStep.postprocessing:
        return '后处理结果...';
      case TranscriptionStep.analyzing:
        return 'AI分析中...';
      case TranscriptionStep.completed:
        return '转写完成';
      case TranscriptionStep.failed:
        return '转写失败';
    }
  }

  /// 清理历史记录
  void clearHistory() {
    _taskHistory.clear();
  }

  /// 释放资源
  void dispose() {
    _statusController.close();
  }
}

/// 转写状态
class TranscriptionStatus {
  final TranscriptionState state;
  final TranscriptionTask? task;

  TranscriptionStatus._(this.state, this.task);

  factory TranscriptionStatus.idle() => TranscriptionStatus._(TranscriptionState.idle, null);
  factory TranscriptionStatus.transcribing(TranscriptionTask task) =>
      TranscriptionStatus._(TranscriptionState.transcribing, task);
  factory TranscriptionStatus.completed(TranscriptionTask task) =>
      TranscriptionStatus._(TranscriptionState.completed, task);
  factory TranscriptionStatus.failed(TranscriptionTask task) =>
      TranscriptionStatus._(TranscriptionState.failed, task);

  bool get isIdle => state == TranscriptionState.idle;
  bool get isTranscribing => state == TranscriptionState.transcribing;
  bool get isCompleted => state == TranscriptionState.completed;
  bool get isFailed => state == TranscriptionState.failed;
}

/// 转写状态枚举
enum TranscriptionState {
  idle,
  transcribing,
  completed,
  failed,
}

/// 转写步骤
enum TranscriptionStep {
  initializing,   // 初始化
  loadingModel,   // 加载模型
  preprocessing,  // 预处理
  transcribing,   // 转写中
  postprocessing, // 后处理
  analyzing,      // AI分析
  completed,      // 完成
  failed,         // 失败
}

/// 转写任务
class TranscriptionTask {
  final String id;
  final String fileName;
  final DateTime startTime;
  DateTime? endTime;
  TranscriptionStep status;
  double progress;
  String message;
  String? resultText;
  String? error;
  List<String> tags;

  TranscriptionTask({
    required this.id,
    required this.fileName,
    required this.startTime,
    this.status = TranscriptionStep.initializing,
    this.progress = 0.0,
    this.message = '准备中...',
    this.resultText,
    this.error,
    this.tags = const [],
  });

  /// 获取耗时（秒）
  int get elapsedSeconds {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inSeconds;
  }

  /// 获取进度百分比
  int get progressPercent => (progress * 100).round();
}
