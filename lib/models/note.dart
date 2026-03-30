// 笔记数据模型
enum NoteType { voice, text }

class Note {
  final int? id;
  final NoteType type;
  final String title;
  final String content;
  final String? audioPath;
  final String? transcript;
  final List<String> tags;
  final int? linkedRecordingId;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    this.id,
    required this.type,
    required this.title,
    required this.content,
    this.audioPath,
    this.transcript,
    this.tags = const [],
    this.linkedRecordingId,
    this.latitude,
    this.longitude,
    this.locationName,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'content': content,
      'audio_path': audioPath,
      'transcript': transcript,
      'tags': tags.join(','),
      'linked_recording_id': linkedRecordingId,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      type: NoteType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => NoteType.text,
      ),
      title: map['title'] as String,
      content: map['content'] as String,
      audioPath: map['audio_path'] as String?,
      transcript: map['transcript'] as String?,
      tags: map['tags'] != null && (map['tags'] as String).isNotEmpty
          ? (map['tags'] as String).split(',')
          : [],
      linkedRecordingId: map['linked_recording_id'] as int?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      locationName: map['location_name'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Note copyWith({
    int? id,
    NoteType? type,
    String? title,
    String? content,
    String? audioPath,
    String? transcript,
    List<String>? tags,
    int? linkedRecordingId,
    double? latitude,
    double? longitude,
    String? locationName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      audioPath: audioPath ?? this.audioPath,
      transcript: transcript ?? this.transcript,
      tags: tags ?? this.tags,
      linkedRecordingId: linkedRecordingId ?? this.linkedRecordingId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
