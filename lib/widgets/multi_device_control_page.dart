import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/operator_profile.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../models/service.dart';
import '../services/roland_service.dart';
import '../services/panasonic_service.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/mock/mock_roland_service.dart';
import '../services/mock/mock_panasonic_service.dart';
import '../services/device_config_store.dart';
import '../services/height_range_store.dart';
import '../services/operator_store.dart';
import '../services/people_store.dart';
import '../services/position_store.dart';
import '../services/service_store.dart';
import 'operator_panel.dart';
import 'people_manager_dialog.dart';
import 'service_tab.dart';
import 'positions_tab.dart';
import 'settings_dialog.dart';

class MultiDeviceControlPage extends StatefulWidget {
  const MultiDeviceControlPage({super.key});

  @override
  State<MultiDeviceControlPage> createState() => _MultiDeviceControlPageState();
}

class _MultiDeviceControlPageState extends State<MultiDeviceControlPage> {
  bool _mockMode = false;
  bool _connectingAll = false;

  // Roland
  final TextEditingController _rolandIpController =
      TextEditingController(text: '10.0.1.20');
  RolandServiceAbstract _rolandService = MockRolandService();
  final ValueNotifier<bool> _rolandConnected = ValueNotifier(false);
  final ValueNotifier<bool> _rolandConnecting = ValueNotifier(false);
  final ValueNotifier<String> _rolandConnectionError = ValueNotifier('');

  // Panasonic
  final List<PanasonicCameraConfig> _panasonicCameras = [];

  // Operators
  List<OperatorProfile> _operators = [OperatorProfile.defaultProfile];
  OperatorProfile _activeOperator = OperatorProfile.defaultProfile;

  // Shared data
  List<Position> _positions = [];
  List<Person> _people = [];
  List<Service> _services = [];
  List<HeightRange> _heightRanges = [];

  @override
  void initState() {
    super.initState();
    _loadDeviceConfig();
    _loadOperators();
    _loadPositions();
    _loadPeople();
    _loadServices();
    _loadHeightRanges();
  }

  Future<void> _loadDeviceConfig() async {
    final rolandIp = await DeviceConfigStore.loadRolandIp();
    final cameras = await DeviceConfigStore.loadCameras();
    if (!mounted) return;
    setState(() {
      _rolandIpController.text = rolandIp;
      _panasonicCameras
        ..clear()
        ..addAll(cameras.map(
            (e) => PanasonicCameraConfig(name: e.name, ipAddress: e.ip)));
    });
  }

  Future<void> _loadOperators() async {
    final operators = await OperatorStore.loadAll();
    final activeId = await OperatorStore.loadActiveId();
    if (!mounted) return;
    final active = operators.firstWhere(
      (o) => o.id == activeId,
      orElse: () => operators.first,
    );
    setState(() {
      _operators = operators;
      _activeOperator = active;
    });
  }

  void _setActiveOperator(OperatorProfile op) {
    setState(() => _activeOperator = op);
    OperatorStore.saveActiveId(op.id);
  }

  void _applyDeviceConfig(String rolandIp, List<CameraEntry> entries) {
    for (final c in _panasonicCameras) {
      c.isConnected.value = false;
      c.service = null;
      c.dispose();
    }
    setState(() {
      _rolandIpController.text = rolandIp;
      if (_rolandConnected.value) {
        _rolandService.disconnect();
        _rolandConnected.value = false;
        _rolandService = MockRolandService();
      }
      _panasonicCameras
        ..clear()
        ..addAll(entries.map(
            (e) => PanasonicCameraConfig(name: e.name, ipAddress: e.ip)));
    });
    DeviceConfigStore.save(rolandIp, entries);
  }

  @override
  void dispose() {
    _rolandService.disconnect();
    _rolandIpController.dispose();
    for (final camera in _panasonicCameras) {
      camera.ipController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPositions() async {
    final positions = await PositionStore.loadAll();
    if (mounted) setState(() => _positions = positions);
  }

  Future<void> _loadPeople() async {
    final people = await PeopleStore.loadAll();
    if (mounted) setState(() => _people = people);
  }

  Future<void> _loadServices() async {
    final services = await ServiceStore.loadAll();
    if (mounted) setState(() => _services = services);
  }

  Future<void> _loadHeightRanges() async {
    final heightRanges = await HeightRangeStore.loadAll();
    if (mounted) setState(() => _heightRanges = heightRanges);
  }

  Future<void> _connectAll() async {
    setState(() => _connectingAll = true);
    await Future.wait([
      _connectRoland(),
      ...List.generate(_panasonicCameras.length, _connectPanasonic),
    ]);
    if (mounted) setState(() => _connectingAll = false);
  }

  Future<void> _connectRoland() async {
    if (_rolandConnected.value) {
      await _rolandService.disconnect();
      setState(() {
        _rolandConnected.value = false;
        _rolandService = MockRolandService();
        _rolandConnectionError.value = '';
      });
      return;
    }

    setState(() {
      _rolandConnecting.value = true;
      _rolandConnectionError.value = '';
    });

    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _rolandService = MockRolandService();
        _rolandConnected.value = true;
        _rolandConnecting.value = false;
        _rolandConnectionError.value = '';
      });
      return;
    }

