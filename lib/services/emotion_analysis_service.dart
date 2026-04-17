import 'package:flutter/material.dart';

/// 情绪分析服务 - 基于词典和规则的文本情绪识别
///
/// 不使用ML模型，而是通过：
/// 1. 情绪词典匹配
/// 2. 否定词反转
/// 3. 程度词加权
/// 4. 表情符号识别
/// 5. 上下文规则
class EmotionAnalysisService {
  static final EmotionAnalysisService _instance = EmotionAnalysisService._internal();
  factory EmotionAnalysisService() => _instance;
  EmotionAnalysisService._internal();

  // 情绪词典
  late final Map<String, double> _positiveWords;
  late final Map<String, double> _negativeWords;
  late final Set<String> _negationWords;
  late final Map<String, double> _degreeWords;

  bool _initialized = false;

  /// 初始化情绪词典
  void initialize() {
    if (_initialized) return;

    _positiveWords = _buildPositiveDictionary();
    _negativeWords = _buildNegativeDictionary();
    _negationWords = _buildNegationWords();
    _degreeWords = _buildDegreeWords();

    _initialized = true;
    debugPrint('情绪分析服务已初始化');
  }

  /// 分析文本情绪
  EmotionAnalysisResult analyze(String text) {
    if (!_initialized) initialize();
    if (text.isEmpty) {
      return EmotionAnalysisResult(
        primaryEmotion: EmotionType.neutral,
        intensity: 0.0,
        confidence: 0.0,
        allEmotions: {},
      );
    }

    final sentences = _splitSentences(text);
    final emotionScores = <EmotionType, double>{
      EmotionType.joy: 0,
      EmotionType.gratitude: 0,
      EmotionType.excitement: 0,
      EmotionType.sadness: 0,
      EmotionType.anxiety: 0,
      EmotionType.anger: 0,
      EmotionType.frustration: 0,
      EmotionType.neutral: 0,
    };

    int matchedWords = 0;

    for (final sentence in sentences) {
      final result = _analyzeSentence(sentence);
      result.forEach((emotion, score) {
        emotionScores[emotion] = emotionScores[emotion]! + score;
      });
      if (result.values.any((s) => s != 0)) matchedWords++;
    }

    // 添加表情符号分析
    final emojiResult = _analyzeEmojis(text);
    emojiResult.forEach((emotion, score) {
      emotionScores[emotion] = emotionScores[emotion]! + score;
    });

    // 找出主要情绪
    final maxEntry = emotionScores.entries
        .where((e) => e.value > 0)
        .reduce((a, b) => a.value > b.value ? a : b);

    final totalScore = emotionScores.values.reduce((a, b) => a + b);
    final confidence = totalScore > 0 ? maxEntry.value / totalScore : 0;

    return EmotionAnalysisResult(
      primaryEmotion: maxEntry.value > 0 ? maxEntry.key : EmotionType.neutral,
      intensity: (maxEntry.value / sentences.length).clamp(0, 1).toDouble(),
      confidence: confidence.clamp(0, 1).toDouble(),
      allEmotions: emotionScores,
      matchedKeywords: matchedWords,
    );
  }

  /// 分析单句情绪
  Map<EmotionType, double> _analyzeSentence(String sentence) {
    final scores = <EmotionType, double>{
      for (var e in EmotionType.values) e: 0,
    };

    final words = _tokenize(sentence);
    bool negationActive = false;
    double degreeMultiplier = 1.0;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];

      // 检查否定词
      if (_negationWords.contains(word)) {
        negationActive = true;
        continue;
      }

      // 检查程度词
      if (_degreeWords.containsKey(word)) {
        degreeMultiplier = _degreeWords[word]!;
        continue;
      }

      // 检查情绪词
      double? score;
      EmotionType? emotion;

      if (_positiveWords.containsKey(word)) {
        score = _positiveWords[word]!;
        emotion = _mapPositiveToEmotion(word);
      } else if (_negativeWords.containsKey(word)) {
        score = -_negativeWords[word]!;
        emotion = _mapNegativeToEmotion(word);
      }

