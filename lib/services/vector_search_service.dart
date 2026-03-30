import 'dart:math';
import '../models/note.dart';
import '../models/recording.dart';
import 'database_service.dart';

/// 查询意图类型
enum QueryIntent {
  searchTodos, // 查找待办
  searchByTime, // 按时间查找
  searchByPerson, // 按人查找
  searchByTopic, // 按主题查找
  searchFiles, // 查找文件
  generalQuestion, // 一般问题
}

/// 语义搜索服务
///
/// 使用关键词扩展和同义词匹配来模拟语义理解
/// 未来可升级为真正的向量搜索（使用Chroma等向量数据库）
class VectorSearchService {
  static final VectorSearchService _instance = VectorSearchService._internal();
  factory VectorSearchService() => _instance;
  VectorSearchService._internal();

  final DatabaseService _databaseService = DatabaseService();

  /// 同义词词典
  final Map<String, List<String>> _synonyms = {
    '会议': ['开会', '讨论', '商谈', '座谈', '会晤'],
    '工作': ['项目', '任务', '业务', '职责', '职业'],
    '生活': ['日常', '私事', '家庭', '个人'],
    '重要': ['关键', '紧急', '重大', '核心', '主要'],
    '计划': ['安排', '打算', '规划', '日程', '行程'],
    '问题': ['困难', 'bug', '错误', '故障', '麻烦'],
    '想法': ['思路', '观点', '见解', '灵感', '构思'],
    '客户': ['顾客', '用户', '甲方', '合作方'],
    '报告': ['汇报', '总结', '文档', '材料', 'PPT'],
    '时间': ['日期', '时刻', '期限', ' deadline'],
    '地点': ['位置', '场所', '地址', '地方'],
    '人员': ['同事', '团队', '成员', '伙伴', '人员'],
  };

  /// 解析查询意图
  QueryIntent _parseIntent(String query) {
    final lower = query.toLowerCase();

    if (lower.contains('待办') || lower.contains('todo') ||
        lower.contains('要做') || lower.contains('任务')) {
      return QueryIntent.searchTodos;
    }

    if (lower.contains('今天') || lower.contains('昨天') ||
        lower.contains('上周') || lower.contains('最近') ||
        lower.contains('哪天') || lower.contains('什么时候')) {
      return QueryIntent.searchByTime;
    }

    if (lower.contains('和') || lower.contains('聊') ||
        lower.contains('讨论') || lower.contains('说')) {
      return QueryIntent.searchByPerson;
    }

    if (lower.contains('文件') || lower.contains('文档') ||
        lower.contains('ppt') || lower.contains('pdf')) {
      return QueryIntent.searchFiles;
    }

    if (lower.contains('项目') || lower.contains('会议') ||
        lower.contains('工作')) {
      return QueryIntent.searchByTopic;
    }

    return QueryIntent.generalQuestion;
  }

  /// 语义搜索主方法
  ///
  /// 返回搜索结果，按相关性排序
  Future<SearchResult> semanticSearch(String query, {int limit = 10}) async {
    final intent = _parseIntent(query);

    // 扩展查询关键词
    final expandedKeywords = _expandQuery(query);

    // 获取所有数据
    final recordings = await _databaseService.getRecordings(limit: 100);
    final notes = await _databaseService.getNotes(limit: 100);

    // 计算相关性分数
    final scoredRecordings = <ScoredRecording>[];
    final scoredNotes = <ScoredNote>[];

    for (final r in recordings) {
      final score = _calculateRelevance(r, query, expandedKeywords, intent);
      if (score > 0) {
        scoredRecordings.add(ScoredRecording(recording: r, score: score));
      }
    }

    for (final n in notes) {
      final score = _calculateNoteRelevance(n, query, expandedKeywords, intent);
      if (score > 0) {
        scoredNotes.add(ScoredNote(note: n, score: score));
      }
    }

    // 按分数排序
    scoredRecordings.sort((a, b) => b.score.compareTo(a.score));
    scoredNotes.sort((a, b) => b.score.compareTo(a.score));

    return SearchResult(
      recordings: scoredRecordings.take(limit).toList(),
      notes: scoredNotes.take(limit).toList(),
      intent: intent,
      expandedKeywords: expandedKeywords,
    );
  }

  /// 扩展查询（添加同义词）
  Set<String> _expandQuery(String query) {
    final keywords = <String>{};
    final words = query.split(RegExp(r'[\s,，。]+'));

    for (final word in words) {
      if (word.isEmpty) continue;
      keywords.add(word);

      // 添加同义词
      for (final entry in _synonyms.entries) {
        if (entry.key == word || entry.value.contains(word)) {
          keywords.add(entry.key);
          keywords.addAll(entry.value);
        }
      }
    }

    return keywords;
  }

