// 录音数据模型
class Recording {
  final int? id;
  final String filePath;
  final String? fileName;  // 原始文件名
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final String? title;  // 智能生成的标题
  final String? transcript;
  final String? summary;
  final List<String> tags;
  final bool isProcessed;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final bool isVoiceNote;  // 是否为语音笔记
  final String? source;  // 来源：'app' | 'system_call' | 'imported'

  Recording({
    this.id,
    required this.filePath,
    this.fileName,
    required this.startTime,
    DateTime? endTime,
    required this.durationSeconds,
    this.title,  // 智能标题
    this.transcript,
    this.summary,
    this.tags = const [],
    this.isProcessed = false,
    this.latitude,
    this.longitude,
    this.locationName,
    this.isVoiceNote = false,
    this.source = 'app',
  }) : endTime = endTime ?? startTime.add(Duration(seconds: durationSeconds));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'file_name': fileName,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'duration_seconds': durationSeconds,
      'title': title,
      'transcript': transcript,
      'summary': summary,
      'tags': tags.join(','),
      'is_processed': isProcessed ? 1 : 0,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'is_voice_note': isVoiceNote ? 1 : 0,
      'source': source,
    };
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      durationSeconds: map['duration_seconds'] as int,
      title: map['title'] as String?,
      transcript: map['transcript'] as String?,
      summary: map['summary'] as String?,
      tags: map['tags'] != null && (map['tags'] as String).isNotEmpty
          ? (map['tags'] as String).split(',')
          : [],
      isProcessed: map['is_processed'] == 1,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      locationName: map['location_name'] as String?,
      isVoiceNote: map['is_voice_note'] == 1,
      source: map['source'] as String? ?? 'app',
    );
  }

  Recording copyWith({
    int? id,
    String? filePath,
    String? fileName,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    String? title,
    String? transcript,
    String? summary,
    List<String>? tags,
    bool? isProcessed,
    double? latitude,
    double? longitude,
    String? locationName,
    bool? isVoiceNote,
    String? source,
  }) {
    return Recording(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      title: title ?? this.title,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      isProcessed: isProcessed ?? this.isProcessed,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      isVoiceNote: isVoiceNote ?? this.isVoiceNote,
      source: source ?? this.source,
    );
  }
}
