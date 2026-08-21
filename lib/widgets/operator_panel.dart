import 'package:flutter/material.dart';
import '../models/controllable_device.dart';
import '../models/operator_profile.dart';
import '../models/panasonic_camera_config.dart';
import '../models/panasonic_device.dart';
import '../models/roland_device.dart';
import '../models/service.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/preset_name_store.dart';
import '../services/service_store.dart';

class OperatorPanel extends StatefulWidget {
  final OperatorProfile operator;
  final RolandServiceAbstract? rolandService;
  final ValueNotifier<bool>? rolandConnected;
  final TextEditingController? rolandIpController;
  final List<PanasonicCameraConfig> cameras;
  final ValueChanged<String> onResponse;
  final VoidCallback? onServicesChanged;

  const OperatorPanel({
    super.key,
    required this.operator,
    required this.rolandService,
    required this.rolandConnected,
    required this.cameras,
    required this.onResponse,
    this.rolandIpController,
    this.onServicesChanged,
  });

  @override
  State<OperatorPanel> createState() => _OperatorPanelState();
}

class _OperatorPanelState extends State<OperatorPanel> {
  late List<ControllableDevice> _devices;
  int _selectedDeviceIndex = 0;
  final Map<int, Map<int, String>> _namesByDevice = {};
  final List<VoidCallback> _deviceListeners = [];
  final ScrollController _scrollController = ScrollController();

  bool _isRecording = false;
  final List<ServiceStep> _recordedSteps = [];

  @override
  void initState() {
    super.initState();
    _buildDevices();
    _setupListeners();
    _loadNames(_selectedDeviceIndex);
  }

  void _buildDevices() {
    _devices = [
      RolandDevice(
        service: () => widget.rolandService,
        connected: widget.rolandConnected ?? ValueNotifier(false),
        ip: () => widget.rolandIpController?.text ?? '',
      ),
      ...widget.cameras.map(PanasonicDevice.new),
    ];
  }

  @override
  void didUpdateWidget(OperatorPanel old) {
    super.didUpdateWidget(old);
    setState(() {});
  }

