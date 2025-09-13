import 'package:hive/hive.dart';

part 'monitor.g.dart';

@HiveType(typeId: 0)
class Monitor extends HiveObject {
  @HiveField(0)
  String host;

  @HiveField(1)
  int port;

  @HiveField(2)
  String serviceName;

  @HiveField(3)
  bool isUp;

  @HiveField(4)
  DateTime lastChecked;

  @HiveField(5)
  String responseTime;

  Monitor({
    required this.host,
    required this.port,
    required this.serviceName,
    this.isUp = false,
    DateTime? lastChecked,
    this.responseTime = 'Checking...',
  }) : lastChecked = lastChecked ?? DateTime.now();
}
