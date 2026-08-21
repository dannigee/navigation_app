import 'dart:async';

import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/controllable_device.dart';
import '../models/roland_device.dart';
import '../models/panasonic_device.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/visibility_store.dart';

class MasterControlWidget extends StatefulWidget {
  final RolandServiceAbstract? rolandService;
  final ValueNotifier<bool>? rolandConnected;
  final TextEditingController? rolandIpController;
  final List<PanasonicCameraConfig> cameras;
  final ValueChanged<String> onResponse;

  /// Replaces the Roland/Panasonic devices normally built from the fields
  /// above. Lets tests substitute fakes with controllable async timing to
  /// exercise races between an in-flight save and a device/item switch.
  @visibleForTesting
  final List<ControllableDevice>? devicesOverride;

  const MasterControlWidget({
    super.key,
    required this.rolandService,
    required this.rolandConnected,
    required this.cameras,
    required this.onResponse,
    this.rolandIpController,
    this.devicesOverride,
  });

  @override
  State<MasterControlWidget> createState() => _MasterControlWidgetState();
}

class _MasterControlWidgetState extends State<MasterControlWidget> {
  late final List<ControllableDevice> _devices;
  int _selectedDeviceIndex = 0;
  int? _selectedItemIndex;
  bool _editMode = false;

  final Map<int, Map<int, String>> _namesByDevice = {};
  final Map<int, Map<int, ItemVisibility>> _visibilityByDevice = {};
  ItemVisibility _selectedVisibility = ItemVisibility.visible;

  final TextEditingController _renameController = TextEditingController();
  final List<VoidCallback> _deviceListeners = [];
  Timer? _renameDebounce;

  // Serializes every name-save so a flush and the autosave it preempted (or
  // two autosaves for different items in quick succession) always persist
  // in the order they were issued, never interleaved.
  Future<void> _saveQueue = Future.value();

