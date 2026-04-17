import 'dart:async';
import 'dart:io';
import 'developer_service.dart';
import 'whisper_local_service.dart';

/// Whisper服务 - 语音转文字
///
/// 【注意】此服务现已成为 [WhisperLocalService] 的薄包装器，
/// 用于保持对现有调用方（recording_service.dart、chat_screen.dart）的接口兼容性。
class WhisperService {
  static final WhisperService _instance = WhisperService._internal();
  factory WhisperService() => _instance;
  WhisperService._internal();

  bool _isInitialized = false;
  final _developerService = DeveloperService();
  final _localService = WhisperLocalService();

  // 初始化Whisper
  Future<bool> initialize({String? modelPath}) async {
    if (_isInitialized) return true;

    _developerService.log('开始初始化Whisper...', tag: 'Whisper');

    try {
      final success = await _localService.initialize(modelPath: modelPath);
      _isInitialized = success;
      if (success) {
        // model loaded successfully
      }
      _developerService.log('Whisper初始化${_isInitialized ? "成功" : "失败"}', tag: 'Whisper');
      return _isInitialized;
    } catch (e, stack) {
      _developerService.log(
        'Whisper初始化失败: $e',
        level: LogLevel.error,
        tag: 'Whisper',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  // 加载模型（动态下载）- 已弃用，直接委托给 initialize
  @Deprecated('请直接使用 initialize(modelPath: modelPath)')
  Future<bool> loadModel(String modelPath) async {
    return initialize(modelPath: modelPath);
  }

  // 转写音频文件
  Future<TranscriptionResult?> transcribe(String audioPath, {String language = 'zh'}) async {
    _developerService.log('开始转写流程，音频: $audioPath', tag: 'Whisper');

    if (!_isInitialized) {
      _developerService.log('Whisper未初始化，先进行初始化...', tag: 'Whisper');
      final initialized = await initialize();
      if (!initialized) {
        _developerService.log('Whisper初始化失败，无法转写', level: LogLevel.error, tag: 'Whisper');
        return null;
      }
    }

    // 检查音频文件是否存在
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      _developerService.log('转写失败: 音频文件不存在: $audioPath', level: LogLevel.error, tag: 'Whisper');
      return null;
    }

    // 检查文件大小
    final fileSize = await audioFile.length();
    if (fileSize == 0) {
      _developerService.log('转写失败: 音频文件为空', level: LogLevel.error, tag: 'Whisper');
      return null;
    }

    // 检查文件是否过小（小于1KB可能不是有效音频）
    if (fileSize < 1024) {
      _developerService.log('转写警告: 音频文件过小 (${fileSize}bytes)', level: LogLevel.warning, tag: 'Whisper');
    }

    _developerService.log('开始转写: $audioPath, 大小: $fileSize bytes, 语言: $language', tag: 'Whisper');

    try {
      final result = await _localService.transcribe(audioPath, language: language);

      if (result != null && result.isNotEmpty) {
        _developerService.log('转写成功，结果长度: ${result.length}', tag: 'Whisper');
        return TranscriptionResult(
          text: result,
          language: language,
          segments: null,
        );
      }

      _developerService.log('转写结果为空', level: LogLevel.warning, tag: 'Whisper');
      return null;
    } catch (e, stack) {
      _developerService.log(
        '转写失败: $e',
        level: LogLevel.error,
        tag: 'Whisper',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  // 检查模型是否存在
  Future<bool> isModelAvailable(String modelPath) async {
    final file = File(modelPath);
    return await file.exists();
  }

  // 获取推荐模型信息
  ModelInfo getRecommendedModel() {
    return ModelInfo(
      name: 'Whisper Tiny',
      fileName: 'ggml-tiny.bin',
      sizeMB: 39,
      description: '基础中文语音识别',
      isRequired: true,
    );
  }

  // 获取可选模型列表
  List<ModelInfo> getOptionalModels() {
    return [
      ModelInfo(
        name: 'Whisper Small',
        fileName: 'ggml-small.bin',
        sizeMB: 466,
        description: '更高的识别准确率',
        isRequired: false,
      ),
      ModelInfo(
        name: 'Qwen 1.5B',
        fileName: 'qwen2.5-1.5b.gguf',
        sizeMB: 950,
        description: '本地AI分析',
        isRequired: false,
      ),
    ];
  }
}

// 转写结果
class TranscriptionResult {
  final String text;
  final String? language;
  final List<TranscriptionSegment>? segments;

  TranscriptionResult({
    required this.text,
    this.language,
    this.segments,
  });
}

// 转写分段
class TranscriptionSegment {
  final int id;
  final double start;
  final double end;
  final String text;
  final double confidence;

  TranscriptionSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    required this.confidence,
  });

  factory TranscriptionSegment.fromMap(Map<dynamic, dynamic> map) {
    return TranscriptionSegment(
      id: map['id'] as int,
      start: map['start'] as double,
      end: map['end'] as double,
      text: map['text'] as String,
      confidence: map['confidence'] as double,
    );
  }
}

// 模型信息
class ModelInfo {
  final String name;
  final String fileName;
  final int sizeMB;
  final String description;
  final bool isRequired;

  ModelInfo({
    required this.name,
    required this.fileName,
    required this.sizeMB,
    required this.description,
    required this.isRequired,
  });
}