      if (score != null && emotion != null) {
        // 应用否定反转
        if (negationActive) {
          score = -score;
          negationActive = false;
        }

        // 应用程度加权
        score *= degreeMultiplier;
        degreeMultiplier = 1.0;

        scores[emotion] = scores[emotion]! + score.abs();
      }

      // 否定词影响范围：只影响下一个情绪词
      if (negationActive && i > 0) {
        negationActive = false;
      }
    }

    return scores;
  }

  /// 分析表情符号
  Map<EmotionType, double> _analyzeEmojis(String text) {
    final scores = <EmotionType, double>{};

    // 正向表情
    final positiveEmojis = {
      '😊': EmotionType.joy, '😄': EmotionType.joy, '😃': EmotionType.joy,
      '🙂': EmotionType.joy, '😉': EmotionType.joy, '😍': EmotionType.excitement,
      '🥰': EmotionType.excitement, '😘': EmotionType.excitement,
      '🤗': EmotionType.gratitude, '🙏': EmotionType.gratitude,
      '👍': EmotionType.joy, '❤️': EmotionType.excitement,
      '💪': EmotionType.excitement, '🎉': EmotionType.excitement,
      '✨': EmotionType.excitement, '👏': EmotionType.gratitude,
    };

    // 负向表情
    final negativeEmojis = {
      '😢': EmotionType.sadness, '😭': EmotionType.sadness,
      '😞': EmotionType.sadness, '😔': EmotionType.sadness,
      '😟': EmotionType.anxiety, '😰': EmotionType.anxiety,
      '😥': EmotionType.anxiety, '😨': EmotionType.anxiety,
      '😠': EmotionType.anger, '😡': EmotionType.anger,
      '🤬': EmotionType.anger, '😤': EmotionType.frustration,
      '😩': EmotionType.frustration, '😫': EmotionType.frustration,
      '😣': EmotionType.frustration, '💔': EmotionType.sadness,
    };

    for (final entry in positiveEmojis.entries) {
      if (text.contains(entry.key)) {
        scores[entry.value] = (scores[entry.value] ?? 0) + 0.5;
      }
    }

    for (final entry in negativeEmojis.entries) {
      if (text.contains(entry.key)) {
        scores[entry.value] = (scores[entry.value] ?? 0) + 0.5;
      }
    }

    return scores;
  }

  /// 分句
  List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'[。！？.!?\n]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  /// 分词（简化版）
  List<String> _tokenize(String text) {
    // 简化分词：按字和常见词分割
    final words = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (_isChinese(char) || _isLetter(char)) {
        buffer.write(char);
      } else {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
      }
    }

    if (buffer.isNotEmpty) {
      words.add(buffer.toString());
    }

    // 再提取2-4字的词组
    final additionalWords = <String>[];
    for (int len = 4; len >= 2; len--) {
      for (int i = 0; i <= text.length - len; i++) {
        additionalWords.add(text.substring(i, i + len));
      }
    }

    return [...words, ...additionalWords];
  }

  bool _isChinese(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x4E00 && code <= 0x9FFF;
  }

  bool _isLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  /// 正向情绪映射
  EmotionType _mapPositiveToEmotion(String word) {
    if (word.contains('激动') || word.contains('兴奋') || word.contains('期待')) {
      return EmotionType.excitement;
    }
    if (word.contains('感谢') || word.contains('谢谢') || word.contains('感激')) {
      return EmotionType.gratitude;
    }
    return EmotionType.joy;
  }

  /// 负向情绪映射
  EmotionType _mapNegativeToEmotion(String word) {
    if (word.contains('担心') || word.contains('焦虑') || word.contains('紧张')) {
      return EmotionType.anxiety;
    }
    if (word.contains('生气') || word.contains('愤怒') || word.contains('恼火')) {
      return EmotionType.anger;
    }
    if (word.contains('难过') || word.contains('伤心') || word.contains('悲伤')) {
      return EmotionType.sadness;
    }
    if (word.contains('沮丧') || word.contains('失望') || word.contains('挫败')) {
      return EmotionType.frustration;
    }
    return EmotionType.anxiety;
  }

  /// 构建正向词典
  Map<String, double> _buildPositiveDictionary() {
    return {
      // 开心类
      '开心': 0.8, '高兴': 0.8, '快乐': 0.8, '愉快': 0.7, '喜悦': 0.8,
      '兴奋': 0.9, '激动': 0.9, '欢喜': 0.7, '欢乐': 0.7, '欣慰': 0.6,
      '满足': 0.7, '舒畅': 0.6, '畅快': 0.6, '欣喜': 0.7, '雀跃': 0.8,
      '幸福': 0.9, '甜蜜': 0.7, '美好': 0.6, '棒': 0.6, '赞': 0.6,
      '很好': 0.7, '不错': 0.5, '优秀': 0.7, '出色': 0.7, '完美': 0.9,

      // 期待类
      '期待': 0.7, '盼望': 0.7, '憧憬': 0.7, '向往': 0.6, '希望': 0.6,

      // 感谢类
      '感谢': 0.7, '谢谢': 0.6, '感激': 0.8, '感恩': 0.8, '感动': 0.7,

      // 自信类
      '自信': 0.7, '自豪': 0.7, '骄傲': 0.6, '得意': 0.5, '从容': 0.6,

      // 轻松类
      '轻松': 0.6, '放松': 0.6, '舒适': 0.6, '惬意': 0.6, '悠闲': 0.5,
    };
  }

  /// 构建负向词典
  Map<String, double> _buildNegativeDictionary() {
    return {
      // 焦虑类
      '焦虑': 0.9, '担心': 0.7, '紧张': 0.7, '害怕': 0.8, '恐惧': 0.9,
      '不安': 0.7, '忐忑': 0.7, '慌张': 0.7, '着急': 0.7, '焦躁': 0.8,
      '压力': 0.7, '压抑': 0.7, '负担': 0.6, '困扰': 0.7, '纠结': 0.7,

      // 悲伤类
      '难过': 0.8, '伤心': 0.8, '悲伤': 0.9, '痛苦': 0.9, '难受': 0.8,
      '心疼': 0.7, '委屈': 0.7, '失落': 0.7, '沮丧': 0.8, '消沉': 0.7,
      '郁闷': 0.7, '抑郁': 0.9, '绝望': 0.9, '无助': 0.8, '孤独': 0.7,

      // 愤怒类
      '生气': 0.7, '愤怒': 0.9, '恼火': 0.8, '气愤': 0.8, '火大': 0.7,
      '讨厌': 0.6, '厌恶': 0.7, '反感': 0.6, '憎恨': 0.9,

      // 挫败类
      '失望': 0.7, '挫败': 0.8, '失败': 0.7, '无力': 0.7,
      '疲惫': 0.6, '累': 0.6, '厌倦': 0.7, '厌烦': 0.6, '无聊': 0.5,

      // 负面评价
      '糟糕': 0.7, '差': 0.6, '坏': 0.6, '烂': 0.7, '糟': 0.6,
      '折磨': 0.8, '煎熬': 0.8,
    };
  }

  /// 构建否定词表
  Set<String> _buildNegationWords() {
    return {
      '不', '没', '无', '别', '未', '勿', '莫',
      '不是', '没有', '不要', '不能', '不会', '不该',
    };
  }

  /// 构建程度词表
  Map<String, double> _buildDegreeWords() {
    return {
      '很': 1.5, '非常': 2.0, '特别': 2.0, '十分': 1.8, '极其': 2.5,
      '太': 1.8, '超级': 2.0, '相当': 1.6, '有点': 0.6, '稍微': 0.5,
      '略微': 0.5, '比较': 1.2, '最': 2.0, '更': 1.3, '更加': 1.5,
      '越发': 1.5, '实在': 1.4, '确实': 1.3, '真的': 1.4,
    };
  }

  /// 检测情绪变化
  EmotionChange detectChange(EmotionAnalysisResult previous, EmotionAnalysisResult current) {
    // 情绪类型变化
    if (previous.primaryEmotion != current.primaryEmotion) {
      return EmotionChange(
        type: ChangeType.shift,
        fromEmotion: previous.primaryEmotion,
        toEmotion: current.primaryEmotion,
        significance: _calculateSignificance(previous, current),
      );
    }

    // 强度变化
    final intensityDiff = (current.intensity - previous.intensity).abs();
    if (intensityDiff > 0.3) {
      return EmotionChange(
        type: current.intensity > previous.intensity ? ChangeType.intensify : ChangeType.diminish,
        fromEmotion: previous.primaryEmotion,
        toEmotion: current.primaryEmotion,
        significance: intensityDiff,
      );
    }

    return EmotionChange(type: ChangeType.none);
  }

  double _calculateSignificance(EmotionAnalysisResult a, EmotionAnalysisResult b) {
    // 正向到负向的变化更显著
    final aValence = _getValence(a.primaryEmotion);
    final bValence = _getValence(b.primaryEmotion);

    if ((aValence > 0 && bValence < 0) || (aValence < 0 && bValence > 0)) {
      return 1.0; // 极性翻转，最显著
    }

    return (aValence - bValence).abs();
  }

  double _getValence(EmotionType emotion) {
    switch (emotion) {
      case EmotionType.joy:
      case EmotionType.excitement:
      case EmotionType.gratitude:
        return 1.0;
      case EmotionType.sadness:
      case EmotionType.anxiety:
      case EmotionType.anger:
      case EmotionType.frustration:
        return -1.0;
      case EmotionType.neutral:
        return 0.0;
    }
  }
}

