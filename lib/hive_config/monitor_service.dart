import 'dart:async';
import 'dart:io';
import 'package:hive/hive.dart';
import 'monitor.dart';

class MonitorService {
  static final MonitorService _instance = MonitorService._internal();
  factory MonitorService() => _instance;
  MonitorService._internal();

  late Box<Monitor> _box;
  Timer? _timer;

  Future<void> init() async {
    _box = await Hive.openBox<Monitor>('monitors');
  }

  Box<Monitor> get box => _box;
  List<Monitor> get monitors => _box.values.toList();

  Future<void> addMonitor(Monitor monitor) async {
    await _box.add(monitor);
  }

  Future<void> removeMonitor(int index) async {
    await _box.deleteAt(index);
  }

  Future<void> refreshMonitor(int key) async {
    var monitor = _box.get(key);
    if (monitor != null) {
      final stopwatch = Stopwatch()..start();
      final status = await _checkPort(monitor.host, monitor.port);
      stopwatch.stop();

      monitor.isUp = status;
      monitor.lastChecked = DateTime.now();
      monitor.responseTime = status ? '${stopwatch.elapsedMilliseconds}ms' : 'Timeout';
      await monitor.save(); // updates Hive
    }
  }

  void startMonitoring({Duration interval = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _checkAll());
  }

  void stopMonitoring() {
    _timer?.cancel();
  }

  Future<void> _checkAll() async {
    for (var i = 0; i < _box.length; i++) {
      var monitor = _box.getAt(i);
      if (monitor != null) {
        final stopwatch = Stopwatch()..start();
        final status = await _checkPort(monitor.host, monitor.port);
        stopwatch.stop();

        monitor.isUp = status;
        monitor.lastChecked = DateTime.now();
        monitor.responseTime = status ? '${stopwatch.elapsedMilliseconds}ms' : 'Timeout';
        await monitor.save(); // updates Hive
      }
    }
  }

  Future<bool> _checkPort(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateInterval(String interval) {
    Duration duration;
    switch (interval) {
      case '10s':
        duration = const Duration(seconds: 10);
        break;
      case '30s':
        duration = const Duration(seconds: 30);
        break;
      case '60s':
        duration = const Duration(seconds: 60);
        break;
      case '5min':
        duration = const Duration(minutes: 5);
        break;
      default:
        duration = const Duration(seconds: 30);
    }
    startMonitoring(interval: duration);
  }
}
