// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monitor.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MonitorAdapter extends TypeAdapter<Monitor> {
  @override
  final int typeId = 0;

  @override
  Monitor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Monitor(
      host: fields[0] as String,
      port: fields[1] as int,
      serviceName: fields[2] as String,
      isUp: fields[3] as bool,
      lastChecked: fields[4] as DateTime?,
      responseTime: fields[5] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Monitor obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.host)
      ..writeByte(1)
      ..write(obj.port)
      ..writeByte(2)
      ..write(obj.serviceName)
      ..writeByte(3)
      ..write(obj.isUp)
      ..writeByte(4)
      ..write(obj.lastChecked)
      ..writeByte(5)
      ..write(obj.responseTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonitorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
