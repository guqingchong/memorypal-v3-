import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/recording.dart';
import 'kimi_service.dart';
import 'keyword_extraction_service.dart';
import 'whisper_local_service.dart';
import 'transcription_status_service.dart';

/// 语音转写服务
///
/// 转写架构：
/// 1. 本地Whisper转写 - 离线语音转文字
/// 2. Kimi云端分析 - 转写后的文本深度分析（待办提取等）
/// 3. 本地备用（智能关键词提取）- 降级方案
class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  final _kimiService = KimiService();
  final _dio = Dio();
  final _keywordService = KeywordExtractionService();
  final _whisperService = WhisperLocalService();
  final _statusService = TranscriptionStatusService();

  /// 转写音频文件
  ///
  /// 转写流程：
  /// 1. 本地Whisper转写（语音→文字）
  /// 2. Kimi云端分析（提取待办、摘要等）
  /// 3. 降级：智能关键词提取
  ///
  /// [audioPath] 音频文件路径
  /// [recordingMeta] 录音元数据（用于关键词提取降级）
  /// [skipKimiAnalysis] 是否跳过Kimi深度分析
  ///
  /// 返回转写结果，失败返回null
  Future<TranscriptionResult?> transcribe(
    String audioPath, {
    Recording? recordingMeta,
    bool skipKimiAnalysis = false,
  }) async {
    // Step 1: 本地Whisper转写
    var result = await _transcribeWithWhisper(audioPath);

    // Step 2: 使用Kimi进行深度分析（如果Whisper成功且未跳过）
    if (result != null && !skipKimiAnalysis && _kimiService.isAvailable) {
      result = await _enrichWithKimi(result);
    }

    // Step 3: 降级到关键词提取
    if (result == null) {
      result = await _transcribeWithLocal(audioPath, recordingMeta: recordingMeta);
    }

    return result;
  }

  /// 使用本地Whisper模型转写
  ///
  /// 调用本地 whisper.cpp 进行语音转文字
  /// 需要提前下载模型文件 ggml-small.bin
  Future<TranscriptionResult?> _transcribeWithWhisper(String audioPath) async {
    final recordingId = audioPath.hashCode.toString();
    final fileName = audioPath.split('/').last;

    try {
      // 通知状态：开始转写
      _statusService.startTranscription(recordingId, fileName);
      _statusService.updateStep(recordingId, TranscriptionStep.loadingModel,
          message: '加载Whisper模型...');

      // 模拟加载模型时间（实际集成时可移除）
      await Future.delayed(const Duration(milliseconds: 500));

      _statusService.updateStep(recordingId, TranscriptionStep.transcribing,
          message: '正在转写音频...');

      // 调用Whisper本地服务
      final text = await _whisperService.transcribe(audioPath, language: 'zh');

      if (text != null && text.isNotEmpty) {
        debugPrint('Whisper转写成功: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');

        _statusService.completeTranscription(recordingId, text,
            tags: ['本地转写', 'Whisper']);

        return TranscriptionResult(
          text: text,
          language: 'zh',
          confidence: 0.85,
          isOffline: true,
          needsCloudTranscription: false, // Whisper已完成转写
          audioPath: audioPath,
          tags: ['本地转写'],
        );
      } else {
        _statusService.failTranscription(recordingId, '转写结果为空');
      }
    } catch (e) {
      debugPrint('Whisper转写失败: $e');
      _statusService.failTranscription(recordingId, e.toString());
    }

    // 转写失败，降级到关键词提取
    debugPrint('Whisper转写失败，降级到关键词提取');
    return null;
  }

  /// 使用Kimi分析转写文本（提取待办、摘要等）
  ///
  /// 在Whisper完成基础转写后，调用Kimi进行深度分析
  Future<TranscriptionResult?> _enrichWithKimi(TranscriptionResult whisperResult) async {
    if (!_kimiService.isAvailable) {
      // Kimi不可用，直接返回Whisper结果
      return whisperResult;
    }

    try {
      // 使用Kimi提取待办事项
      final todos = await extractTodosFromTranscript(whisperResult.text);

      // TODO: 可以在这里添加更多Kimi分析：
      // - 生成摘要
      // - 提取关键词
      // - 情感分析
      // - 主题分类

      debugPrint('Kimi分析完成，提取到 ${todos.length} 个待办');

      // 返回 enriched 结果
      return TranscriptionResult(
        text: whisperResult.text,
        language: whisperResult.language,
        confidence: whisperResult.confidence,
        isOffline: whisperResult.isOffline,
        needsCloudTranscription: false,
        audioPath: whisperResult.audioPath,
        tags: [...whisperResult.tags, 'AI分析'],
        // TODO: 添加待办列表到结果
      );

    } catch (e) {
      debugPrint('Kimi分析失败: $e');
      // Kimi分析失败，返回原始Whisper结果
      return whisperResult;
    }
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

  /// 批量转写录音（待Whisper集成后使用）
  ///
  /// TODO: 集成本地Whisper后，可批量处理录音
  Future<List<TranscriptionResult>> batchTranscribe(
    List<String> audioPaths,
  ) async {
    final results = <TranscriptionResult>[];

    for (final path in audioPaths) {
      final result = await transcribe(path);
      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }

  /// 检查是否有未转写的离线录音
  Future<List<String>> getPendingOfflineTranscriptions() async {
    // 从数据库查询标记为需要云端转写的录音
    // 简化实现：返回空列表
    return [];
  }

  /// 获取转写状态服务（用于UI监听）
  TranscriptionStatusService get statusService => _statusService;
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
