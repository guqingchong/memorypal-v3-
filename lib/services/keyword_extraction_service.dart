import '../models/recording.dart';

/// 关键词提取服务
///
/// 离线状态下从录音的元数据中提取关键词标签
/// 帮助用户在没有网络转写时也能识别录音内容
class KeywordExtractionService {
  static final KeywordExtractionService _instance = KeywordExtractionService._internal();
  factory KeywordExtractionService() => _instance;
  KeywordExtractionService._internal();

  // 商务场景关键词库
  static const Map<String, List<String>> _businessKeywords = {
    '融资': ['融资', '投资', '估值', '股权', 'BP', '路演', 'TS', 'DD', '尽调', 'Term Sheet'],
    '会议': ['会议', '开会', '讨论', '决策', '汇报', '评审', '例会', '周会', '月会'],
    '销售': ['客户', '订单', '合同', '报价', '成交', '业绩', '目标', 'KPI', '销售额'],
    '产品': ['产品', '需求', '功能', '迭代', '原型', 'PRD', '用户', '体验', '设计'],
    '技术': ['技术', '开发', '架构', '代码', 'Bug', '上线', '部署', '服务器', 'API'],
    '管理': ['团队', '管理', '绩效', '考核', '招聘', '人事', '组织架构', '晋升'],
    '财务': ['财务', '预算', '报销', '发票', '税务', '审计', '成本', '利润', '现金流'],
    '法务': ['合同', '法务', '法律', '合规', '诉讼', '仲裁', '知识产权', '商标', '专利'],
  };

  // 常见人名姓氏（中文）
  static const List<String> _commonSurnames = [
    '李', '王', '张', '刘', '陈', '杨', '赵', '黄', '周', '吴',
    '徐', '孙', '胡', '朱', '高', '林', '何', '郭', '马', '罗',
    '梁', '宋', '郑', '谢', '韩', '唐', '冯', '于', '董', '萧',
  ];

  // 时间相关关键词（预留）
  // static const List<String> _timeKeywords = [...];

  // 地点相关关键词
  static const List<String> _locationKeywords = [
    '公司', '办公室', '会议室', '咖啡厅', '餐厅', '酒店', '机场',
    '车站', '家里', '客户', '现场', '工地', '工厂', '实验室',
  ];

  /// 从录音中提取关键词标签
  ///
  /// [recording] 录音对象
  /// [fileName] 原始文件名（如果有）
  /// 返回提取的关键词标签列表
  List<String> extractKeywordsFromRecording(Recording recording, {String? fileName}) {
    final tags = <String>[];
    final textToAnalyze = StringBuffer();

    // 1. 分析文件名
    if (fileName != null) {
      textToAnalyze.writeln(fileName);
    }

    // 2. 分析文件路径
    textToAnalyze.writeln(recording.filePath);

    // 3. 分析地点名称
    if (recording.locationName != null && recording.locationName!.isNotEmpty) {
      textToAnalyze.writeln(recording.locationName);
      // 添加地点类型标签
      tags.addAll(_extractLocationType(recording.locationName!));
    }

    // 4. 分析时间信息
    final timeContext = _analyzeTimeContext(recording.startTime);
    tags.addAll(timeContext.tags);
    textToAnalyze.writeln(timeContext.description);

    // 5. 提取商务关键词
    tags.addAll(_extractBusinessKeywords(textToAnalyze.toString()));

    // 6. 提取可能的姓名
    tags.addAll(_extractPossibleNames(textToAnalyze.toString()));

    // 7. 去重并限制数量
    return tags.toSet().take(5).toList();
  }

  /// 生成离线模式下的描述文本
  ///
  /// 即使无法转写，也给用户一个有意义的描述
  String generateOfflineDescription(Recording recording, {String? fileName}) {
    final buffer = StringBuffer();

    // 基本信息
    buffer.writeln('[离线模式 - 基础信息识别]');
    buffer.writeln();

    // 时间信息
    final timeDesc = _getTimeDescription(recording.startTime);
    buffer.writeln('⏰ 时间: $timeDesc');

    // 时长信息
    final duration = recording.durationSeconds;
    if (duration > 0) {
      if (duration < 60) {
        buffer.writeln('⏱️ 时长: ${duration}秒');
      } else {
        buffer.writeln('⏱️ 时长: ${(duration / 60).ceil()}分钟');
      }
    }

    // 地点信息
    if (recording.locationName != null && recording.locationName!.isNotEmpty) {
      buffer.writeln('📍 地点: ${recording.locationName}');
    }

    // 提取的关键词
    final keywords = extractKeywordsFromRecording(recording, fileName: fileName);
    if (keywords.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('🏷️ 识别标签: ${keywords.join(', ')}');
    }

    // 场景推测
    final sceneGuess = _guessScene(recording, keywords);
    if (sceneGuess != null) {
      buffer.writeln();
      buffer.writeln('💡 场景推测: $sceneGuess');
    }

    buffer.writeln();
    buffer.writeln('📝 提示: 连接网络后可使用云端转写获取完整内容');

    return buffer.toString();
  }

