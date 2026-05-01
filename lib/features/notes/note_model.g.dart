// GENERATED CODE — run: dart run build_runner build --delete-conflicting-outputs
// This hand-written stub matches the NoteModel / TagModel definitions above.
// Re-generate with build_runner after any @HiveField change.

part of 'note_model.dart';

class NoteModelAdapter extends TypeAdapter<NoteModel> {
  @override
  final int typeId = 0;

  @override
  NoteModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NoteModel(
      id: fields[0] as String,
      encryptedTitle: fields[1] as String,
      encryptedContent: fields[2] as String,
      noteSalt: fields[8] as String? ?? '',
      createdAt: fields[3] as DateTime,
      modifiedAt: fields[4] as DateTime,
      tagIds: (fields[5] as List).cast<String>(),
      isPinned: fields[6] as bool,
      isDeleted: fields[7] as bool,
    )
      ..id = fields[0] as String
      ..encryptedTitle = fields[1] as String
      ..encryptedContent = fields[2] as String
      ..createdAt = fields[3] as DateTime
      ..modifiedAt = fields[4] as DateTime
      ..tagIds = (fields[5] as List).cast<String>()
      ..isPinned = fields[6] as bool
      ..isDeleted = fields[7] as bool
      ..noteSalt = fields[8] as String? ?? '';
  }

  @override
  void write(BinaryWriter writer, NoteModel obj) {
    writer
      ..writeByte(9) // 9 fields
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.encryptedTitle)
      ..writeByte(2)
      ..write(obj.encryptedContent)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.modifiedAt)
      ..writeByte(5)
      ..write(obj.tagIds)
      ..writeByte(6)
      ..write(obj.isPinned)
      ..writeByte(7)
      ..write(obj.isDeleted)
      ..writeByte(8)
      ..write(obj.noteSalt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TagModelAdapter extends TypeAdapter<TagModel> {
  @override
  final int typeId = 1;

  @override
  TagModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TagModel(
      id: fields[0] as String,
      name: fields[1] as String,
      colorValue: fields[2] as int,
    )
      ..id = fields[0] as String
      ..name = fields[1] as String
      ..colorValue = fields[2] as int;
  }

  @override
  void write(BinaryWriter writer, TagModel obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.colorValue);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}