import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// 模型下载管理服务
/// 负责管理AI模型的下载、缓存和版本控制
class ModelDownloadService {
  static const MethodChannel _channel = MethodChannel('com.memorypal/model');
  static final ModelDownloadService _instance = ModelDownloadService._internal();

  factory ModelDownloadService() => _instance;
  ModelDownloadService._internal();

  // 模型存储目录
  Directory? _modelDir;

  // 下载进度回调
  Function(String modelName, double progress)? onProgress;
  Function(String modelName)? onComplete;
  Function(String modelName, String error)? onError;

  /// 初始化模型目录
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _modelDir = Directory('${appDir.path}/models');
    if (!await _modelDir!.exists()) {
      await _modelDir!.create(recursive: true);
    }
  }

  /// 获取模型文件路径
  String? getModelPath(String modelFileName) {
    if (_modelDir == null) return null;
    final path = '${_modelDir!.path}/$modelFileName';
    return File(path).existsSync() ? path : null;
  }

  /// 检查模型是否已下载
  bool isModelDownloaded(String modelFileName) {
    final path = getModelPath(modelFileName);
    if (path == null) return false;
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// 获取模型文件大小（MB）
  Future<double> getModelSize(String modelFileName) async {
    final path = getModelPath(modelFileName);
    if (path == null) return 0;
    final file = File(path);
    if (!await file.exists()) return 0;
    return file.lengthSync() / (1024 * 1024);
  }

  /// 下载模型（支持断点续传）
  Future<bool> downloadModel({
    required String modelName,
    required String modelFileName,
    required String downloadUrl,
    String? expectedChecksum,
  }) async {
    if (_modelDir == null) await initialize();

    final filePath = '${_modelDir!.path}/$modelFileName';
    final file = File(filePath);

    try {
      // 检查是否已存在完整文件
      if (await file.exists() && await _verifyChecksum(filePath, expectedChecksum)) {
        onComplete?.call(modelName);
        return true;
      }

      // 开始下载
      final request = http.Request('GET', Uri.parse(downloadUrl));

      // 支持断点续传
      int startByte = 0;
      if (await file.exists()) {
        startByte = await file.length();
        request.headers['Range'] = 'bytes=$startByte-';
      }

      final response = await http.Client().send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      final totalBytes = response.contentLength != null
          ? startByte + response.contentLength!
          : null;
      int receivedBytes = startByte;

      // 以追加模式写入文件
      final sink = file.openWrite(mode: FileMode.append);

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes != null) {
          final progress = receivedBytes / totalBytes;
          onProgress?.call(modelName, progress);
        }
      }

      await sink.close();

      // 验证校验和
      if (expectedChecksum != null && !await _verifyChecksum(filePath, expectedChecksum)) {
        await file.delete();
        throw Exception('Checksum verification failed');
      }

      onComplete?.call(modelName);
      return true;
    } catch (e) {
      onError?.call(modelName, e.toString());
      return false;
    }
  }

  /// 验证文件校验和
  Future<bool> _verifyChecksum(String filePath, String? expectedChecksum) async {
    if (expectedChecksum == null) return true;
    // TODO: 实现SHA256校验
    return true;
  }

  /// 删除模型
  Future<bool> deleteModel(String modelFileName) async {
    final path = getModelPath(modelFileName);
    if (path == null) return false;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取所有可用磁盘空间（MB）
  Future<double> getAvailableSpace() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStorageInfo');
      if (result != null) {
        return (result['availableBytes'] as int) / (1024 * 1024);
      }
    } catch (e) {
      print('获取存储空间失败: $e');
    }
    return 0;
  }

  /// 获取已下载模型列表
  Future<List<DownloadedModel>> getDownloadedModels() async {
    if (_modelDir == null) await initialize();

    final models = <DownloadedModel>[];
    final files = await _modelDir!.list().toList();

    for (final file in files) {
      if (file is File) {
        final stat = await file.stat();
        models.add(DownloadedModel(
          fileName: file.path.split('/').last,
          fileSize: stat.size / (1024 * 1024),
          downloadDate: stat.modified,
        ));
      }
    }

    return models;
  }
}

/// 已下载模型信息
class DownloadedModel {
  final String fileName;
  final double fileSize;
  final DateTime downloadDate;

  DownloadedModel({
    required this.fileName,
    required this.fileSize,
    required this.downloadDate,
  });
}
