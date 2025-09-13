import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hive_config/monitor.dart';
import 'hive_config/monitor_service.dart';
import 'hive_config/system_port_scanner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(MonitorAdapter());

  await MonitorService().init();
  MonitorService().startMonitoring();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Portly',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.cyanAccent,
          surface: const Color(0xFF121212),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          surfaceTintColor: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          surfaceTintColor: Color(0xFF1E1E1E),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
        ),
      ),
      home: const PortWatchScreen(),
    );
  }
}

class PortWatchScreen extends StatefulWidget {
  const PortWatchScreen({super.key});

  @override
  State<PortWatchScreen> createState() => _PortWatchScreenState();
}

class _PortWatchScreenState extends State<PortWatchScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final MonitorService _monitorService = MonitorService();
  final SystemPortScanner _systemPortScanner = SystemPortScanner();

  bool _autoRefresh = true;
  String _refreshInterval = '30s';
  bool _notifications = true;
  String _searchQuery = '';
  String _sortBy = 'host';
  bool _isSearchVisible = false;
  bool _isAddMonitorExpanded = false;
  bool _showPredefinedServices = false;
  bool _isSystemPortsView = false; // New state for view switching

  final List<Map<String, dynamic>> predefinedServices = [
    {"name": "HTTP", "port": 80},
    {"name": "HTTPS", "port": 443},
    {"name": "SSH", "port": 22},
    {"name": "MySQL", "port": 3306},
    {"name": "Postgres", "port": 5432},
    {"name": "MongoDB", "port": 27017},
  ];

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
    _loadSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _searchController.dispose();
    _systemPortScanner.dispose();
    super.dispose();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;

    if (isFirstLaunch) {
      setState(() {
        _showPredefinedServices = true;
      });
      await prefs.setBool('isFirstLaunch', false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _refreshInterval = prefs.getString('refreshInterval') ?? '30s';
      _notifications = prefs.getBool('notifications') ?? true;
    });

    if (_autoRefresh) {
      _monitorService.updateInterval(_refreshInterval);
    } else {
      _monitorService.stopMonitoring();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoRefresh', _autoRefresh);
    await prefs.setString('refreshInterval', _refreshInterval);
    await prefs.setBool('notifications', _notifications);
  }

  void _switchToSystemPorts() {
    setState(() {
      _isSystemPortsView = true;
      _isAddMonitorExpanded = false;
    });
    _systemPortScanner.startScanning();
  }

  void _switchToUserMonitors() {
    setState(() {
      _isSystemPortsView = false;
    });
    _systemPortScanner.stopScanning();
  }

  List<Monitor> _getFilteredMonitors(List<Monitor> monitors) {
    List<Monitor> filtered = monitors.where((monitor) {
      return monitor.host.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          monitor.port.toString().contains(_searchQuery) ||
          monitor.serviceName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'host':
          return a.host.compareTo(b.host);
        case 'port':
          return a.port.compareTo(b.port);
        case 'status':
          return b.isUp.toString().compareTo(a.isUp.toString());
        case 'protocol':
          return a.serviceName.compareTo(b.serviceName);
        default:
          return 0;
      }
    });

    return filtered;
  }

  List<SystemPort> _getFilteredSystemPorts(List<SystemPort> ports) {
    List<SystemPort> filtered = ports.where((port) {
      return port.port.toString().contains(_searchQuery) ||
          port.protocol.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          port.process.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'port':
          return a.port.compareTo(b.port);
        case 'protocol':
          return a.protocol.compareTo(b.protocol);
        default:
          return a.port.compareTo(b.port);
      }
    });

    return filtered;
  }

  Future<void> _addMonitor(String host, int port, {String? serviceName}) async {
    if (host.isEmpty || port <= 0) return;

    final monitor = Monitor(
      host: host,
      port: port,
      serviceName: serviceName ?? _getProtocolForPort(port),
    );

    await _monitorService.addMonitor(monitor);

    _hostController.clear();
    _portController.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added monitor for $host:$port'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _removeMonitor(int index) async {
    await _monitorService.removeMonitor(index);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Monitor removed'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getProtocolForPort(int port) {
    switch (port) {
      case 21: return 'FTP';
      case 22: return 'SSH';
      case 25: return 'SMTP';
      case 53: return 'DNS';
      case 80: return 'HTTP';
      case 110: return 'POP3';
      case 143: return 'IMAP';
      case 443: return 'HTTPS';
      case 587: return 'SMTP SSL';
      case 993: return 'IMAP SSL';
      case 995: return 'POP3 SSL';
      case 3306: return 'MySQL';
      case 5432: return 'PostgreSQL';
      case 27017: return 'MongoDB';
      case 6379: return 'Redis';
      default: return 'Custom';
    }
  }

  String _formatLastChecked(DateTime lastChecked) {
    final now = DateTime.now();
    final difference = now.difference(lastChecked);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isMediumScreen = screenSize.width < 900;
    final isLargeScreen = screenSize.width >= 1200;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.network_check, size: 28),
            SizedBox(width: 12),
            Text(
              'Portly',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ],
        ),
        actions: [
          // View Switch Toggle - Make responsive
          if (isSmallScreen) ...[
            PopupMenuButton<bool>(
              icon: Icon(_isSystemPortsView ? Icons.computer : Icons.favorite),
              onSelected: (bool value) {
                if (value) {
                  _switchToSystemPorts();
                } else {
                  _switchToUserMonitors();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<bool>(
                  value: false,
                  child: Row(
                    children: [
                      Icon(Icons.favorite, size: 16),
                      SizedBox(width: 8),
                      Text('My Monitors'),
                    ],
                  ),
                ),
                const PopupMenuItem<bool>(
                  value: true,
                  child: Row(
                    children: [
                      Icon(Icons.computer, size: 16),
                      SizedBox(width: 8),
                      Text('System Ports'),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('My Monitors'),
                  icon: Icon(Icons.favorite, size: 16),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('System Ports'),
                  icon: Icon(Icons.computer, size: 16),
                ),
              ],
              selected: {_isSystemPortsView},
              onSelectionChanged: (Set<bool> newSelection) {
                if (newSelection.first) {
                  _switchToSystemPorts();
                } else {
                  _switchToUserMonitors();
                }
              },
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_isSearchVisible ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
                if (!_isSearchVisible) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
            tooltip: 'Search',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(isSmallScreen ? 8.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add Monitor Section (only show for user monitors view)
                  if (!_isSystemPortsView) ...[
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.add_circle, color: Colors.blueAccent),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Add New Monitor',
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 16 : 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(_isAddMonitorExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down),
                                  onPressed: () {
                                    setState(() {
                                      _isAddMonitorExpanded = !_isAddMonitorExpanded;
                                    });
                                  },
                                  tooltip: _isAddMonitorExpanded ? 'Collapse' : 'Expand',
                                ),
                              ],
                            ),

                            if (_isAddMonitorExpanded) ...[
                              SizedBox(height: isSmallScreen ? 12 : 16),
                              // Input fields - Always use Column for small screens, Row for larger
                              isSmallScreen
                                  ? Column(
                                      children: [
                                        TextField(
                                          controller: _hostController,
                                          decoration: const InputDecoration(
                                            labelText: 'Host or IP Address',
                                            hintText: 'google.com',
                                            prefixIcon: Icon(Icons.language),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _portController,
                                          decoration: const InputDecoration(
                                            labelText: 'Port',
                                            hintText: '443',
                                            prefixIcon: Icon(Icons.numbers),
                                          ),
                                          keyboardType: TextInputType.number,
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              if (_hostController.text.isNotEmpty &&
                                                  _portController.text.isNotEmpty) {
                                                _addMonitor(
                                                  _hostController.text,
                                                  int.tryParse(_portController.text) ?? 0,
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.add),
                                            label: const Text('Add Monitor'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller: _hostController,
                                              decoration: const InputDecoration(
                                                labelText: 'Host or IP Address',
                                                hintText: 'google.com',
                                                prefixIcon: Icon(Icons.language),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 1,
                                            child: TextField(
                                              controller: _portController,
                                              decoration: const InputDecoration(
                                                labelText: 'Port',
                                                hintText: '443',
                                                prefixIcon: Icon(Icons.numbers),
                                              ),
                                              keyboardType: TextInputType.number,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              if (_hostController.text.isNotEmpty &&
                                                  _portController.text.isNotEmpty) {
                                                _addMonitor(
                                                  _hostController.text,
                                                  int.tryParse(_portController.text) ?? 0,
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.add),
                                            label: const Text('Add'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                              SizedBox(height: isSmallScreen ? 12 : 16),
                              _buildQuickPortsSection(),
                              SizedBox(height: isSmallScreen ? 12 : 16),
                              const Divider(),
                              SizedBox(height: isSmallScreen ? 8 : 8),
                              _buildSettingsSection(isSmallScreen),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 16),
                  ],

                  // Search Bar
                  if (_isSearchVisible) ...[
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: _isSystemPortsView ? 'Search system ports' : 'Search monitors',
                            hintText: _isSystemPortsView
                                ? 'Search by port, protocol, or process...'
                                : 'Search by host, port, or protocol...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                  ],

                  // Main Content Area - This needs to be Flexible to prevent overflow
                  Flexible(
                    child: _isSystemPortsView
                        ? _buildSystemPortsView(isSmallScreen, isMediumScreen, isLargeScreen)
                        : _buildUserMonitorsView(isSmallScreen, isMediumScreen, isLargeScreen),
                  ),
                ],
              ),
            ),

            if (_showPredefinedServices) _buildPredefinedServicesDialog(),
          ],
        ),
      ),
      floatingActionButton: (!_isAddMonitorExpanded && !_isSystemPortsView)
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _isAddMonitorExpanded = true;
                });
              },
              tooltip: 'Add Monitor',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildQuickPortsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Common Ports:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            direction: Axis.horizontal,
            children: [
              _buildQuickPortChip('22 SSH', Icons.terminal, () => _addMonitor(_hostController.text, 22, serviceName: 'SSH')),
              _buildQuickPortChip('80 HTTP', Icons.http, () => _addMonitor(_hostController.text, 80, serviceName: 'HTTP')),
              _buildQuickPortChip('443 HTTPS', Icons.lock, () => _addMonitor(_hostController.text, 443, serviceName: 'HTTPS')),
              _buildQuickPortChip('3306 MySQL', Icons.storage, () => _addMonitor(_hostController.text, 3306, serviceName: 'MySQL')),
              _buildQuickPortChip('5432 PostgreSQL', Icons.storage, () => _addMonitor(_hostController.text, 5432, serviceName: 'PostgreSQL')),
              _buildQuickPortChip('27017 MongoDB', Icons.storage, () => _addMonitor(_hostController.text, 27017, serviceName: 'MongoDB')),
              _buildQuickPortChip('21 FTP', Icons.folder, () => _addMonitor(_hostController.text, 21, serviceName: 'FTP')),
              _buildQuickPortChip('25 SMTP', Icons.email, () => _addMonitor(_hostController.text, 25, serviceName: 'SMTP')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(bool isSmallScreen) {
    return isSmallScreen
        ? Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.autorenew, size: 20),
                      SizedBox(width: 8),
                      Text('Auto Refresh'),
                    ],
                  ),
                  Switch(
                    value: _autoRefresh,
                    onChanged: (value) {
                      setState(() {
                        _autoRefresh = value;
                      });
                      if (value) {
                        _monitorService.updateInterval(_refreshInterval);
                      } else {
                        _monitorService.stopMonitoring();
                      }
                      _saveSettings();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Refresh Interval'),
                  DropdownButton<String>(
                    value: _refreshInterval,
                    items: ['10s', '30s', '60s', '5min'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _refreshInterval = newValue;
                        });
                        if (_autoRefresh) {
                          _monitorService.updateInterval(newValue);
                        }
                        _saveSettings();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications, size: 20),
                      SizedBox(width: 8),
                      Text('Notifications'),
                    ],
                  ),
                  Switch(
                    value: _notifications,
                    onChanged: (value) {
                      setState(() {
                        _notifications = value;
                      });
                      _saveSettings();
                    },
                  ),
                ],
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.autorenew, size: 20),
                  const SizedBox(width: 8),
                  const Text('Auto Refresh'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _autoRefresh,
                    onChanged: (value) {
                      setState(() {
                        _autoRefresh = value;
                      });
                      if (value) {
                        _monitorService.updateInterval(_refreshInterval);
                      } else {
                        _monitorService.stopMonitoring();
                      }
                      _saveSettings();
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Interval:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _refreshInterval,
                    items: ['10s', '30s', '60s', '5min'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _refreshInterval = newValue;
                        });
                        if (_autoRefresh) {
                          _monitorService.updateInterval(newValue);
                        }
                        _saveSettings();
                      }
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.notifications, size: 20),
                  const SizedBox(width: 8),
                  const Text('Notifications'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _notifications,
                    onChanged: (value) {
                      setState(() {
                        _notifications = value;
                      });
                      _saveSettings();
                    },
                  ),
                ],
              ),
            ],
          );
  }

  Widget _buildUserMonitorsView(bool isSmallScreen, bool isMediumScreen, bool isLargeScreen) {
    return ValueListenableBuilder<Box<Monitor>>(
      valueListenable: _monitorService.box.listenable(),
      builder: (context, box, _) {
        final monitors = _getFilteredMonitors(box.values.toList());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Active Monitors',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${monitors.length} monitors (${monitors.where((m) => m.isUp).length} up, ${monitors.where((m) => !m.isUp).length} down)',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                _buildSortMenu(),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: monitors.isEmpty
                  ? _buildEmptyState()
                  : isSmallScreen
                      ? ListView.builder(
                          itemCount: monitors.length,
                          itemBuilder: (context, index) {
                            return _buildMonitorCard(monitors[index], index, isSmallScreen: true);
                          },
                        )
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isLargeScreen ? 4 : (isMediumScreen ? 2 : 3),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: isLargeScreen ? 2.2 : 1.8,
                          ),
                          itemCount: monitors.length,
                          itemBuilder: (context, index) {
                            return _buildMonitorCard(monitors[index], index, isSmallScreen: false);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemPortsView(bool isSmallScreen, bool isMediumScreen, bool isLargeScreen) {
    return StreamBuilder<List<SystemPort>>(
      stream: _systemPortScanner.portsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Scanning system ports...'),
              ],
            ),
          );
        }

        final systemPorts = _getFilteredSystemPorts(snapshot.data!);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Ports',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${systemPorts.length} open ports detected',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () {
                        _systemPortScanner.startScanning();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Refreshing system ports...'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      tooltip: 'Refresh Scan',
                    ),
                    _buildSortMenu(),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: systemPorts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.computer, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No open ports found',
                            style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    )
                  : isSmallScreen
                      ? ListView.builder(
                          itemCount: systemPorts.length,
                          itemBuilder: (context, index) {
                            return _buildSystemPortCard(systemPorts[index], isSmallScreen: true);
                          },
                        )
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isLargeScreen ? 4 : (isMediumScreen ? 2 : 3),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: isLargeScreen ? 2.2 : 1.8,
                          ),
                          itemCount: systemPorts.length,
                          itemBuilder: (context, index) {
                            return _buildSystemPortCard(systemPorts[index], isSmallScreen: false);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sort, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text('Sort', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
      onSelected: (String value) {
        setState(() {
          _sortBy = value;
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (!_isSystemPortsView) ...[
          const PopupMenuItem<String>(
            value: 'host',
            child: Row(
              children: [Icon(Icons.language, size: 16), SizedBox(width: 8), Text('Host')],
            ),
          ),
        ],
        const PopupMenuItem<String>(
          value: 'port',
          child: Row(
            children: [Icon(Icons.numbers, size: 16), SizedBox(width: 8), Text('Port')],
          ),
        ),
        if (!_isSystemPortsView) ...[
          const PopupMenuItem<String>(
            value: 'status',
            child: Row(
              children: [Icon(Icons.circle, size: 16), SizedBox(width: 8), Text('Status')],
            ),
          ),
        ],
        const PopupMenuItem<String>(
          value: 'protocol',
          child: Row(
            children: [Icon(Icons.category, size: 16), SizedBox(width: 8), Text('Protocol')],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No monitors match your search'
                : 'No monitors added yet',
            style: TextStyle(fontSize: 16, color: Colors.grey[400]),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isAddMonitorExpanded = true;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add your first monitor'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSystemPortCard(SystemPort port, {required bool isSmallScreen}) {
    return Card(
      elevation: 3,
      margin: isSmallScreen ? const EdgeInsets.symmetric(vertical: 6) : EdgeInsets.zero,
      color: const Color(0xFF1E3A2F), // Always green for listening ports
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'localhost:${port.port}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          port.protocol,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[100],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (String value) async {
                    if (value == 'add_monitor') {
                      await _addMonitor('localhost', port.port, serviceName: port.protocol);
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'add_monitor',
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 16),
                          SizedBox(width: 8),
                          Text('Add to Monitors'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.apps, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Process',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        port.process,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Last Check',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatLastChecked(port.lastChecked),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitorCard(Monitor monitor, int index, {required bool isSmallScreen}) {
    return Card(
      elevation: 3,
      margin: isSmallScreen ? const EdgeInsets.symmetric(vertical: 6) : EdgeInsets.zero,
      color: monitor.isUp ? const Color(0xFF1E3A2F) : const Color(0xFF3A2F1E),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: monitor.isUp
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                        : const Color(0xFFD32F2F).withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    monitor.isUp ? Icons.check_circle : Icons.error,
                    color: monitor.isUp ? Colors.greenAccent : Colors.orangeAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              monitor.host,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            ':${monitor.port}',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontWeight: FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          monitor.serviceName,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[100],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (String value) async {
                    if (value == 'delete') {
                      _removeMonitor(index);
                    } else if (value == 'refresh') {
                      await _monitorService.refreshMonitor(monitor.key);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Refreshed ${monitor.host}:${monitor.port}'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'refresh',
                      child: Row(
                        children: [Icon(Icons.refresh, size: 16), SizedBox(width: 8), Text('Refresh')],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Last Check',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatLastChecked(monitor.lastChecked),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.speed, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Response',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        monitor.responseTime,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: monitor.responseTime == 'Timeout'
                              ? Colors.orangeAccent
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPortChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () {
        if (_hostController.text.isNotEmpty) {
          onTap();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a host first'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      backgroundColor: Colors.blueGrey.withValues(alpha: 0.2),
    );
  }

  Widget _buildPredefinedServicesDialog() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Welcome to Portly!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Would you like to add some common services to monitor?',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  width: 400,
                  child: SingleChildScrollView(
                    child: Column(
                      children: predefinedServices.map((service) {
                        return Card(
                          child: ListTile(
                            leading: Icon(_getIconForService(service['name'])),
                            title: Text(service['name']),
                            subtitle: Text('Port ${service['port']}'),
                            trailing: ElevatedButton(
                              onPressed: () async {
                                await _addMonitor('localhost', service['port'], serviceName: service['name']);
                              },
                              child: const Text('Add'),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showPredefinedServices = false;
                        });
                      },
                      child: const Text('Skip'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _showPredefinedServices = false;
                        });
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForService(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'http':
      case 'https':
        return Icons.http;
      case 'ssh':
        return Icons.terminal;
      case 'mysql':
      case 'postgres':
      case 'mongodb':
        return Icons.storage;
      default:
        return Icons.network_check;
    }
  }
}
