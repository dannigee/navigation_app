import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/position.dart';
import '../models/service.dart';
import '../services/preset_name_store.dart';
import '../services/service_store.dart';

class _WorkingParticipant {
  String id;
  String name;
  _WorkingParticipant({required this.id, required this.name});
}

class _WorkingStep {
  final String id;
  StepType type;
  String? participantId;
  String? positionId;
  int? macroNumber;
  String? cameraIp;
  int? cameraPresetIndex;
  String? subServiceId;

  _WorkingStep({
    required this.id,
    this.type = StepType.ministry,
    this.participantId,
    this.positionId,
    this.macroNumber,
    this.cameraIp,
    this.cameraPresetIndex,
    this.subServiceId,
  });
}

class ServiceManagerDialog extends StatefulWidget {
  final List<Position> positions;
  final List<PanasonicCameraConfig> cameras;
  final VoidCallback onSaved;
  final TextEditingController? rolandIpController;

  const ServiceManagerDialog({
    super.key,
    required this.positions,
    required this.cameras,
    required this.onSaved,
    this.rolandIpController,
  });

  @override
  State<ServiceManagerDialog> createState() => _ServiceManagerDialogState();
}

class _ServiceManagerDialogState extends State<ServiceManagerDialog> {
  List<Service> _services = [];
  bool _loading = true;

  Service? _editingService;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _newParticipantCtrl = TextEditingController();

  List<_WorkingParticipant> _editingParticipants = [];
  List<_WorkingStep> _editingSteps = [];

  Map<int, String> _macroNames = {};
  Map<String, Map<int, String>> _cameraPresetNames = {};

  @override
  void initState() {
    super.initState();
    _loadServices();
    _loadPresetNames();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newParticipantCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    final services = await ServiceStore.loadAll();
    if (mounted) setState(() { _services = services; _loading = false; });
  }

  Future<void> _loadPresetNames() async {
    final rolandKey = 'roland_${widget.rolandIpController?.text ?? ''}';
    final macroNames = await PresetNameStore.loadAll(rolandKey);
    final cameraNames = <String, Map<int, String>>{};
    for (final cam in widget.cameras) {
      cameraNames[cam.ipController.text] =
          await PresetNameStore.loadAll(cam.ipController.text);
    }
    if (mounted) {
      setState(() {
        _macroNames = macroNames;
        _cameraPresetNames = cameraNames;
      });
    }
  }

  void _startEditing(Service service) {
    _nameCtrl.text = service.name;
    _newParticipantCtrl.clear();

    _editingParticipants = service.participants
        .map((p) => _WorkingParticipant(id: p.id, name: p.name))
        .toList();

    _editingSteps = service.steps.map((s) => _WorkingStep(
          id: s.id,
          type: s.type,
          participantId: s.participantId,
          positionId: s.positionId,
          macroNumber: s.macroNumber,
          cameraIp: s.cameraIp,
          cameraPresetIndex: s.cameraPresetIndex,
          subServiceId: s.subServiceId,
        )).toList();

    setState(() => _editingService = service);
  }

  void _addNewService() =>
      _startEditing(Service(id: generateServiceId(), name: ''));

