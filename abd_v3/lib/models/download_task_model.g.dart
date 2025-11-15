// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_task_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadTaskAdapter extends TypeAdapter<DownloadTask> {
  @override
  final int typeId = 3;

  @override
  DownloadTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadTask(
      id: fields[0] as String,
      m3u8Url: fields[1] as String,
      animeTitle: fields[2] as String,
      episodeTitle: fields[3] as String,
      episodeNumber: fields[4] as int,
      resolution: fields[5] as String,
      outputPath: fields[6] as String,
      animeSession: fields[16] as String,
      episodeSession: fields[17] as String,
      status: fields[7] as DownloadStatus,
      progress: fields[8] as double,
      downloadedBytes: fields[9] as int,
      totalBytes: fields[10] as int?,
      speedMBps: fields[11] as double,
      etaSeconds: fields[12] as int?,
      errorMessage: fields[13] as String?,
      createdAt: fields[14] as DateTime?,
      completedAt: fields[15] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadTask obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.m3u8Url)
      ..writeByte(2)
      ..write(obj.animeTitle)
      ..writeByte(3)
      ..write(obj.episodeTitle)
      ..writeByte(4)
      ..write(obj.episodeNumber)
      ..writeByte(5)
      ..write(obj.resolution)
      ..writeByte(6)
      ..write(obj.outputPath)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.progress)
      ..writeByte(9)
      ..write(obj.downloadedBytes)
      ..writeByte(10)
      ..write(obj.totalBytes)
      ..writeByte(11)
      ..write(obj.speedMBps)
      ..writeByte(12)
      ..write(obj.etaSeconds)
      ..writeByte(13)
      ..write(obj.errorMessage)
      ..writeByte(14)
      ..write(obj.createdAt)
      ..writeByte(15)
      ..write(obj.completedAt)
      ..writeByte(16)
      ..write(obj.animeSession)
      ..writeByte(17)
      ..write(obj.episodeSession);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DownloadStatusAdapter extends TypeAdapter<DownloadStatus> {
  @override
  final int typeId = 2;

  @override
  DownloadStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DownloadStatus.queued;
      case 1:
        return DownloadStatus.downloading;
      case 2:
        return DownloadStatus.paused;
      case 3:
        return DownloadStatus.completed;
      case 4:
        return DownloadStatus.failed;
      case 5:
        return DownloadStatus.cancelled;
      case 6:
        return DownloadStatus.processing;
      case 7:
        return DownloadStatus.fetchingM3u8;
      default:
        return DownloadStatus.queued;
    }
  }

  @override
  void write(BinaryWriter writer, DownloadStatus obj) {
    switch (obj) {
      case DownloadStatus.queued:
        writer.writeByte(0);
        break;
      case DownloadStatus.downloading:
        writer.writeByte(1);
        break;
      case DownloadStatus.paused:
        writer.writeByte(2);
        break;
      case DownloadStatus.completed:
        writer.writeByte(3);
        break;
      case DownloadStatus.failed:
        writer.writeByte(4);
        break;
      case DownloadStatus.cancelled:
        writer.writeByte(5);
        break;
      case DownloadStatus.processing:
        writer.writeByte(6);
        break;
      case DownloadStatus.fetchingM3u8:
        writer.writeByte(7);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
