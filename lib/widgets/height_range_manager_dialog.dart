import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/panasonic_camera_config.dart';
import '../models/position.dart';
import '../services/height_range_store.dart';
import '../services/preset_name_store.dart';
import '../utils/height_utils.dart';

class HeightRangeManagerDialog extends StatefulWidget {
  final List<Position> positions;
  final List<PanasonicCameraConfig> cameras;
  final VoidCallback onSaved;

  const HeightRangeManagerDialog({
    super.key,
    required this.positions,
    required this.cameras,
    required this.onSaved,
  });

  @override
  State<HeightRangeManagerDialog> createState() =>
      _HeightRangeManagerDialogState();
}

class _HeightRangeManagerDialogState extends State<HeightRangeManagerDialog> {
  List<HeightRange> _ranges = [];
  bool _loading = true;

  HeightRange? _editingRange;
  final TextEditingController _maxFeetCtrl = TextEditingController();
  final TextEditingController _maxInchesCtrl = TextEditingController();
  // positionId → cameraIp → selected preset number (1-based display; null = unset)
  final Map<String, Map<String, int?>> _presetSelections = {};
  // cameraIp → (0-based preset index → saved name)
  Map<String, Map<int, String>> _presetNamesByCamera = {};

  @override
  void initState() {
    super.initState();
    _loadRanges();
    _loadPresetNames();
  }

  Future<void> _loadPresetNames() async {
    final result = <String, Map<int, String>>{};
    for (final camera in widget.cameras) {
      final ip = camera.ipController.text;
      result[ip] = await PresetNameStore.loadAll(ip);
    }
    if (mounted) setState(() => _presetNamesByCamera = result);
  }

