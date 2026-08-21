import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../services/people_store.dart';
import '../services/preset_name_store.dart';
import '../utils/height_utils.dart';
import '../utils/label_utils.dart';
import '../utils/preset_resolver.dart';

class PeopleManagerDialog extends StatefulWidget {
  final List<Position> positions;
  final List<PanasonicCameraConfig> cameras;
  final List<HeightRange> heightRanges;
  final VoidCallback onSaved;

  const PeopleManagerDialog({
    super.key,
    required this.positions,
    required this.cameras,
    required this.heightRanges,
    required this.onSaved,
  });

  @override
  State<PeopleManagerDialog> createState() => _PeopleManagerDialogState();
}

class _PeopleManagerDialogState extends State<PeopleManagerDialog> {
  List<Person> _people = [];
  bool _loading = true;

  Person? _editingPerson;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _heightFeetCtrl = TextEditingController();
  final TextEditingController _heightInchesCtrl = TextEditingController();
  // positionId → cameraIp → selected preset number (1-based display; null = unset)
  final Map<String, Map<String, int?>> _presetSelections = {};
  // cameraIp → (0-based preset index → saved name)
  Map<String, Map<int, String>> _presetNamesByCamera = {};

  @override
  void initState() {
    super.initState();
    _loadPeople();
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
    _nameCtrl.dispose();
    _heightFeetCtrl.dispose();
    _heightInchesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    final people = await PeopleStore.loadAll();
    if (mounted) setState(() { _people = people; _loading = false; });
  }

  void _startEditing(Person person) {
    _presetSelections.clear();
    _nameCtrl.text = person.name;
    if (person.heightCm != null) {
      final (feet, inches) = cmToFeetInches(person.heightCm!);
      _heightFeetCtrl.text = '$feet';
      _heightInchesCtrl.text = '$inches';
    } else {
      _heightFeetCtrl.clear();
      _heightInchesCtrl.clear();
    }
    for (final position in widget.positions) {
      _presetSelections[position.id] = {};
      for (final camera in widget.cameras) {
        final ip = camera.ipController.text;
        final idx = person.positionPresets[position.id]?[ip];
        _presetSelections[position.id]![ip] = idx != null ? idx + 1 : null;
      }
    }
    setState(() => _editingPerson = person);
  }

  // Counts position+camera slots with no explicit override that still
  // resolve to a preset via a height range.
  int _heightDefaultCount(Person person) {
    var count = 0;
    for (final position in widget.positions) {
      for (final camera in widget.cameras) {
        final ip = camera.ipController.text;
        if (person.positionPresets[position.id]?[ip] != null) continue;
        final resolved = resolvePreset(
          person: person,
          positionId: position.id,
          cameraIp: ip,
          heightRanges: widget.heightRanges,
        );
        if (resolved != null) count++;
      }
    }
    return count;
  }

  void _addNewPerson() {
    _startEditing(Person(id: generatePositionId(), name: ''));
  }

  void _savePerson() {
    final name = _nameCtrl.text.trim();
    final feet = int.tryParse(_heightFeetCtrl.text.trim());
    final inches = int.tryParse(_heightInchesCtrl.text.trim());
    final heightCm =
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

    final updated = Person(
      id: _editingPerson!.id,
      name: name.isEmpty ? 'Unnamed' : name,
      heightCm: heightCm,
      positionPresets: positionPresets,
    );

    final newPeople = [..._people];
    final idx = newPeople.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      newPeople[idx] = updated;
    } else {
      newPeople.add(updated);
    }

    PeopleStore.saveAll(newPeople).then((_) => widget.onSaved());
    setState(() { _people = newPeople; _editingPerson = null; });
  }

  Future<void> _deletePerson(String personId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Person'),
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

    final newPeople = _people.where((p) => p.id != personId).toList();
    await PeopleStore.saveAll(newPeople);
    widget.onSaved();
    if (mounted) setState(() => _people = newPeople);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editingPerson == null
          ? 'Manage People'
          : _editingPerson!.name.isEmpty
              ? 'New Person'
              : _editingPerson!.name),
      content: SizedBox(
        width: 480,
        child: _editingPerson == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingPerson == null
          ? [
              FilledButton.icon(
                onPressed: _addNewPerson,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Person'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingPerson = null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _savePerson,
                child: const Text('Save'),
              ),
            ],
    );
  }

  String _subtitleFor(int explicitCount, int heightDefaultCount) {
    final parts = <String>[];
    if (explicitCount > 0) {
      parts.add(
          '$explicitCount position${explicitCount == 1 ? '' : 's'} configured');
    }
    if (heightDefaultCount > 0) {
      parts.add('$heightDefaultCount via height default');
    }
    return parts.isEmpty ? 'No presets configured' : parts.join(' · ');
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (_people.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No people yet.\nTap "Add Person" to create a profile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _people.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final person = _people[i];
        final positionCount = person.positionPresets.length;
        final heightDefaultCount = _heightDefaultCount(person);
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(person.name),
          subtitle: Text(_subtitleFor(positionCount, heightDefaultCount)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(person),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deletePerson(person.id),
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
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Fr. John, Deacon Mike',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _heightFeetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Height — ft',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _heightInchesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Height — in',
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
              'Optional — used to pick a default preset via height ranges when no explicit preset is set below',
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
                child: Text(formatItemLabel(presetNames[n - 1], '$n')),
              ),
          ],
          onChanged: onChanged,
        ),
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
            final hasOverride =
                _editingPerson?.positionPresets[position.id]?[ip] != null;
            final heightDefault = hasOverride || _editingPerson == null
                ? null
                : resolvePreset(
                    person: _editingPerson!,
                    positionId: position.id,
                    cameraIp: ip,
                    heightRanges: widget.heightRanges,
                  );
            final heightDefaultLabel = heightDefault == null
                ? null
                : formatItemLabel(
                    _presetNamesByCamera[ip]?[heightDefault],
                    '${heightDefault + 1}',
                    fallback: 'preset ${heightDefault + 1}');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                  if (heightDefaultLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 90, top: 2),
                      child: Text(
                        'Defaults to $heightDefaultLabel via height range',
                        style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
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
}