    final service = RolandService(host: _rolandIpController.text);
    try {
      await service.connect();
      setState(() {
        _rolandService = service;
        _rolandConnected.value = true;
        _rolandConnecting.value = false;
        _rolandConnectionError.value = '';
      });
    } catch (e) {
      setState(() {
        _rolandConnecting.value = false;
        _rolandConnectionError.value = e.toString();
      });
    }
  }

  Future<void> _connectPanasonic(int cameraIndex) async {
    if (cameraIndex >= _panasonicCameras.length) return;
    final camera = _panasonicCameras[cameraIndex];

    if (camera.isConnected.value) {
      setState(() {
        camera.isConnected.value = false;
        camera.service = MockPanasonicService();
        camera.connectionError.value = '';
      });
      return;
    }

    setState(() {
      camera.isConnecting.value = true;
      camera.connectionError.value = '';
    });

    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        camera.service = MockPanasonicService();
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
      return;
    }

    try {
      final service = PanasonicService(ipAddress: camera.ipController.text);
      await service.getCameraInfo();
      setState(() {
        camera.service = service;
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
    } catch (e) {
      setState(() {
        camera.isConnecting.value = false;
        camera.connectionError.value =
            'Could not reach camera: ${e.toString()}';
      });
    }
  }

  void _showOperatorPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Operator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _operators.map((op) {
            final selected = op.id == _activeOperator.id;
            return ListTile(
              leading: Icon(selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(op.name),
              onTap: () {
                _setActiveOperator(op);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openPeopleManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PeopleManagerDialog(
        positions: _positions,
        cameras: _panasonicCameras,
        heightRanges: _heightRanges,
        onSaved: _loadPeople,
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => SettingsDialog(
            mockMode: _mockMode,
            onMockModeChanged: (value) {
              setDialogState(() {
                _mockMode = value;
                if (_rolandConnected.value) {
                  _rolandService.disconnect();
                  _rolandConnected.value = false;
                  _rolandService = MockRolandService();
                }
                for (final camera in _panasonicCameras) {
                  if (camera.isConnected.value) {
                    camera.isConnected.value = false;
                    camera.service = MockPanasonicService();
                  }
                }
              });
            },
            rolandService: _rolandService,
            rolandIpController: _rolandIpController,
            rolandConnected: _rolandConnected,
            rolandConnecting: _rolandConnecting,
            rolandConnectionError: _rolandConnectionError,
            onConnectRoland: _connectRoland,
            panasonicCameras: _panasonicCameras,
            onConnectPanasonic: _connectPanasonic,
            onResponse: (_) {},
            positions: _positions,
            heightRanges: _heightRanges,
            onPositionsChanged: () async {
              await _loadPositions();
              setDialogState(() {});
            },
            onServicesChanged: () async {
              await _loadServices();
              setDialogState(() {});
            },
            onHeightRangesChanged: () async {
              await _loadHeightRanges();
              setDialogState(() {});
            },
            onPeopleChanged: () async {
              await _loadPeople();
              setDialogState(() {});
            },
            onAllDataChanged: () async {
              await Future.wait([
                _loadPositions(),
                _loadPeople(),
                _loadServices(),
                _loadHeightRanges(),
              ]);
              setDialogState(() {});
            },
            onDeviceConfigSaved: _applyDeviceConfig,
            onOperatorsChanged: () async {
              await _loadOperators();
              setDialogState(() {});
            },
          ),
        );
      },
    );
  }

  // ── Operator selector ────────────────────────────────────────────────────

  Widget _buildOperatorSelector({bool compact = false}) {
    if (_operators.length <= 1 && _operators.first.isDefault) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: _operators.map((op) {
        final selected = op.id == _activeOperator.id;
        return ChoiceChip(
          label: Text(op.name,
              style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal)),
          selected: selected,
          onSelected: (_) => _setActiveOperator(op),
        );
      }).toList(),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isConnected = _rolandConnected.value ||
        _panasonicCameras.any((c) => c.isConnected.value);

    if (!isConnected) {
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Manage People',
              onPressed: () => _openPeopleManager(context),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showSettingsDialog(context),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.devices, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No devices connected',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _mockMode
                      ? Colors.orange.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _mockMode ? 'Demo Mode' : 'Live Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _mockMode
                        ? Colors.orange.shade800
                        : Colors.blue.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildOperatorSelector(),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _connectingAll ? null : _connectAll,
                icon: _connectingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.power_settings_new),
                label: Text(_connectingAll ? 'Connecting…' : 'Connect All'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showSettingsDialog(context),
                icon: const Icon(Icons.settings),
                label: const Text('Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          Tooltip(
            message: 'Switch operator',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showOperatorPicker(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_activeOperator.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _mockMode
                            ? Colors.orange.shade100
                            : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _mockMode ? 'Demo' : 'Live',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _mockMode
                              ? Colors.orange.shade800
                              : Colors.blue.shade800,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Manage People',
            onPressed: () => _openPeopleManager(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Service'),
                Tab(text: 'Panel'),
                Tab(text: 'Positions'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ServiceTab(
                    cameras: _panasonicCameras,
                    people: _people,
                    positions: _positions,
                    services: _services,
                    heightRanges: _heightRanges,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    rolandIpController: _rolandIpController,
                    onResponse: (_) {},
                  ),
                  OperatorPanel(
                    operator: _activeOperator,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    rolandIpController: _rolandIpController,
                    cameras: _panasonicCameras,
                    onResponse: (_) {},
                    onServicesChanged: _loadServices,
                  ),
                  PositionsTab(
                    cameras: _panasonicCameras,
                    positions: _positions,
                    people: _people,
                    heightRanges: _heightRanges,
                    onResponse: (_) {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
