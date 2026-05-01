import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'note_model.g.dart';

@HiveType(typeId: 0)
class NoteModel extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String encryptedTitle;

  @HiveField(2)
  late String encryptedContent;

  @HiveField(3)
  late DateTime createdAt;

  @HiveField(4)
  late DateTime modifiedAt;

  @HiveField(5)
  late List<String> tagIds;

  @HiveField(6)
  late bool isPinned;

  @HiveField(7)
  late bool isDeleted;

  /// Base64-encoded 32-byte random salt for HKDF key derivation.
  /// A new salt is generated each time the note is created or saved.
  @HiveField(8)
  late String noteSalt;

  NoteModel({
    String? id,
    required this.encryptedTitle,
    required this.encryptedContent,
    required this.noteSalt,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? tagIds,
    this.isPinned = false,
    this.isDeleted = false,
  }) {
    this.id = id ?? const Uuid().v4();
    this.createdAt = createdAt ?? DateTime.now();
    this.modifiedAt = modifiedAt ?? DateTime.now();
    this.tagIds = tagIds ?? [];
  }

  NoteModel copyWith({
    String? encryptedTitle,
    String? encryptedContent,
    String? noteSalt,
    List<String>? tagIds,
    bool? isPinned,
    bool? isDeleted,
  }) {
    return NoteModel(
      id: id,
      encryptedTitle: encryptedTitle ?? this.encryptedTitle,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      noteSalt: noteSalt ?? this.noteSalt,
      createdAt: createdAt,
      modifiedAt: DateTime.now(),
      tagIds: tagIds ?? List.from(this.tagIds),
      isPinned: isPinned ?? this.isPinned,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'encryptedTitle': encryptedTitle,
        'encryptedContent': encryptedContent,
        'noteSalt': noteSalt,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'tagIds': tagIds,
        'isPinned': isPinned,
        'isDeleted': isDeleted,
      };

  factory NoteModel.fromJson(Map<String, dynamic> json) => NoteModel(
        id: json['id'] as String,
        encryptedTitle: json['encryptedTitle'] as String,
        encryptedContent: json['encryptedContent'] as String,
        noteSalt: json['noteSalt'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        tagIds: List<String>.from(json['tagIds'] as List),
        isPinned: json['isPinned'] as bool? ?? false,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );
}

@HiveType(typeId: 1)
class TagModel extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String name;

  @HiveField(2)
  late int colorValue;

  TagModel({
    String? id,
    required this.name,
    int? colorValue,
  }) {
    this.id = id ?? const Uuid().v4();
    this.colorValue = colorValue ?? 0xFF6C63FF;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
      };

  factory TagModel.fromJson(Map<String, dynamic> json) => TagModel(
        id: json['id'] as String,
        name: json['name'] as String,
        colorValue: json['colorValue'] as int,
      );
}

/// Decrypted view of a note held only in memory — never persisted.
class NoteView {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<String> tagIds;
  final bool isPinned;

  const NoteView({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.modifiedAt,
    required this.tagIds,
    required this.isPinned,
  });

  String get preview {
    final stripped = content.trim().replaceAll('\n', ' ');
    return stripped.length > 100
        ? '${stripped.substring(0, 100)}...'
        : stripped;
  }
}