/// 情绪类型
enum EmotionType {
  joy,        // 开心
  excitement, // 兴奋/期待
  gratitude,  // 感激
  sadness,    // 悲伤
  anxiety,    // 焦虑/担心
  anger,      // 愤怒
  frustration,// 沮丧/挫败
  neutral,    // 中性
}

extension EmotionTypeExtension on EmotionType {
  bool get isPositive =>
      this == EmotionType.joy ||
      this == EmotionType.excitement ||
      this == EmotionType.gratitude;

  bool get isNegative =>
      this == EmotionType.sadness ||
      this == EmotionType.anxiety ||
      this == EmotionType.anger ||
      this == EmotionType.frustration;
}

/// 情绪分析结果
class EmotionAnalysisResult {
  final EmotionType primaryEmotion;
  final double intensity;      // 0-1
  final double confidence;     // 0-1
  final Map<EmotionType, double> allEmotions;
  final int? matchedKeywords;

  EmotionAnalysisResult({
    required this.primaryEmotion,
    required this.intensity,
    required this.confidence,
    required this.allEmotions,
    this.matchedKeywords,
  });

  bool get isPositive =>
      primaryEmotion == EmotionType.joy ||
      primaryEmotion == EmotionType.excitement ||
      primaryEmotion == EmotionType.gratitude;

