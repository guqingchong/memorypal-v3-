// 用户画像模型 - 16维度 + 置信度机制
class UserProfile {
  // 基础信息
  String? name;
  String? gender;
  int? age;
  String? identity;
  String? address;
  String? occupation;

  // 个人特质
  List<String> interests;
  List<String> habits;
  String? personality;
  List<String> strengths;

  // 社交关系
  List<String> familyMembers;
  List<String> workCircle;
  List<String> socialCircle;

  // 目标与困惑
  String? shortTermGoals;
  String? longTermDreams;
  String? currentConfusions;

  // 元数据
  DateTime lastUpdated;
  Map<String, dynamic> evidence;

  // 置信度机制（优化版新增）
  Map<String, double> confidence;

  UserProfile({
    this.name,
    this.gender,
    this.age,
    this.identity,
    this.address,
    this.occupation,
    this.interests = const [],
    this.habits = const [],
    this.personality,
    this.strengths = const [],
    this.familyMembers = const [],
    this.workCircle = const [],
    this.socialCircle = const [],
    this.shortTermGoals,
    this.longTermDreams,
    this.currentConfusions,
    required this.lastUpdated,
    this.evidence = const {},
    this.confidence = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'gender': gender,
      'age': age,
      'identity': identity,
      'address': address,
      'occupation': occupation,
      'interests': interests.join(','),
      'habits': habits.join(','),
      'personality': personality,
      'strengths': strengths.join(','),
      'family_members': familyMembers.join(','),
      'work_circle': workCircle.join(','),
      'social_circle': socialCircle.join(','),
      'short_term_goals': shortTermGoals,
      'long_term_dreams': longTermDreams,
      'current_confusions': currentConfusions,
      'last_updated': lastUpdated.millisecondsSinceEpoch,
      'evidence': evidence.toString(),
      'confidence': confidence.toString(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      name: map['name'] as String?,
      gender: map['gender'] as String?,
      age: map['age'] as int?,
      identity: map['identity'] as String?,
      address: map['address'] as String?,
      occupation: map['occupation'] as String?,
      interests: _parseList(map['interests']),
      habits: _parseList(map['habits']),
      personality: map['personality'] as String?,
      strengths: _parseList(map['strengths']),
      familyMembers: _parseList(map['family_members']),
      workCircle: _parseList(map['work_circle']),
      socialCircle: _parseList(map['social_circle']),
      shortTermGoals: map['short_term_goals'] as String?,
      longTermDreams: map['long_term_dreams'] as String?,
      currentConfusions: map['current_confusions'] as String?,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        map['last_updated'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      evidence: {},
      confidence: {},
    );
  }

  static List<String> _parseList(dynamic value) {
    if (value == null || value.toString().isEmpty) return [];
    return value.toString().split(',').where((s) => s.isNotEmpty).toList();
  }

  // 获取字段置信度
  double getConfidence(String field) {
    return confidence[field] ?? 0.0;
  }

  // 更新字段及置信度
  void updateField(String field, dynamic value, double conf) {
    switch (field) {
      case 'name':
        name = value;
        break;
      case 'gender':
        gender = value;
        break;
      case 'age':
        age = value;
        break;
      case 'identity':
        identity = value;
        break;
      case 'address':
        address = value;
        break;
      case 'occupation':
        occupation = value;
        break;
      case 'interests':
        interests = value;
        break;
      case 'habits':
        habits = value;
        break;
      case 'personality':
        personality = value;
        break;
      case 'strengths':
        strengths = value;
        break;
      case 'family_members':
        familyMembers = value;
        break;
      case 'work_circle':
        workCircle = value;
        break;
      case 'social_circle':
        socialCircle = value;
        break;
      case 'short_term_goals':
        shortTermGoals = value;
        break;
      case 'long_term_dreams':
        longTermDreams = value;
        break;
      case 'current_confusions':
        currentConfusions = value;
        break;
    }
    confidence[field] = conf;
    lastUpdated = DateTime.now();
  }
}

// 更新策略枚举
enum UpdateStrategy {
  autoUpdate, // 置信度 > 0.8：自动更新
  pendingConfirm, // 置信度 0.5-0.8：标记待确认
  ignore, // 置信度 < 0.5：忽略
}

// 根据置信度获取更新策略
UpdateStrategy getUpdateStrategy(double confidence) {
  if (confidence > 0.8) return UpdateStrategy.autoUpdate;
  if (confidence >= 0.5) return UpdateStrategy.pendingConfirm;
  return UpdateStrategy.ignore;
}

// 待确认更新项
class ProfileUpdate {
  final String field;
  final dynamic newValue;
  final double confidence;
  final String evidence;
  final DateTime detectedAt;

  ProfileUpdate({
    required this.field,
    required this.newValue,
    required this.confidence,
    required this.evidence,
    required this.detectedAt,
  });
}
