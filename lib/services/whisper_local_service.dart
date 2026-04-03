import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'whisper_platform_channel.dart';

/// 本地Whisper语音转写服务
///
/// 封装 whisper.cpp 的调用，实现完全离线的语音转文字
///
/// 使用步骤：
/// 1. 下载模型文件 ggml-small.bin (~244MB)
/// 2. 放置到 assets/models/ 或应用文档目录
/// 3. 调用 initialize() 初始化
/// 4. 调用 transcribe() 进行转写
///
/// TODO: 当前为骨架实现，需要集成本地库
class WhisperLocalService {
  static final WhisperLocalService _instance = WhisperLocalService._internal();
  factory WhisperLocalService() => _instance;
  WhisperLocalService._internal();

  // 模型状态
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _modelPath;
  String? _error;

  // 模型下载URL (多个备用源)
  static const List<String> _modelUrls = [
    'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-small.bin', // 国内镜像
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin', // 官方源
  ];

  // 支持的模型文件名（按优先级排序）
  static const List<String> _modelFileNames = [
    'ggml-small.bin',
    'ggml-small-q5_1.bin',  // 量化版本，更小更快
    'ggml-tiny.bin',         // 超轻量版本
    'ggml-base.bin',         // 基础版本
  ];

  // 进度回调
  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  // 状态获取
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isDownloading => _isDownloading;
  String? get error => _error;

  /// 初始化Whisper模型
  ///
  /// [modelPath] 模型文件路径，null则使用默认路径
  /// 返回是否初始化成功
  Future<bool> initialize({String? modelPath}) async {
    if (_isInitialized) return true;
    if (_isLoading) {
      debugPrint('Whisper模型正在加载中...');
      return false;
    }

    _isLoading = true;
    _error = null;

    try {
      // 确定模型路径
      _modelPath = modelPath ?? await _getDefaultModelPath();

      if (_modelPath == null) {
        _error = '模型文件未找到';
        _isLoading = false;
        return false;
      }

      // 检查模型文件是否存在
      final modelFile = File(_modelPath!);
      if (!await modelFile.exists()) {
        _error = '模型文件不存在: $_modelPath';
        _isLoading = false;
        return false;
      }

      // 调用原生代码初始化Whisper
      _progressController.add(0.0);
      final success = await WhisperPlatformChannel.instance.initialize(_modelPath!);
      _progressController.add(1.0);

      if (success) {
        debugPrint('Whisper模型初始化成功: $_modelPath');
        _isInitialized = true;
        _isLoading = false;
        return true;
      } else {
        _error = '原生层初始化失败';
        _isLoading = false;
        return false;
      }

    } catch (e) {
      _error = '初始化失败: $e';
      debugPrint('Whisper初始化错误: $e');
      _isLoading = false;
      return false;
    }
  }

