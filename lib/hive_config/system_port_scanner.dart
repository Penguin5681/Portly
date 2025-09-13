import 'dart:async';
import 'dart:io';
import 'dart:collection';

class SystemPortScanner {
  static final SystemPortScanner _instance = SystemPortScanner._internal();
  factory SystemPortScanner() => _instance;
  SystemPortScanner._internal();

  Timer? _scanTimer;
  final List<SystemPort> _openPorts = [];
  final StreamController<List<SystemPort>> _portsController =
      StreamController<List<SystemPort>>.broadcast();

  Stream<List<SystemPort>> get portsStream => _portsController.stream;
  List<SystemPort> get openPorts => List.unmodifiable(_openPorts);

  void startScanning({Duration interval = const Duration(seconds: 10)}) {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(interval, (_) => _scanAllPorts());
    // Initial scan
    _scanAllPorts();
  }

  void stopScanning() {
    _scanTimer?.cancel();
  }

  Future<void> _scanAllPorts() async {
    final newOpenPorts = <SystemPort>[];

    // Scan common ports first (1-1024) for faster initial results
    final commonPorts = List.generate(1024, (index) => index + 1);

    // Then scan additional common service ports
    final additionalPorts = [
      1433, 1521, 1883, 2049, 2181, 2375, 2376, 3000, 3001, 3306, 3389,
      4000, 4369, 5000, 5432, 5672, 5984, 6379, 6543, 7000, 8000, 8080,
      8443, 8888, 9000, 9092, 9200, 9300, 11211, 27017, 27018, 27019, 28017
    ];

    final allPorts = [...commonPorts, ...additionalPorts].toSet().toList();

    // Use concurrent scanning for better performance
    final futures = <Future<SystemPort?>>[];
    final semaphore = Semaphore(50); // Limit concurrent connections

    for (final port in allPorts) {
      futures.add(semaphore.acquire().then((_) async {
        try {
          final result = await _checkSystemPort(port);
          return result;
        } finally {
          semaphore.release();
        }
      }));
    }

    final results = await Future.wait(futures);

    for (final port in results) {
      if (port != null) {
        newOpenPorts.add(port);
      }
    }

    // Sort by port number
    newOpenPorts.sort((a, b) => a.port.compareTo(b.port));

    _openPorts.clear();
    _openPorts.addAll(newOpenPorts);
    _portsController.add(_openPorts);
  }

  Future<SystemPort?> _checkSystemPort(int port) async {
    try {
      // Try to connect to localhost on this port
      final socket = await Socket.connect(
        'localhost',
        port,
        timeout: const Duration(milliseconds: 500)
      );

      final processInfo = await _getProcessInfo(port);
      socket.destroy();

      return SystemPort(
        port: port,
        protocol: _getProtocolForPort(port),
        process: processInfo,
        isListening: true,
        lastChecked: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _getProcessInfo(int port) async {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        // Use netstat to get process information
        final result = await Process.run(
          'netstat',
          ['-tlnp'],
          runInShell: true
        );

        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.contains(':$port ') && line.contains('LISTEN')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length > 6) {
                final processInfo = parts[6];
                if (processInfo.contains('/')) {
                  return processInfo.split('/').last;
                }
              }
            }
          }
        }
      } else if (Platform.isWindows) {
        // Use netstat for Windows
        final result = await Process.run(
          'netstat',
          ['-ano'],
          runInShell: true
        );

        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.contains(':$port ') && line.contains('LISTENING')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.isNotEmpty) {
                final pid = parts.last.trim();
                if (pid.isNotEmpty && pid != '0') {
                  return 'PID: $pid';
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Ignore errors in process detection
    }

    return 'Unknown Process';
  }

  String _getProtocolForPort(int port) {
    switch (port) {
      case 21: return 'FTP';
      case 22: return 'SSH';
      case 23: return 'Telnet';
      case 25: return 'SMTP';
      case 53: return 'DNS';
      case 80: return 'HTTP';
      case 110: return 'POP3';
      case 143: return 'IMAP';
      case 443: return 'HTTPS';
      case 587: return 'SMTP SSL';
      case 993: return 'IMAP SSL';
      case 995: return 'POP3 SSL';
      case 1433: return 'SQL Server';
      case 1521: return 'Oracle';
      case 3306: return 'MySQL';
      case 3389: return 'RDP';
      case 5432: return 'PostgreSQL';
      case 5984: return 'CouchDB';
      case 6379: return 'Redis';
      case 8080: return 'HTTP Alt';
      case 8443: return 'HTTPS Alt';
      case 9092: return 'Kafka';
      case 9200: return 'Elasticsearch';
      case 11211: return 'Memcached';
      case 27017: return 'MongoDB';
      default: return 'Unknown';
    }
  }

  void dispose() {
    _scanTimer?.cancel();
    _portsController.close();
  }
}

class SystemPort {
  final int port;
  final String protocol;
  final String process;
  final bool isListening;
  final DateTime lastChecked;

  SystemPort({
    required this.port,
    required this.protocol,
    required this.process,
    required this.isListening,
    required this.lastChecked,
  });
}

class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}