  /// 提取商务关键词
  List<String> _extractBusinessKeywords(String text) {
    final foundTags = <String>[];
    final lowerText = text.toLowerCase();

    for (final entry in _businessKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerText.contains(keyword.toLowerCase())) {
          foundTags.add(entry.key);
          break;
        }
      }
    }

    return foundTags;
  }

  /// 提取可能的姓名（基于上下文模式）
  List<String> _extractPossibleNames(String text) {
    final names = <String>[];

    // 简单的模式匹配：姓氏 + "总" / "经理" / "先生" / "女士"
    for (final surname in _commonSurnames) {
      // 李总、王经理 等模式
      final patterns = [
        '$surname总',
        '$surname经理',
        '$surname老师',
        '$surname工',
      ];

      for (final pattern in patterns) {
        if (text.contains(pattern)) {
          names.add(pattern);
          break; // 每个姓氏只加一次
        }
      }
    }

    return names.take(3).toList(); // 限制数量
  }

  /// 提取地点类型
  List<String> _extractLocationType(String location) {
    final types = <String>[];

    for (final keyword in _locationKeywords) {
      if (location.contains(keyword)) {
        types.add(keyword);
      }
    }

    return types;
  }

  /// 分析时间上下文
  _TimeContext _analyzeTimeContext(DateTime time) {
    final hour = time.hour;
    final weekday = time.weekday;

    String description;
    List<String> tags = [];

    // 时间段
    if (hour >= 6 && hour < 12) {
      description = '上午${hour}点';
      tags.add('上午');
    } else if (hour >= 12 && hour < 14) {
      description = '中午';
      tags.add('中午');
    } else if (hour >= 14 && hour < 18) {
      description = '下午${hour - 12}点';
      tags.add('下午');
    } else if (hour >= 18 && hour < 22) {
      description = '晚上${hour - 12}点';
      tags.add('晚上');
    } else {
      description = '深夜';
      tags.add('深夜');
    }

    // 工作日/周末
    if (weekday <= 5) {
      description += ' 工作日';
      tags.add('工作日');
    } else {
      description += ' 周末';
      tags.add('周末');
    }

    return _TimeContext(description: description, tags: tags);
  }

  /// 获取时间描述
  String _getTimeDescription(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordingDay = DateTime(time.year, time.month, time.day);
    final difference = today.difference(recordingDay).inDays;

    String dayDesc;
    if (difference == 0) {
      dayDesc = '今天';
    } else if (difference == 1) {
      dayDesc = '昨天';
    } else if (difference < 7) {
      dayDesc = _getWeekdayName(time.weekday);
    } else {
      dayDesc = '${time.month}月${time.day}日';
    }

    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '$dayDesc $hour:$minute';
  }

  /// 获取星期名称
  String _getWeekdayName(int weekday) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[weekday - 1];
  }

  /// 推测场景
  String? _guessScene(Recording recording, List<String> keywords) {
    // 基于关键词组合推测场景
    final keywordSet = keywords.toSet();

    if (keywordSet.contains('融资') || keywordSet.contains('投资')) {
      return '可能与融资或投资相关';
    }

    if (keywordSet.contains('会议') || keywordSet.contains('会议室')) {
      return '可能是会议记录';
    }

    if (keywordSet.contains('客户') || keywordSet.contains('销售')) {
      return '可能是客户沟通';
    }

    if (recording.isVoiceNote) {
      return '语音备忘';
    }

    // 基于时间推测
    final hour = recording.startTime.hour;
    if (hour >= 9 && hour <= 18 && recording.startTime.weekday <= 5) {
      return '可能是工作相关内容';
    }

    if (keywordSet.isEmpty) {
      return null;
    }

    return '可能是${keywords.first}相关内容';
  }

  /// 生成智能标题
  ///
  /// 基于录音的元数据生成人类可读的标题
  String generateSmartTitle(Recording recording, {List<String>? keywords}) {
    keywords ??= extractKeywordsFromRecording(recording);

    final buffer = StringBuffer();

    // 1. 时间前缀
    final timeDesc = _getShortTimeDescription(recording.startTime);
    buffer.write(timeDesc);

    // 2. 场景关键词
    if (keywords.isNotEmpty) {
      // 选择最相关的1-2个关键词
      final mainKeywords = keywords.take(2).join('');
      buffer.write(' · $mainKeywords');
    }

    // 3. 类型后缀
    if (recording.isVoiceNote) {
      buffer.write(' · 备忘');
    } else if (recording.durationSeconds > 300) {
      buffer.write(' · 录音');
    }

    return buffer.toString();
  }

  /// 获取简短时间描述
  String _getShortTimeDescription(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordingDay = DateTime(time.year, time.month, time.day);
    final difference = today.difference(recordingDay).inDays;

    if (difference == 0) {
      // 今天 - 显示时段
      final hour = time.hour;
      if (hour >= 6 && hour < 12) return '今早';
      if (hour >= 12 && hour < 14) return '中午';
      if (hour >= 14 && hour < 18) return '下午';
      return '今晚';
    } else if (difference == 1) {
      return '昨天';
    } else if (difference < 7) {
      return _getWeekdayName(time.weekday);
    } else {
      return '${time.month}/${time.day}';
    }
  }
}

class _TimeContext {
  final String description;
  final List<String> tags;

  _TimeContext({required this.description, required this.tags});
}