  /// 转写音频文件
  ///
  /// [audioPath] 音频文件路径（支持 wav, mp3, m4a 等）
  /// [language] 语言代码，默认 'zh' (中文)
  ///
  /// 返回转写文本，失败返回 null
  Future<String?> transcribe(
    String audioPath, {
    String language = 'zh',
  }) async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return null;
    }

    try {
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        debugPrint('音频文件不存在: $audioPath');
        return null;
      }

      // 调用原生代码进行转写
      _progressController.add(0.1); // 开始转写

      final result = await WhisperPlatformChannel.instance.transcribe(
        audioPath,
        language: language,
      );

      _progressController.add(1.0); // 完成

      return result;

    } catch (e) {
      debugPrint('Whisper转写错误: $e');
      return null;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    // 调用原生代码释放资源
    await WhisperPlatformChannel.instance.release();
    _isInitialized = false;
    await _progressController.close();
  }

  /// 获取默认模型路径
  ///
  /// 优先顺序：
  /// 1. 应用文档目录/models/ggml-small.bin
  /// 2. 从assets复制后的路径
  Future<String?> _getDefaultModelPath() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${docDir.path}/models');
      // 检查多个可能的模型文件名
      for (final fileName in _modelFileNames) {
        final modelPath = '${modelDir.path}/$fileName';
        final modelFile = File(modelPath);
        if (await modelFile.exists()) {
          debugPrint('找到模型文件: $fileName');
          return modelPath;
        }
      }

      // 如果本地不存在任何模型，尝试从assets复制默认模型
      final defaultPath = '${modelDir.path}/${_modelFileNames.first}';
      await _copyModelFromAssets(defaultPath);

      return await File(defaultPath).exists() ? defaultPath : null;


    } catch (e) {
      debugPrint('获取模型路径失败: $e');
      return null;
    }
  }

  /// 从assets复制模型文件到本地
  ///
  /// 注意：模型文件较大(244MB)，首次复制可能需要时间
  Future<void> _copyModelFromAssets(String targetPath) async {
    try {
      debugPrint('从assets复制Whisper模型...');
      _progressController.add(0);

      // 检查assets中是否存在模型
      final assetData = await rootBundle.load('assets/models/ggml-small.bin');

      if (assetData.lengthInBytes == 0) {
        debugPrint('assets中未找到模型文件');
        return;
      }

      // 写入本地文件
      final bytes = assetData.buffer.asUint8List();
      final file = File(targetPath);
      await file.writeAsBytes(bytes);

      debugPrint('模型文件复制完成: ${bytes.length} bytes');
      _progressController.add(1.0);

    } catch (e) {
      debugPrint('复制模型失败: $e');
      // 模型文件可能不存在于assets中
    }
  }

  /// 从网络下载模型文件
  ///
  /// [onProgress] 进度回调 (0.0 - 1.0)
  /// 返回是否下载成功
  Future<bool> downloadModel({void Function(double progress)? onProgress}) async {
    if (_isDownloading) return false;

    _isDownloading = true;
    _error = null;

    final docDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${docDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final modelPath = '${modelDir.path}/${_modelFileNames.first}';

    // 尝试多个下载源
    for (int i = 0; i < _modelUrls.length; i++) {
      final url = _modelUrls[i];
      try {
        debugPrint('尝试下载模型 (${i + 1}/${_modelUrls.length}): $url');
        _error = null;

        // 使用Dio下载，设置超时
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
        ));

        await dio.download(
          url,
          modelPath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total;
              onProgress?.call(progress);
              _progressController.add(progress);
            }
          },
        );

        // 验证文件
        final file = File(modelPath);
        if (await file.exists()) {
          final size = await file.length();
          if (size > 10 * 1024 * 1024) { // 至少10MB
            _modelPath = modelPath;
            _isDownloading = false;
            debugPrint('模型下载成功: ${(size / 1024 / 1024).toStringAsFixed(1)} MB');
            return true;
          }
        }

        _error = '下载文件验证失败';
      } on DioException catch (e) {
        _error = '下载失败 (${i + 1}/${_modelUrls.length}): ${e.message}';
        debugPrint('下载模型失败 (${i + 1}/${_modelUrls.length}): ${e.message}');
        // 继续尝试下一个URL
        continue;
      } catch (e) {
        _error = '下载失败 (${i + 1}/${_modelUrls.length}): $e';
        debugPrint('下载模型失败 (${i + 1}/${_modelUrls.length}): $e');
        // 继续尝试下一个URL
        continue;
      }
    }

    _isDownloading = false;
    return false;
  }

  /// 检查模型文件是否已下载
  Future<bool> isModelDownloaded() async {
    final path = await _getDefaultModelPath();
    if (path == null) return false;
    return File(path).existsSync();
  }

  /// 获取模型文件大小（用于显示）
  Future<String> getModelSize() async {
    try {
      final path = await _getDefaultModelPath();
      if (path == null) return '未知';

      final file = File(path);
      if (!await file.exists()) return '未下载';

      final bytes = await file.length();
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB';
    } catch (e) {
      return '未知';
    }
  }
}

/// Whisper转写结果
class WhisperResult {
  final String text;
  final String language;
  final double confidence;
  final Duration processingTime;
  final List<WhisperSegment>? segments;

  WhisperResult({
    required this.text,
    required this.language,
    required this.confidence,
    required this.processingTime,
    this.segments,
  });
}

/// 转写分段（带时间戳）
class WhisperSegment {
  final int id;
  final String text;
  final Duration start;
  final Duration end;
  final double confidence;

  WhisperSegment({
    required this.id,
    required this.text,
    required this.start,
    required this.end,
    required this.confidence,
  });
}