  void _addParticipant() {
    final name = _newParticipantCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _editingParticipants.add(
          _WorkingParticipant(id: generateServiceId(), name: name));
      _newParticipantCtrl.clear();
    });
  }

  void _removeParticipant(String id) {
    setState(() => _editingParticipants.removeWhere((p) => p.id == id));
  }

  void _addStep() {
    final ws = _WorkingStep(id: generateServiceId(), type: StepType.ministry);
    setState(() => _editingSteps.add(ws));
  }

  void _removeStep(int index) {
    setState(() => _editingSteps.removeAt(index));
  }

  void _changeStepType(int index, StepType newType) {
    setState(() => _editingSteps[index].type = newType);
  }

  void _saveService() {
    final name = _nameCtrl.text.trim();
    final participants = _editingParticipants
        .map((p) => Participant(id: p.id, name: p.name))
        .toList();

    final steps = _editingSteps
        .map((s) => ServiceStep(
              id: s.id,
              type: s.type,
              participantId: s.participantId,
              positionId: s.positionId,
              macroNumber: s.type == StepType.macro ? s.macroNumber : null,
              cameraIp: s.cameraIp,
              cameraPresetIndex:
                  s.type == StepType.shot ? s.cameraPresetIndex : null,
              subServiceId: s.subServiceId,
            ))
        .toList();

    final updated = Service(
      id: _editingService!.id,
      name: name.isEmpty ? 'New Service' : name,
      participants: participants,
      steps: steps,
    );

    final newServices = [..._services];
    final idx = newServices.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) {
      newServices[idx] = updated;
    } else {
      newServices.add(updated);
    }

    ServiceStore.saveAll(newServices).then((_) => widget.onSaved());
    setState(() { _services = newServices; _editingService = null; });
  }

  Future<void> _deleteService(String serviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Service'),
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
    final newServices = _services.where((s) => s.id != serviceId).toList();
    await ServiceStore.saveAll(newServices);
    widget.onSaved();
    if (mounted) setState(() => _services = newServices);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editingService == null
          ? 'Manage Services'
          : _editingService!.name.isEmpty
              ? 'New Service'
              : _editingService!.name),
      content: SizedBox(
        width: 520,
        child: _editingService == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingService == null
          ? [
              FilledButton.icon(
                onPressed: _addNewService,
                icon: const Icon(Icons.add),
                label: const Text('Add Service'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingService = null),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: _saveService, child: const Text('Save')),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (_services.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No services yet.\nTap "Add Service" to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _services.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final service = _services[i];
        return ListTile(
          leading: const Icon(Icons.format_list_numbered),
          title: Text(service.name),
          subtitle: Text(
              '${service.steps.length} step${service.steps.length == 1 ? '' : 's'}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(service),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteService(service.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Service Name',
              hintText: 'e.g. Standard Mass, Christmas Vigil',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Participants section
          const Text('Participants',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          if (_editingParticipants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('No participants yet',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 13)),
            )
          else
            ..._editingParticipants.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(p.name,
                              style: const TextStyle(fontSize: 13))),
                      TextButton(
                        onPressed: () => _removeParticipant(p.id),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(28, 28),
                        ),
                        child: const Text('×',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                )),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newParticipantCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Participant name',
                    hintText: 'e.g. Reader 1, Priest',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addParticipant(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _addParticipant,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Steps section
          const Text('Steps',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ..._editingSteps.asMap().entries.map(
              (e) => _buildStepRow(e.key, e.value)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _addStep,
            icon: const Icon(Icons.add),
            label: const Text('Add Step'),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(int index, _WorkingStep s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${index + 1}.',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<StepType>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: StepType.ministry,
                          label: Text('Person')),
                      ButtonSegment(
                          value: StepType.macro,
                          label: Text('Macro')),
                      ButtonSegment(
                          value: StepType.shot,
                          label: Text('Shot')),
                      ButtonSegment(
                          value: StepType.block,
                          label: Text('Block')),
                    ],
                    selected: {s.type},
                    onSelectionChanged: (sel) =>
                        _changeStepType(index, sel.first),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => _removeStep(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildStepFields(s),
          ],
        ),
      ),
    );
  }

  Widget _buildStepFields(_WorkingStep s) {
    switch (s.type) {
      case StepType.ministry:
        return Row(
          children: [
            Expanded(
              child: _dropdown<String?>(
                hint: 'Participant',
                value: _editingParticipants.any((p) => p.id == s.participantId)
                    ? s.participantId
                    : null,
                items: _editingParticipants
                    .map((p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => s.participantId = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown<String?>(
                hint: 'Position',
                value: s.positionId,
                items: widget.positions
                    .map((p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => s.positionId = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown<String?>(
                hint: 'Camera',
                value: s.cameraIp,
                items: widget.cameras
                    .map((c) => DropdownMenuItem<String?>(
                          value: c.ipController.text,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => s.cameraIp = v),
              ),
            ),
          ],
        );

      case StepType.macro:
        return _dropdown<int?>(
          hint: 'Macro #',
          value: s.macroNumber,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (var n = 1; n <= 100; n++)
              DropdownMenuItem<int?>(
                value: n,
                child: Text(
                    _macroNames[n] != null ? '${_macroNames[n]} ($n)' : '$n'),
              ),
          ],
          onChanged: (v) => setState(() => s.macroNumber = v),
        );

      case StepType.shot:
        final presetNames = _cameraPresetNames[s.cameraIp] ?? const {};
        return Row(
          children: [
            Expanded(
              child: _dropdown<String?>(
                hint: 'Camera',
                value: s.cameraIp,
                items: widget.cameras
                    .map((c) => DropdownMenuItem<String?>(
                          value: c.ipController.text,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => s.cameraIp = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown<int?>(
                hint: 'Preset #',
                value:
                    s.cameraPresetIndex == null ? null : s.cameraPresetIndex! + 1,
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
                onChanged: (v) => setState(
                    () => s.cameraPresetIndex = v == null ? null : v - 1),
              ),
            ),
          ],
        );

      case StepType.block:
        final available =
            _services.where((sv) => sv.id != _editingService?.id).toList();
        return _dropdown<String?>(
          hint: 'Select service block',
          value: s.subServiceId,
          items: available
              .map((sv) => DropdownMenuItem<String?>(
                    value: sv.id,
                    child: Text(sv.name),
                  ))
              .toList(),
          onChanged: (v) => setState(() => s.subServiceId = v),
        );
    }
  }

  Widget _dropdown<T>({
    required String hint,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        hintText: hint,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