  @override
  void dispose() {
    _maxFeetCtrl.dispose();
    _maxInchesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRanges() async {
    final ranges = await HeightRangeStore.loadAll();
    if (mounted) setState(() { _ranges = ranges; _loading = false; });
  }

  // Ranges sorted so bounds read low-to-high, with the catch-all (null
  // maxHeightCm) last — this order defines each range's implicit lower
  // bound (the previous range's maxHeightCm) since ranges carry no name.
  List<HeightRange> _sorted(List<HeightRange> ranges) {
    final sorted = [...ranges]..sort((a, b) {
        if (a.maxHeightCm == null && b.maxHeightCm == null) return 0;
        if (a.maxHeightCm == null) return 1;
        if (b.maxHeightCm == null) return -1;
        return a.maxHeightCm!.compareTo(b.maxHeightCm!);
      });
    return sorted;
  }

  String _boundLabel(HeightRange range) {
    final sorted = _sorted(_ranges);
    final index = sorted.indexWhere((r) => r.id == range.id);
    final lowerBoundCm = index > 0 ? sorted[index - 1].maxHeightCm : null;

    if (range.maxHeightCm == null) {
      return lowerBoundCm != null
          ? 'Taller than ${formatHeightCm(lowerBoundCm)}'
          : 'Any height';
    }
    if (lowerBoundCm == null) {
      return 'Up to ${formatHeightCm(range.maxHeightCm!)}';
    }
    return '${formatHeightCm(lowerBoundCm)} – ${formatHeightCm(range.maxHeightCm!)}';
  }

  void _startEditing(HeightRange range) {
    _presetSelections.clear();
    if (range.maxHeightCm != null) {
      final (feet, inches) = cmToFeetInches(range.maxHeightCm!);
      _maxFeetCtrl.text = '$feet';
      _maxInchesCtrl.text = '$inches';
    } else {
      _maxFeetCtrl.clear();
      _maxInchesCtrl.clear();
    }
    for (final position in widget.positions) {
      _presetSelections[position.id] = {};
      for (final camera in widget.cameras) {
        final ip = camera.ipController.text;
        final idx = range.positionPresets[position.id]?[ip];
        _presetSelections[position.id]![ip] = idx != null ? idx + 1 : null;
      }
    }
    setState(() => _editingRange = range);
  }

  void _addNew() {
    _startEditing(HeightRange(id: generateHeightRangeId()));
  }

  void _save() {
    final feet = int.tryParse(_maxFeetCtrl.text.trim());
    final inches = int.tryParse(_maxInchesCtrl.text.trim());
    final maxHeightCm =
        feet != null || inches != null ? feetInchesToCm(feet ?? 0, inches ?? 0) : null;

    final positionPresets = <String, Map<String, int>>{};
    for (final position in widget.positions) {
      final cameraMap = <String, int>{};
      for (final camera in widget.cameras) {
        final ip = camera.ipController.text;
        final num = _presetSelections[position.id]?[ip];
        if (num != null && num >= 1 && num <= 100) {
          cameraMap[ip] = num - 1;
        }
      }
      if (cameraMap.isNotEmpty) positionPresets[position.id] = cameraMap;
    }

    final updated = HeightRange(
      id: _editingRange!.id,
      maxHeightCm: maxHeightCm,
      positionPresets: positionPresets,
    );

    final newRanges = [..._ranges];
    final idx = newRanges.indexWhere((r) => r.id == updated.id);
    if (idx >= 0) {
      newRanges[idx] = updated;
    } else {
      newRanges.add(updated);
    }

    HeightRangeStore.saveAll(newRanges).then((_) => widget.onSaved());
    setState(() { _ranges = newRanges; _editingRange = null; });
  }

  Future<void> _delete(String rangeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Height Range'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final newRanges = _ranges.where((r) => r.id != rangeId).toList();
    await HeightRangeStore.saveAll(newRanges);
    widget.onSaved();
    if (mounted) setState(() => _ranges = newRanges);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editingRange == null
          ? 'Manage Height Ranges'
          : 'Edit Height Range'),
      content: SizedBox(
        width: 480,
        child: _editingRange == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingRange == null
          ? [
              FilledButton.icon(
                onPressed: _addNew,
                icon: const Icon(Icons.add),
                label: const Text('Add Height Range'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingRange = null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (_ranges.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No height ranges yet.\nTap "Add Height Range" to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    final sorted = _sorted(_ranges);
    return ListView.separated(
      shrinkWrap: true,
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final range = sorted[i];
        final presetCount = range.positionPresets.length;
        return ListTile(
          leading: const Icon(Icons.height),
          title: Text(_boundLabel(range)),
          subtitle: Text(presetCount == 0
              ? 'No presets configured'
              : '$presetCount position${presetCount == 1 ? '' : 's'} configured'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(range),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _delete(range.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    final noPositions = widget.positions.isEmpty;
    final noCameras = widget.cameras.isEmpty;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxFeetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max Height — ft',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxInchesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max Height — in',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Leave blank for the catch-all range (tallest, no upper bound)',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
          if (noPositions || noCameras)
            Text(
              noPositions
                  ? 'Add positions first (Settings → Manage Positions).'
                  : 'No cameras configured.',
              style: const TextStyle(color: Colors.grey),
            )
          else
            ...widget.positions.map((position) => _buildPositionSection(position)),
        ],
      ),
    );
  }

  Widget _buildPositionSection(Position position) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(position.name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          ...widget.cameras.map((camera) {
            final ip = camera.ipController.text;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(camera.name,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    child: _presetDropdown(
                      value: _presetSelections[position.id]?[ip],
                      presetNames: _presetNamesByCamera[ip] ?? const {},
                      onChanged: (val) => setState(() {
                        _presetSelections[position.id] ??= {};
                        _presetSelections[position.id]![ip] = val;
                      }),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _presetDropdown({
    required int? value,
    required Map<int, String> presetNames,
    required ValueChanged<int?> onChanged,
  }) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Preset #',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: const Text('—', style: TextStyle(color: Colors.grey)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (var n = 1; n <= 100; n++)
              DropdownMenuItem<int?>(
                value: n,
                child: Text(presetNames[n - 1] != null
                    ? '${presetNames[n - 1]} ($n)'
                    : '$n'),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