  @override
  void dispose() {
    _removeListeners();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupListeners() {
    for (int i = 0; i < _devices.length; i++) {
      void listener() {
        if (_devices[i].isConnected && _selectedDeviceIndex == i) {
          _refresh();
        }
      }
      _deviceListeners.add(listener);
      _devices[i].connectionListenable.addListener(listener);
    }
  }

  void _removeListeners() {
    for (int i = 0; i < _devices.length; i++) {
      _devices[i].connectionListenable.removeListener(_deviceListeners[i]);
    }
    _deviceListeners.clear();
  }

  Future<void> _loadNames(int deviceIndex) async {
    final names =
        await PresetNameStore.loadAll(_devices[deviceIndex].storageKey);
    if (mounted) setState(() => _namesByDevice[deviceIndex] = names);
  }

  Future<void> _refresh() async {
    final idx = _selectedDeviceIndex;
    if (mounted) setState(() {});
    try {
      await _devices[idx].refreshItems();
    } catch (e) {
      if (mounted) widget.onResponse('Error fetching data: $e');
    }
    if (mounted) setState(() {});
  }

  void _onDeviceSelected(int index) {
    setState(() => _selectedDeviceIndex = index);
    _loadNames(index);
    _refresh();
  }

  Future<void> _executeItem(int index) async {
    final device = _devices[_selectedDeviceIndex];
    try {
      widget.onResponse(await device.execute(index));
      if (_isRecording) {
        setState(() => _recordedSteps.add(device.toServiceStep(index)));
      }
    } catch (e) {
      widget.onResponse('$e');
    }
  }

  void _startRecording() => setState(() => _isRecording = true);

  Future<void> _stopRecording() async {
    setState(() => _isRecording = false);
    if (_recordedSteps.isEmpty) return;

    var pendingName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Save Recording (${_recordedSteps.length} steps)'),
        content: TextField(
          autofocus: true,
          onChanged: (v) => pendingName = v,
          decoration: const InputDecoration(
            labelText: 'Service Name',
            hintText: 'e.g. Standard Mass',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = pendingName.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(ctx).pop(trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (name == null) {
      setState(() => _recordedSteps.clear());
      return;
    }

    try {
      final services = await ServiceStore.loadAll();
      services.add(Service(
        id: generateServiceId(),
        name: name,
        steps: List.of(_recordedSteps),
      ));
      await ServiceStore.saveAll(services);
    } catch (e) {
      if (mounted) widget.onResponse('Error saving service: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _recordedSteps.clear());
    widget.onServicesChanged?.call();
  }

  List<int> _visibleIndices(ControllableDevice device) {
    final allowed = widget.operator.items[device.storageKey];
    if (allowed == null) {
      return widget.operator.isDefault ? device.itemIndices : [];
    }
    final allowedSet = allowed.toSet();
    return device.itemIndices.where(allowedSet.contains).toList();
  }

  static int _optimalCols(
      int count, double width, double height, double spacing) {
    int best = 1;
    double bestArea = 0;
    for (int c = 1; c <= count; c++) {
      final r = (count / c).ceil();
      final bw = (width - (c - 1) * spacing) / c;
      final bh = (height - (r - 1) * spacing) / r;
      if (bw <= 0 || bh <= 0) continue;
      final area = bw * bh;
      if (area > bestArea) {
        bestArea = area;
        best = c;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final device = _devices[_selectedDeviceIndex];
    final names = _namesByDevice[_selectedDeviceIndex] ?? {};
    final indices = _visibleIndices(device);

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ToggleButtons(
                      isSelected: List.generate(
                          _devices.length, (i) => i == _selectedDeviceIndex),
                      onPressed: _onDeviceSelected,
                      children: _devices
                          .map((d) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                child: Text(d.name),
                              ))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isRecording
                    ? ElevatedButton.icon(
                        onPressed: _stopRecording,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.stop),
                        label: Text(
                            'Stop (${_recordedSteps.length} step${_recordedSteps.length == 1 ? '' : 's'})'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _startRecording,
                        icon: const Icon(Icons.fiber_manual_record,
                            color: Colors.red),
                        label: const Text('Record'),
                      ),
              ],
            ),
            if (device.isLoadingItems) ...[
              const SizedBox(height: 8),
              const Row(children: [
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading presets…'),
              ]),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: indices.isEmpty && !device.isLoadingItems
                  ? Center(
                      child: Text(
                        device.itemIndices.isEmpty
                            ? 'No items available for this device.'
                            : 'No items configured for ${widget.operator.name}.\n'
                                'Go to Settings → Manage Operators to add items.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : LayoutBuilder(builder: (context, constraints) {
                      const spacing = 4.0;
                      const maxCols = 5;
                      const maxRows = 5;
                      final cols = _optimalCols(
                        indices.length,
                        constraints.maxWidth,
                        constraints.maxHeight,
                        spacing,
                      ).clamp(1, maxCols);
                      final totalRows = (indices.length / cols).ceil();
                      final bw =
                          (constraints.maxWidth - (cols - 1) * spacing) / cols;
                      final bh =
                          (constraints.maxHeight - (maxRows - 1) * spacing) /
                              maxRows;
                      return Scrollbar(
                        controller: _scrollController,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Column(
                            children: List.generate(totalRows, (row) {
                              final start = row * cols;
                              final end =
                                  (start + cols).clamp(0, indices.length);
                              final rowItems = indices.sublist(start, end);
                              return Padding(
                                padding:
                                    EdgeInsets.only(top: row == 0 ? 0 : spacing),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: rowItems.asMap().entries.map((e) {
                                    final label = names[e.value] ??
                                        device.defaultLabel(e.value);
                                    return Padding(
                                      padding: EdgeInsets.only(
                                          left: e.key == 0 ? 0 : spacing),
                                      child: SizedBox(
                                        width: bw,
                                        height: bh,
                                        child: Tooltip(
                                          message: label,
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8.0)),
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () =>
                                                _executeItem(e.value),
                                            child: FittedBox(
                                              fit: BoxFit.contain,
                                              child: Text(label,
                                                  textAlign: TextAlign.center),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }
}
