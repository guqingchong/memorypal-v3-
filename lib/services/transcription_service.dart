import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'kimi_service.dart';

/// 语音转写服务
///
/// 支持多种转写后端：
/// 1. 云端API（Kimi/其他）- 优先使用，准确率高
/// 2. 本地备用（简静音量检测转写）- 离线时使用
///
/// 注意：真正的本地Whisper需要集成whisper.cpp原生库
class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  final _kimiService = KimiService();
  final _dio = Dio();

  // 音频文件缓存
  final Map<String, File> _audioCache = {};

  /// 转写音频文件
  ///
  /// [audioPath] 音频文件路径
  /// [useLocal] 强制使用本地转写（离线模式）
  ///
  /// 返回转写结果，失败返回null
  Future<TranscriptionResult?> transcribe(
    String audioPath, {
    bool useLocal = false,
  }) async {
    // 优先使用云端API
    if (!useLocal && _kimiService.isAvailable) {
      final result = await _transcribeWithCloud(audioPath);
      if (result != null) return result;
    }

    // 离线模式：使用简静音量检测转写
    return await _transcribeWithLocal(audioPath);
  }

  /// 使用云端API转写
  Future<TranscriptionResult?> _transcribeWithCloud(String audioPath) async {
    try {
      // 使用Kimi API进行语音转写
      // 注意：Kimi API可能需要特定的音频格式和大小限制
      final file = File(audioPath);
      if (!await file.exists()) return null;

      // 检查文件大小（限制25MB）
      final size = await file.length();
      if (size > 25 * 1024 * 1024) {
        debugPrint('音频文件过大，使用本地转写');
        return null;
      }

      // 上传音频并转写
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(audioPath),
        'model': 'whisper-1', // 或其他支持的模型
      });

      final response = await _dio.post(
        'https://api.moonshot.cn/v1/audio/transcriptions',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_kimiService.apiKey}',
          },
        ),
      );

      if (response.statusCode == 200) {
        final text = response.data['text'] as String?;
        if (text != null && text.isNotEmpty) {
          return TranscriptionResult(
            text: text,
            language: 'zh',
            confidence: 0.9,
            isOffline: false,
          );
        }
      }
    } catch (e) {
      debugPrint('云端转写失败: $e');
    }
    return null;
  }

  /// 使用本地方法转写（简化版）
  ///
  /// 由于whisper.cpp原生集成复杂，这里提供：
  /// 1. 简拼音量分析提取关键信息
  /// 2. 标记需要后续云端转写的文件
  Future<TranscriptionResult?> _transcribeWithLocal(String audioPath) async {
    try {
      // 分析音频文件，提取基本信息
      final file = File(audioPath);
      if (!await file.exists()) return null;

      final size = await file.length();
      final duration = await _estimateDuration(audioPath, size);

      // 简拼音量分析（模拟）
      // 实际应该分析音频波形
      final hasVoice = await _analyzeAudioForVoice(audioPath);

      if (!hasVoice) {
        return TranscriptionResult(
          text: '[未检测到有效语音]',
          language: 'zh',
          confidence: 0.0,
          isOffline: true,
          needsCloudTranscription: false,
        );
      }

      // 离线模式：提示用户稍后联网转写
      return TranscriptionResult(
        text: '[离线模式] 录音已保存，时长约${duration.toStringAsFixed(1)}秒。'
            '请连接网络后使用云端转写获取准确结果。',
        language: 'zh',
        confidence: 0.5,
        isOffline: true,
        needsCloudTranscription: true,
        audioPath: audioPath,
      );
    } catch (e) {
      debugPrint('本地转写失败: $e');
      return null;
    }
  }

  /// 估算音频时长
  Future<double> _estimateDuration(String audioPath, int fileSize) async {
    // 简化估算：假设是16kHz, 16bit, 单声道
    // 每秒数据量 = 16000 * 2 = 32000 bytes
    return fileSize / 32000;
  }

  /// 分析音频是否包含语音
  Future<bool> _analyzeAudioForVoice(String audioPath) async {
    // 简化实现：检查文件大小
    // 大于1KB的文件认为可能包含语音
    final file = File(audioPath);
    final size = await file.length();
    return size > 1024;
  }

  /// 批量转写离线录音
  ///
  /// 在恢复网络后调用，转写之前离线保存的录音
  Future<List<TranscriptionResult>> batchTranscribeOffline(
    List<String> audioPaths,
  ) async {
    final results = <TranscriptionResult>[];

    for (final path in audioPaths) {
      final result = await transcribe(path, useLocal: false);
      if (result != null) {
        results.add(result);
      }
      // 添加延迟避免API限流
      await Future.delayed(const Duration(seconds: 1));
    }

    return results;
  }

  /// 检查是否有未转写的离线录音
  Future<List<String>> getPendingOfflineTranscriptions() async {
    // 从数据库查询标记为需要云端转写的录音
    // 简化实现：返回空列表
    return [];
  }
}

/// 转写结果
class TranscriptionResult {
  final String text;
  final String language;
  final double confidence;
  final bool isOffline;
  final bool needsCloudTranscription;
  final String? audioPath;
  final DateTime? timestamp;

  TranscriptionResult({
    required this.text,
    required this.language,
    required this.confidence,
    this.isOffline = false,
    this.needsCloudTranscription = false,
    this.audioPath,
    this.timestamp,
  });
}
