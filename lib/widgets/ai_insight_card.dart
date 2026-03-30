import 'package:flutter/material.dart';
import '../models/user_profile.dart';

/// AI 洞察卡片组件
/// 显示AI对用户的观察和建议
class AIInsightCard extends StatelessWidget {
  final UserProfile profile;

  const AIInsightCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final insights = _generateInsights();

    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.purple.shade400),
                const SizedBox(width: 8),
                const Text(
                  'AI 洞察',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            ...insights.map((insight) => _buildInsightItem(insight)),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(AIInsight insight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getTypeColor(insight.type).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getTypeIcon(insight.type),
              size: 20,
              color: _getTypeColor(insight.type),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.description,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<AIInsight> _generateInsights() {
    final insights = <AIInsight>[];

    // 基于性格特点生成洞察
    if (profile.personality != null) {
      insights.add(AIInsight(
        type: InsightType.personality,
        title: '性格分析',
        description: '根据您的日常记录，AI观察到您可能是${_getPersonalityDescription(profile.personality!)}类型的人',
      ));
    }

    // 基于习惯生成洞察
    if (profile.habits.isNotEmpty) {
      final habitText = profile.habits.take(3).join('、');
      insights.add(AIInsight(
        type: InsightType.habit,
        title: '习惯识别',
        description: '您表现出以下习惯特征：$habitText',
      ));
    }

    // 基于目标生成建议
    if (profile.shortTermGoals != null) {
      insights.add(AIInsight(
        type: InsightType.suggestion,
        title: '目标建议',
        description: '针对您的短期目标"${profile.shortTermGoals}"，建议每天安排固定时间推进',
      ));
    }

    // 基于困惑提供帮助
    if (profile.currentConfusions != null) {
      insights.add(AIInsight(
        type: InsightType.help,
        title: '困惑支持',
        description: '关于您提到的"${profile.currentConfusions}"，AI会持续关注相关信息并适时提供参考',
      ));
    }

    return insights;
  }

  String _getPersonalityDescription(String personality) {
    final descriptions = {
      '外向': '喜欢与人交流，从社交中获得能量',
      '内向': '更倾向于独处思考，享受个人空间',
      '理性': '逻辑清晰，善于分析问题',
      '感性': '富有同理心，重视情感体验',
      '计划型': '喜欢提前规划，做事有条理',
      '随性': '灵活应变，享受生活中的惊喜',
    };

    for (final key in descriptions.keys) {
      if (personality.contains(key)) {
        return '${personality}（${descriptions[key]}）';
      }
    }

    return personality;
  }

  Color _getTypeColor(InsightType type) {
    switch (type) {
      case InsightType.personality:
        return Colors.blue;
      case InsightType.habit:
        return Colors.green;
      case InsightType.suggestion:
        return Colors.orange;
      case InsightType.help:
        return Colors.purple;
    }
  }

  IconData _getTypeIcon(InsightType type) {
    switch (type) {
      case InsightType.personality:
        return Icons.psychology;
      case InsightType.habit:
        return Icons.repeat;
      case InsightType.suggestion:
        return Icons.lightbulb;
      case InsightType.help:
        return Icons.help_outline;
    }
  }
}

/// 洞察类型
enum InsightType {
  personality,
  habit,
  suggestion,
  help,
}

/// AI 洞察数据
class AIInsight {
  final InsightType type;
  final String title;
  final String description;

  AIInsight({
    required this.type,
    required this.title,
    required this.description,
  });
}
