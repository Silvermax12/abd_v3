// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EpisodeAdapter extends TypeAdapter<Episode> {
  @override
  final int typeId = 1;

  @override
  Episode read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Episode(
      session: fields[0] as String,
      number: fields[1] as int,
      title: fields[2] as String,
      animeSession: fields[6] as String,
      thumbnail: fields[3] as String?,
      snapshot: fields[4] as String?,
      duration: fields[5] as String?,
      cachedAt: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Episode obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.session)
      ..writeByte(1)
      ..write(obj.number)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.thumbnail)
      ..writeByte(4)
      ..write(obj.snapshot)
      ..writeByte(5)
      ..write(obj.duration)
      ..writeByte(6)
      ..write(obj.animeSession)
      ..writeByte(7)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpisodeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
