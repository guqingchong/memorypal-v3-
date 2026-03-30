// 录音数据模型
class Recording {
  final int? id;
  final String filePath;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final String? transcript;
  final String? summary;
  final List<String> tags;
  final bool isProcessed;
  final double? latitude;
  final double? longitude;
  final String? locationName;

  Recording({
    this.id,
    required this.filePath,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    this.transcript,
    this.summary,
    this.tags = const [],
    this.isProcessed = false,
    this.latitude,
    this.longitude,
    this.locationName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'duration_seconds': durationSeconds,
      'transcript': transcript,
      'summary': summary,
      'tags': tags.join(','),
      'is_processed': isProcessed ? 1 : 0,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
    };
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      durationSeconds: map['duration_seconds'] as int,
      transcript: map['transcript'] as String?,
      summary: map['summary'] as String?,
      tags: map['tags'] != null && (map['tags'] as String).isNotEmpty
          ? (map['tags'] as String).split(',')
          : [],
      isProcessed: map['is_processed'] == 1,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      locationName: map['location_name'] as String?,
    );
  }

  Recording copyWith({
    int? id,
    String? filePath,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    String? transcript,
    String? summary,
    List<String>? tags,
    bool? isProcessed,
    double? latitude,
    double? longitude,
    String? locationName,
  }) {
    return Recording(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      isProcessed: isProcessed ?? this.isProcessed,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
    );
  }
}