  /// 计算录音相关性分数
  double _calculateRelevance(
    Recording recording,
    String originalQuery,
    Set<String> keywords,
    QueryIntent intent,
  ) {
    double score = 0.0;
    final text = '${recording.transcript ?? ''} ${recording.summary ?? ''}';

    if (text.isEmpty) return 0.0;

    // 1. 精确匹配加分
    if (text.contains(originalQuery)) {
      score += 10.0;
    }

    // 2. 关键词匹配
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        score += 2.0;
        // 标题匹配权重更高
        if (recording.summary?.contains(keyword) == true) {
          score += 3.0;
        }
      }
    }

    // 3. 时间相关性（根据意图）
    if (intent == QueryIntent.searchByTime) {
      final now = DateTime.now();
      final age = now.difference(recording.startTime);
      if (age.inDays <= 7) {
        score += 5.0;
      } else if (age.inDays <= 30) {
        score += 2.0;
      }
    }

    // 4. 新鲜度奖励（所有查询都适用）
    final age = DateTime.now().difference(recording.startTime);
    if (age.inDays <= 1) {
      score += 1.0;
    } else if (age.inDays <= 7) {
      score += 0.5;
    }

    return score;
  }

  /// 计算笔记相关性分数
  double _calculateNoteRelevance(
    Note note,
    String originalQuery,
    Set<String> keywords,
    QueryIntent intent,
  ) {
    double score = 0.0;
    final text = '${note.title} ${note.content} ${note.transcript ?? ''}';

    // 1. 精确匹配加分
    if (text.contains(originalQuery)) {
      score += 10.0;
    }

    // 2. 关键词匹配
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        score += 2.0;
        // 标题匹配权重更高
        if (note.title.contains(keyword)) {
          score += 5.0;
        }
      }
    }

    // 3. 时间相关性
    if (intent == QueryIntent.searchByTime) {
      final now = DateTime.now();
      final age = now.difference(note.createdAt);
      if (age.inDays <= 7) {
        score += 5.0;
      }
    }

    return score;
  }

  /// 智能回答生成
  ///
  /// 根据搜索结果生成自然语言回答
  String generateAnswer(String query, SearchResult result) {
    final buffer = StringBuffer();

    switch (result.intent) {
      case QueryIntent.searchTodos:
        buffer.writeln('📋 待办事项搜索结果：\n');
        break;
      case QueryIntent.searchByTime:
        buffer.writeln('📅 时间相关记录：\n');
        break;
      case QueryIntent.searchByPerson:
        buffer.writeln('👥 相关人员记录：\n');
        break;
      case QueryIntent.searchFiles:
        buffer.writeln('📁 文件搜索结果：\n');
        break;
      case QueryIntent.searchByTopic:
        buffer.writeln('📌 主题相关记录：\n');
        break;
      case QueryIntent.generalQuestion:
        buffer.writeln('🔍 搜索结果：\n');
        break;
    }

    final totalResults = result.recordings.length + result.notes.length;
    if (totalResults == 0) {
      buffer.writeln('没有找到相关记录。\n');
      buffer.writeln('建议：');
      buffer.writeln('• 尝试使用不同的关键词');
      buffer.writeln('• 检查是否有相关录音或笔记');
      return buffer.toString();
    }

    buffer.writeln('找到 $totalResults 条相关记录\n');

    // 显示最相关的结果
    if (result.recordings.isNotEmpty) {
      buffer.writeln('🎙️ 相关录音：');
      for (final scored in result.recordings.take(5)) {
        final r = scored.recording;
        buffer.writeln('• ${r.startTime.month}/${r.startTime.day} '
            '${r.startTime.hour}:${r.startTime.minute.toString().padLeft(2, '0')} '
            '(相关度: ${(scored.score).toInt()})');
        if (r.transcript != null && r.transcript!.isNotEmpty) {
          final preview = r.transcript!.length > 40
              ? '${r.transcript!.substring(0, 40)}...'
              : r.transcript;
          buffer.writeln('  "$preview"');
        }
      }
      buffer.writeln('');
    }

    if (result.notes.isNotEmpty) {
      buffer.writeln('📝 相关笔记：');
      for (final scored in result.notes.take(5)) {
        final n = scored.note;
        buffer.writeln('• ${n.title} (${n.createdAt.month}/${n.createdAt.day}) '
            '(相关度: ${(scored.score).toInt()})');
      }
    }

    return buffer.toString();
  }
}

/// 搜索结果
class SearchResult {
  final List<ScoredRecording> recordings;
  final List<ScoredNote> notes;
  final QueryIntent intent;
  final Set<String> expandedKeywords;

  SearchResult({
    required this.recordings,
    required this.notes,
    required this.intent,
    required this.expandedKeywords,
  });
}

/// 带分数的录音
class ScoredRecording {
  final Recording recording;
  final double score;

  ScoredRecording({
    required this.recording,
    required this.score,
  });
}

/// 带分数的笔记
class ScoredNote {
  final Note note;
  final double score;

  ScoredNote({
    required this.note,
    required this.score,
  });
}