  bool get isNegative =>
      primaryEmotion == EmotionType.sadness ||
      primaryEmotion == EmotionType.anxiety ||
      primaryEmotion == EmotionType.anger ||
      primaryEmotion == EmotionType.frustration;

  String get description {
    final intensityText = intensity > 0.7 ? '很' : intensity > 0.4 ? '有点' : '稍微';
    final emotionText = _emotionDescriptions[primaryEmotion] ?? '平静';
    return '$intensityText$emotionText';
  }

  static final Map<EmotionType, String> _emotionDescriptions = {
    EmotionType.joy: '开心',
    EmotionType.excitement: '兴奋',
    EmotionType.gratitude: '感激',
    EmotionType.sadness: '难过',
    EmotionType.anxiety: '焦虑',
    EmotionType.anger: '生气',
    EmotionType.frustration: '沮丧',
    EmotionType.neutral: '平静',
  };
}

/// 情绪变化
class EmotionChange {
  final ChangeType type;
  final EmotionType? fromEmotion;
  final EmotionType? toEmotion;
  final double significance;  // 0-1

  EmotionChange({
    required this.type,
    this.fromEmotion,
    this.toEmotion,
    this.significance = 0,
  });

  bool get isSignificant => significance > 0.5;
}

enum ChangeType {
  none,       // 无变化
  shift,      // 情绪类型变化
  intensify,  // 情绪增强
  diminish,   // 情绪减弱
}