  Future<void> _enqueueSave(Future<void> Function() op) {
    final result = _saveQueue.then((_) => op());
    _saveQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  void initState() {
    super.initState();
    _devices = widget.devicesOverride ??
        [
          RolandDevice(
            service: () => widget.rolandService,
            connected: widget.rolandConnected ?? ValueNotifier(false),
            ip: () => widget.rolandIpController?.text ?? '',
          ),
          ...widget.cameras.map(PanasonicDevice.new),
        ];
    _setupDeviceListeners();
    _loadDeviceMetadata(_selectedDeviceIndex);
  }

  @override
  void dispose() {
    _flushPendingRename();
    _removeDeviceListeners();
    _renameController.dispose();
    super.dispose();
  }

  /// Persists a still-pending debounced rename immediately -- called before
  /// the selection/device changes out from under it, and on dispose. Enqueued
  /// on [_saveQueue] rather than awaited here (dispose can't await), but the
  /// queue still guarantees this write lands before any later autosave.
  void _flushPendingRename() {
    if (_renameDebounce?.isActive ?? false) {
      _renameDebounce!.cancel();
      if (_selectedItemIndex != null) {
        final device = _devices[_selectedDeviceIndex];
        final index = _selectedItemIndex!;
        final name = _renameController.text.trim();
        _enqueueSave(() => device.saveName(index, name));
      }
    }
  }

  void _setupDeviceListeners() {
    for (int i = 0; i < _devices.length; i++) {
      void listener() => _onDeviceConnectionChanged(i);
      _deviceListeners.add(listener);
      _devices[i].connectionListenable.addListener(listener);
    }
  }

  void _removeDeviceListeners() {
    for (int i = 0; i < _devices.length; i++) {
      _devices[i].connectionListenable.removeListener(_deviceListeners[i]);
    }
    _deviceListeners.clear();
  }

  void _onDeviceConnectionChanged(int deviceIndex) {
    if (_devices[deviceIndex].isConnected && _selectedDeviceIndex == deviceIndex) {
      _loadDeviceMetadata(deviceIndex);
      _refreshSelectedDevice();
    }
  }

  Future<void> _loadDeviceMetadata(int deviceIndex) async {
    final device = _devices[deviceIndex];
    final names = await device.loadNames();
    final visibility = await device.loadVisibility();
    if (mounted) {
      setState(() {
        _namesByDevice[deviceIndex] = names;
        _visibilityByDevice[deviceIndex] = visibility;
      });
    }
  }

  Future<void> _refreshSelectedDevice() async {
    final deviceIndex = _selectedDeviceIndex;
    final future = _devices[deviceIndex].refreshItems();
    if (mounted) setState(() {}); // reflect isLoadingItems=true (set synchronously)
    try {
      await future;
    } catch (e) {
      if (mounted) widget.onResponse('Error fetching preset data: $e');
    }
    if (mounted) setState(() {});
  }

  void _onDeviceSelected(int index) {
    _flushPendingRename();
    setState(() {
      _selectedDeviceIndex = index;
      _selectedItemIndex = null;
      _renameController.clear();
      _selectedVisibility = ItemVisibility.visible;
    });
    _loadDeviceMetadata(index);
    _refreshSelectedDevice();
  }

  Future<void> _executeSelected(int index) async {
    try {
      final msg = await _devices[_selectedDeviceIndex].execute(index);
      widget.onResponse(msg);
    } catch (e) {
      widget.onResponse('$e');
    }
  }

  void _selectItem(int index) {
    _flushPendingRename();
    final device = _devices[_selectedDeviceIndex];
    final names = _namesByDevice[_selectedDeviceIndex] ?? {};
    final visibility = _visibilityByDevice[_selectedDeviceIndex] ?? {};
    setState(() {
      _selectedItemIndex = index;
      _renameController.text = names[index] ?? device.defaultLabel(index);
      _selectedVisibility = visibility[index] ?? ItemVisibility.visible;
    });
  }

  void _onRenameChanged(String _) {
    _renameDebounce?.cancel();
    _renameDebounce = Timer(const Duration(milliseconds: 500), _saveRename);
  }

  void _onRenameSubmitted(String _) {
    _renameDebounce?.cancel();
    _saveRename();
  }

  Future<void> _saveRename() async {
    if (_selectedItemIndex == null) return;
    final deviceIndex = _selectedDeviceIndex;
    final device = _devices[deviceIndex];
    final index = _selectedItemIndex!;
    final name = _renameController.text.trim();
    await _enqueueSave(() => device.saveName(index, name));
    final names = await device.loadNames();
    // Written into the device that was active when this save was kicked
    // off, not whichever device happens to be selected now -- the user may
    // have switched devices while the save/reload above were in flight.
    if (mounted) setState(() => _namesByDevice[deviceIndex] = names);
    widget.onResponse(
        '${device.describe(index)} renamed to "${name.isEmpty ? "(cleared)" : name}"');
  }

  Future<void> _saveVisibility(ItemVisibility visibility) async {
    if (_selectedItemIndex == null) return;
    final deviceIndex = _selectedDeviceIndex;
    final device = _devices[deviceIndex];
    final index = _selectedItemIndex!;
    setState(() => _selectedVisibility = visibility);
    await device.saveVisibility(index, visibility);
    final stored = await device.loadVisibility();
    if (mounted) setState(() => _visibilityByDevice[deviceIndex] = stored);
  }

  @override
  Widget build(BuildContext context) {
    final device = _devices[_selectedDeviceIndex];
    final names = _namesByDevice[_selectedDeviceIndex] ?? {};
    final selectedLabel = _selectedItemIndex != null
        ? (names[_selectedItemIndex] ?? device.describe(_selectedItemIndex!))
        : null;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Master Control',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _editMode = !_editMode),
                  style: _editMode
                      ? FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.tertiary,
                          foregroundColor: Theme.of(context).colorScheme.onTertiary,
                        )
                      : null,
                  icon: Icon(_editMode ? Icons.check : Icons.edit),
                  label: Text(_editMode ? 'Done Editing' : 'Edit Mode'),
                ),
              ],
            ),
            if (_editMode) ...[
              const SizedBox(height: 8),
              const Text(
                'Edit mode: tap a button to select it without executing it.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),

            // Device selector
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ToggleButtons(
                isSelected: List.generate(
                    _devices.length, (i) => i == _selectedDeviceIndex),
                onPressed: _onDeviceSelected,
                children: _devices
                    .map((d) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(d.name),
                        ))
                    .toList(),
              ),
            ),

            if (device.isLoadingItems) ...[
              const SizedBox(height: 8),
              const Row(children: [
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading presets...'),
              ]),
            ],

            const SizedBox(height: 12),

            // Grid
            Expanded(child: _buildGrid(device, names)),

            // Rename / Visibility section — editing tools, so only shown
            // in Edit Mode; outside it, tapping a button executes instead.
            if (_editMode) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Text('Rename',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  if (selectedLabel != null) ...[
                    const SizedBox(width: 8),
                    Text('— $selectedLabel',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (selectedLabel == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6.0),
                  child: Text('Tap a button above to select it for renaming',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              TextField(
                controller: _renameController,
                enabled: _selectedItemIndex != null,
                onChanged: _onRenameChanged,
                onSubmitted: _onRenameSubmitted,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Visibility',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SegmentedButton<ItemVisibility>(
                segments: const [
                  ButtonSegment(
                    value: ItemVisibility.visible,
                    label: Text('Visible'),
                    icon: Icon(Icons.visibility),
                  ),
                  ButtonSegment(
                    value: ItemVisibility.hidden,
                    label: Text('Hidden'),
                    icon: Icon(Icons.visibility_off),
                  ),
                ],
                selected: {_selectedVisibility},
                onSelectionChanged: _selectedItemIndex != null
                    ? (selection) => _saveVisibility(selection.first)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(ControllableDevice device, Map<int, String> names) {
    final indices = device.itemIndices;
    if (indices.isEmpty && !device.isLoadingItems) {
      return Center(
        child: Text(device.emptyMessage,
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return GridView.count(
      crossAxisCount: 5,
      childAspectRatio: 3.0,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: indices.map((index) {
        final label = names[index] ?? device.defaultLabel(index);
        final isSelected = _selectedItemIndex == index;
        return FilledButton(
          style: FilledButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 12),
            backgroundColor:
                isSelected ? Theme.of(context).colorScheme.tertiary : null,
          ),
          onPressed: () {
            if (_editMode) {
              _selectItem(index);
              return;
            }
            _executeSelected(index);
            _selectItem(index);
          },
          child: Text(label),
        );
      }).toList(),
    );
  }
}
