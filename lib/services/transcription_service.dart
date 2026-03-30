import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/recording.dart';
import 'kimi_service.dart';
import 'keyword_extraction_service.dart';

/// 语音转写服务
///
/// 支持多种转写后端：
/// 1. 云端API（Kimi/其他）- 优先使用，准确率高
/// 2. 本地备用（智能关键词提取）- 离线时使用，从元数据提取标签
///
/// 注意：真正的本地Whisper需要集成whisper.cpp原生库
class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  final _kimiService = KimiService();
  final _dio = Dio();
  final _keywordService = KeywordExtractionService();

  // 音频文件缓存
  final Map<String, File> _audioCache = {};

  /// 转写音频文件
  ///
  /// [audioPath] 音频文件路径
  /// [useLocal] 强制使用本地转写（离线模式）
  /// [recordingMeta] 录音元数据（用于离线模式提取关键词）
  ///
  /// 返回转写结果，失败返回null
  Future<TranscriptionResult?> transcribe(
    String audioPath, {
    bool useLocal = false,
    Recording? recordingMeta,
  }) async {
    // 优先使用云端API
    if (!useLocal && _kimiService.isAvailable) {
      final result = await _transcribeWithCloud(audioPath);
      if (result != null) return result;
    }

    // 离线模式：使用智能关键词提取
    return await _transcribeWithLocal(audioPath, recordingMeta: recordingMeta);
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

  /// 使用本地方法转写（智能关键词提取版）
  ///
  /// 离线模式下，从录音的元数据中提取关键词标签
  /// 帮助用户在没有网络时也能识别录音内容
  Future<TranscriptionResult?> _transcribeWithLocal(String audioPath, {Recording? recordingMeta}) async {
    try {
      // 分析音频文件，提取基本信息
      final file = File(audioPath);
      if (!await file.exists()) return null;

      final size = await file.length();
      final duration = await _estimateDuration(audioPath, size);

      // 简拼音量分析
      final hasVoice = await _analyzeAudioForVoice(audioPath);

      if (!hasVoice) {
        return TranscriptionResult(
          text: '[未检测到有效语音]',
          language: 'zh',
          confidence: 0.0,
          isOffline: true,
          needsCloudTranscription: false,
          tags: ['无效录音'],
        );
      }

      // 如果有录音元数据，进行智能关键词提取
      List<String> extractedTags = [];
      String smartDescription;

      if (recordingMeta != null) {
        // 提取关键词标签
        extractedTags = _keywordService.extractKeywordsFromRecording(
          recordingMeta,
          fileName: file.path.split('/').last,
        );

        // 生成智能描述
        smartDescription = _keywordService.generateOfflineDescription(
          recordingMeta,
          fileName: file.path.split('/').last,
        );
      } else {
        // 没有元数据时的默认描述
        smartDescription = _generateBasicOfflineDescription(audioPath, duration);
        extractedTags = ['离线录音'];
      }

      return TranscriptionResult(
        text: smartDescription,
        language: 'zh',
        confidence: 0.6,
        isOffline: true,
        needsCloudTranscription: true,
        audioPath: audioPath,
        tags: extractedTags,
        durationSeconds: duration.toInt(),
      );
    } catch (e) {
      debugPrint('本地转写失败: $e');
      return null;
    }
  }

  /// 生成基础离线描述（无元数据时）
  String _generateBasicOfflineDescription(String audioPath, double duration) {
    final fileName = audioPath.split('/').last;
    final buffer = StringBuffer();

    buffer.writeln('[离线模式 - 录音已保存]');
    buffer.writeln();
    buffer.writeln('📁 文件: $fileName');
    buffer.writeln('⏱️ 时长: ${duration.toStringAsFixed(1)}秒');
    buffer.writeln();
    buffer.writeln('🏷️ 识别标签: 离线录音');
    buffer.writeln();
    buffer.writeln('💡 提示: 连接网络后可使用云端转写获取完整内容');

    return buffer.toString();
  }

  /// 从录音元数据提取关键词（供外部调用）
  List<String> extractKeywords(Recording recording) {
    return _keywordService.extractKeywordsFromRecording(recording);
  }

  /// 生成智能标题（供外部调用）
  String generateSmartTitle(Recording recording, {List<String>? keywords}) {
    return _keywordService.generateSmartTitle(recording, keywords: keywords);
  }

  /// 从转写文本中提取待办事项
  ///
  /// 使用Kimi API分析文本，自动识别待办事项
  Future<List<ExtractedTodo>> extractTodosFromTranscript(String transcript) async {
    if (!_kimiService.isAvailable) {
      return [];
    }

    try {
      final response = await _dio.post(
        'https://api.moonshot.cn/v1/chat/completions',
        data: {
          'model': 'moonshot-v1-8k',
          'messages': [
            {
              'role': 'system',
              'content': '''分析以下录音转写文本，提取其中包含的待办事项、任务、约定或需要后续跟进的内容。

输出JSON格式：
{
  "todos": [
    {
      "content": "待办内容",
      "type": "task|meeting|reminder|deadline",
      "priority": "high|medium|low",
      "context": "上下文原文片段"
    }
  ]
}

规则：
1. 只提取明确提到的待办，不要推测
2. 优先提取带有"要"、"需要"、"记得"、"别忘了"、"明天"、"下周"等关键词的内容
3. 会议安排、约定时间也算待办
4. 如果没有待办，返回空数组
5. priority根据紧急程度判断：high-紧急/今天/明天，medium-近期，low-远期/模糊'''
            },
            {
              'role': 'user',
              'content': transcript
            }
          ],
          'temperature': 0.3,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_kimiService.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final content = response.data['choices'][0]['message']['content'] as String;
        return _parseExtractedTodos(content);
      }
    } catch (e) {
      debugPrint('提取待办失败: $e');
    }

    return [];
  }

  /// 解析提取的待办事项
  List<ExtractedTodo> _parseExtractedTodos(String jsonStr) {
    try {
      // 提取JSON部分
      final jsonStart = jsonStr.indexOf('{');
      final jsonEnd = jsonStr.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) return [];

      final json = jsonDecode(jsonStr.substring(jsonStart, jsonEnd + 1));
      final todos = json['todos'] as List<dynamic>?;

      if (todos == null) return [];

      return todos.map((t) => ExtractedTodo(
        content: t['content'] as String,
        type: t['type'] as String? ?? 'task',
        priority: t['priority'] as String? ?? 'medium',
        context: t['context'] as String?,
      )).toList();
    } catch (e) {
      debugPrint('解析待办失败: $e');
      return [];
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
  final List<String> tags;  // 离线模式提取的关键词标签
  final int? durationSeconds;  // 音频时长（秒）

  TranscriptionResult({
    required this.text,
    required this.language,
    required this.confidence,
    this.isOffline = false,
    this.needsCloudTranscription = false,
    this.audioPath,
    this.timestamp,
    this.tags = const [],
    this.durationSeconds,
  });
}

/// 提取的待办事项
class ExtractedTodo {
  final String content;
  final String type;  // task, meeting, reminder, deadline
  final String priority;  // high, medium, low
  final String? context;  // 上下文原文片段
  bool isSelected;  // 是否被用户选中添加

  ExtractedTodo({
    required this.content,
    required this.type,
    required this.priority,
    this.context,
    this.isSelected = true,  // 默认选中
  });

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'type': type,
      'priority': priority,
      'context': context,
    };
  }
}
