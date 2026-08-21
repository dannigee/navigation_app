import 'package:flutter/material.dart';
import '../models/operator_profile.dart';
import '../models/panasonic_camera_config.dart';
import '../services/operator_store.dart';
import '../services/preset_name_store.dart';
import '../utils/label_utils.dart';

class OperatorManagerDialog extends StatefulWidget {
  /// Storage key for the Roland device, e.g. `roland_10.0.1.20`.
  final String rolandStorageKey;

  /// Current camera list (used for storage keys and display names).
  final List<PanasonicCameraConfig> cameras;

  final VoidCallback onSaved;

  const OperatorManagerDialog({
    super.key,
    required this.rolandStorageKey,
    required this.cameras,
    required this.onSaved,
  });

  @override
  State<OperatorManagerDialog> createState() => _OperatorManagerDialogState();
}

class _OperatorManagerDialogState extends State<OperatorManagerDialog> {
  List<OperatorProfile> _operators = [];
  bool _loading = true;

  OperatorProfile? _editing;
  final TextEditingController _nameCtrl = TextEditingController();

  // Per-device mutable selection during edit: storageKey → set of selected indices
  Map<String, Set<int>> _editItems = {};

  // Per-device preset names for display during edit
  Map<String, Map<int, String>> _namesByKey = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ops = await OperatorStore.loadAll();
    if (mounted) setState(() { _operators = ops; _loading = false; });
  }

  // ── List view ────────────────────────────────────────────────────────────

  Future<void> _startEditing(OperatorProfile op) async {
    _nameCtrl.text = op.name;

    // Build mutable item selection from the operator's saved list.
    // Default operator starts with everything selected.
    final items = <String, Set<int>>{};
    final names = <String, Map<int, String>>{};
    final keys = _deviceKeys();

    for (final key in keys) {
      final allIndices = _allIndicesFor(key);
      final saved = op.items[key];
      items[key] = saved != null ? Set<int>.from(saved) : Set<int>.from(allIndices);
      names[key] = await PresetNameStore.loadAll(key);
    }

    if (mounted) {
      setState(() {
        _editItems = items;
        _namesByKey = names;
        _editing = op;
      });
    }
  }

  void _addNew() {
    // New operator copies the Default operator's selection (all items).
    const defaultOp = OperatorProfile.defaultProfile;
    _startEditing(OperatorProfile(
      id: generateOperatorId(),
      name: '',
      items: defaultOp.items,
    ));
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Operator'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = _operators.where((o) => o.id != id).toList();
    await OperatorStore.saveAll(updated);
    widget.onSaved();
    if (mounted) setState(() => _operators = updated);
  }

  // ── Editor ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final updated = _editing!.copyWith(
      name: name.isEmpty ? 'Operator' : name,
      items: _editItems.map((k, v) => MapEntry(k, v.toList()..sort())),
    );

    final newList = [..._operators];
    final idx = newList.indexWhere((o) => o.id == updated.id);
    if (idx >= 0) {
      newList[idx] = updated;
    } else {
      newList.add(updated);
    }

    await OperatorStore.saveAll(newList);
    widget.onSaved();
    if (mounted) setState(() { _operators = newList; _editing = null; });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  List<String> _deviceKeys() => [
        widget.rolandStorageKey,
        ...widget.cameras.map((c) => c.ipController.text),
      ];

  String _deviceLabel(String key) {
    if (key == widget.rolandStorageKey) return 'Roland';
    final cam = widget.cameras.firstWhere(
      (c) => c.ipController.text == key,
      orElse: () => PanasonicCameraConfig(name: key, ipAddress: key),
    );
    return cam.name;
  }

  /// Roland: macros 1–100. Cameras: presets 0–99.
  List<int> _allIndicesFor(String key) =>
      key == widget.rolandStorageKey
          ? List.generate(100, (i) => i + 1)
          : List.generate(100, (i) => i);

  String _labelFor(String key, int index) {
    final defaultLabel =
        key == widget.rolandStorageKey ? 'M$index' : '${index + 1}';
    return formatItemLabel(_namesByKey[key]?[index], defaultLabel);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing == null
          ? 'Manage Operators'
          : _editing!.id == OperatorProfile.defaultId
              ? 'Edit Default Operator'
              : _editing!.name.isEmpty
                  ? 'New Operator'
                  : 'Edit ${_editing!.name}'),
      content: SizedBox(
        width: 460,
        child: _editing == null ? _buildList() : _buildEditor(),
      ),
      actions: _editing == null
          ? [
              FilledButton.icon(
                onPressed: _addNew,
                icon: const Icon(Icons.add),
                label: const Text('Add Operator'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editing = null),
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
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_operators.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No operators yet.')),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _operators.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final op = _operators[i];
        final count = op.isDefault
            ? 'All items'
            : '${op.items.values.fold<int>(0, (sum, list) => sum + list.length)} items';
        return ListTile(
          leading: Icon(op.isDefault ? Icons.person_outline : Icons.person),
          title: Text(op.name),
          subtitle: Text(count),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(op),
              ),
              if (!op.isDefault)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _delete(op.id),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    final keys = _deviceKeys();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_editing!.isDefault)
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Operator name',
                border: OutlineInputBorder(),
              ),
            ),
          if (!_editing!.isDefault) const SizedBox(height: 16),
          ...keys.map((key) => _buildDeviceSection(key)),
        ],
      ),
    );
  }

  Widget _buildDeviceSection(String key) {
    final allIndices = _allIndicesFor(key);
    final selected = _editItems[key] ?? {};
    final allSelected = allIndices.every(selected.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(_deviceLabel(key),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(
                  () => _editItems[key] = Set<int>.from(allIndices)),
              child: const Text('All'),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _editItems[key] = {}),
              child: const Text('None'),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: allIndices.map((idx) {
            final isSelected = selected.contains(idx);
            return FilterChip(
              label: Text(_labelFor(key, idx),
                  style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              onSelected: (v) => setState(() {
                if (v) {
                  (_editItems[key] ??= {}).add(idx);
                } else {
                  _editItems[key]?.remove(idx);
                }
              }),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              showCheckmark: false,
              selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              side: BorderSide(
                color: allSelected || isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade400,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
