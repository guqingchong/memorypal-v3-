import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'developer_service.dart';

// Whisper服务 - 语音转文字
class WhisperService {
  static const MethodChannel _channel = MethodChannel('com.memorypal/whisper');
  static final WhisperService _instance = WhisperService._internal();

  factory WhisperService() => _instance;
  WhisperService._internal();

  bool _isInitialized = false;
  bool _isModelLoaded = false;
  final _developerService = DeveloperService();

  // 初始化Whisper
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final result = await _channel.invokeMethod('initialize');
      _isInitialized = result == true;
      return _isInitialized;
    } catch (e, stack) {
      _developerService.log('Whisper初始化失败', level: LogLevel.error, tag: 'Whisper', error: e, stackTrace: stack);
      return false;
    }
  }

  // 加载模型（动态下载）
  Future<bool> loadModel(String modelPath) async {
    if (_isModelLoaded) return true;

    try {
      final result = await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
      });
      _isModelLoaded = result == true;
      return _isModelLoaded;
    } catch (e, stack) {
      _developerService.log('加载Whisper模型失败', level: LogLevel.error, tag: 'Whisper', error: e, stackTrace: stack);
      return false;
    }
  }

  // 转写音频文件
  Future<TranscriptionResult?> transcribe(String audioPath, {String language = 'zh'}) async {
    if (!_isInitialized) {
      await initialize();
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

    _developerService.log('开始转写: $audioPath, 大小: ${fileSize} bytes, 语言: $language', tag: 'Whisper');

    try {
      final result = await _channel.invokeMethod('transcribe', {
        'audioPath': audioPath,
        'language': language,
      });

      // 适配原生层返回格式：原生返回String，Flutter包装为结果对象
      if (result is String) {
        _developerService.log('转写成功，结果长度: ${result.length}', tag: 'Whisper');
        return TranscriptionResult(
          text: result,
          language: language,
          segments: null,
        );
      }

      // 如果原生层改为返回Map，也支持
      if (result is Map) {
        final text = result['text'] as String? ?? '';
        _developerService.log('转写成功(Map格式)，结果长度: ${text.length}', tag: 'Whisper');
        return TranscriptionResult(
          text: text,
          language: result['language'] as String? ?? language,
          segments: (result['segments'] as List<dynamic>?)
              ?.map((s) => TranscriptionSegment.fromMap(s))
              .toList(),
        );
      }

      return null;
    } on PlatformException catch (e) {
      _developerService.log('转写失败(PlatformException): ${e.code} - ${e.message}', level: LogLevel.error, tag: 'Whisper', error: e);
      return null;
    } catch (e, stack) {
      _developerService.log('转写失败', level: LogLevel.error, tag: 'Whisper', error: e, stackTrace: stack);
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
