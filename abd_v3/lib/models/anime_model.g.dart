// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anime_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AnimeAdapter extends TypeAdapter<Anime> {
  @override
  final int typeId = 0;

  @override
  Anime read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Anime(
      session: fields[0] as String,
      title: fields[1] as String,
      poster: fields[2] as String?,
      type: fields[3] as String?,
      episodes: fields[4] as int?,
      status: fields[5] as String?,
      year: fields[6] as String?,
      season: fields[7] as String?,
      cachedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Anime obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.session)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.poster)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.episodes)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.year)
      ..writeByte(7)
      ..write(obj.season)
      ..writeByte(8)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
