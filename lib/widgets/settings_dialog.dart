import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/operator_profile.dart';
import '../models/panasonic_camera_config.dart';
import '../models/position.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/config_bundle.dart';
import '../services/device_config_store.dart';
import '../services/operator_store.dart';
import 'connections_dialog.dart';
import 'height_range_manager_dialog.dart';
import 'master_control_widget.dart';
import 'operator_manager_dialog.dart';
import 'people_manager_dialog.dart';
import 'pinp_tab.dart';
import 'position_manager_dialog.dart';
import 'service_manager_dialog.dart';

class SettingsDialog extends StatelessWidget {
  final bool mockMode;
  final ValueChanged<bool> onMockModeChanged;
  final RolandServiceAbstract? rolandService;
  final TextEditingController rolandIpController;
  final ValueNotifier<bool> rolandConnected;
  final ValueNotifier<bool> rolandConnecting;
  final ValueNotifier<String> rolandConnectionError;
  final VoidCallback onConnectRoland;
  final List<PanasonicCameraConfig> panasonicCameras;
  final Function(int) onConnectPanasonic;
  final ValueChanged<String> onResponse;
  final List<Position> positions;
  final List<HeightRange> heightRanges;
  final VoidCallback onPositionsChanged;
  final VoidCallback onServicesChanged;
  final VoidCallback onHeightRangesChanged;
  final VoidCallback onPeopleChanged;
  final VoidCallback onAllDataChanged;
  final DeviceConfigCallback onDeviceConfigSaved;

  // Operator
  final VoidCallback onOperatorsChanged;

  const SettingsDialog({
    super.key,
    required this.mockMode,
    required this.onMockModeChanged,
    required this.rolandService,
    required this.rolandIpController,
    required this.rolandConnected,
    required this.rolandConnecting,
    required this.rolandConnectionError,
    required this.onConnectRoland,
    required this.panasonicCameras,
    required this.onConnectPanasonic,
    required this.onResponse,
    required this.positions,
    required this.heightRanges,
    required this.onPositionsChanged,
    required this.onServicesChanged,
    required this.onHeightRangesChanged,
    required this.onPeopleChanged,
    required this.onAllDataChanged,
    required this.onDeviceConfigSaved,
    required this.onOperatorsChanged,
  });

  // ── Operator ─────────────────────────────────────────────────────────────

  void _openOperatorManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => OperatorManagerDialog(
        rolandStorageKey: 'roland_${rolandIpController.text}',
        cameras: panasonicCameras,
        onSaved: onOperatorsChanged,
      ),
    );
  }

  // ── Connections / devices ─────────────────────────────────────────────────

  void _openConnections(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ConnectionsDialog(
        rolandIpController: rolandIpController,
        rolandConnected: rolandConnected,
        rolandConnecting: rolandConnecting,
        rolandConnectionError: rolandConnectionError,
        onConnectRoland: onConnectRoland,
        panasonicCameras: panasonicCameras,
        onConnectPanasonic: onConnectPanasonic,
        onSaved: onDeviceConfigSaved,
      ),
    );
  }

  void _openMasterControl(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preset Labels & Visibility'),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 700,
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: MasterControlWidget(
            rolandService: rolandService,
            rolandConnected: rolandConnected,
            rolandIpController: rolandIpController,
            cameras: panasonicCameras,
            onResponse: onResponse,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openPinP(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PinP'),
        content: SizedBox(
          width: 500,
          child: PinPTab(
            rolandConnected: rolandConnected,
            onRolandResponse: onResponse,
            rolandService: rolandService,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ── Data managers ─────────────────────────────────────────────────────────

  void _openPositionManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PositionManagerDialog(onSaved: onPositionsChanged),
    );
  }

  void _openHeightRangeManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => HeightRangeManagerDialog(
        positions: positions,
        cameras: panasonicCameras,
        onSaved: onHeightRangesChanged,
      ),
    );
  }

  void _openServiceManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ServiceManagerDialog(
        positions: positions,
        cameras: panasonicCameras,
        onSaved: onServicesChanged,
        rolandIpController: rolandIpController,
      ),
    );
  }

  void _openPeopleManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PeopleManagerDialog(
        positions: positions,
        cameras: panasonicCameras,
        heightRanges: heightRanges,
        onSaved: onPeopleChanged,
      ),
    );
  }

  // ── Import / Export ───────────────────────────────────────────────────────

  Future<void> _exportConfig(BuildContext context) async {
    final path = ConfigBundle.suggestedExportPath();
    try {
      final bundle = await ConfigBundle.fromStores();
      await ConfigBundle.writeToPath(path, bundle);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export complete'),
          content: SelectableText(path),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export failed'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _importConfig(BuildContext context) async {
    final pathCtrl = TextEditingController();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Configuration'),
        content: TextField(
          controller: pathCtrl,
          decoration: InputDecoration(
            labelText: 'File path',
            hintText: ConfigBundle.suggestedExportPath(),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Load')),
        ],
      ),
    );

    final path = pathCtrl.text.trim();
    pathCtrl.dispose();
    if (proceed != true || path.isEmpty || !context.mounted) return;

    ConfigBundle bundle;
    try {
      bundle = await ConfigBundle.readFromPath(path);
    } catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import failed'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace all configuration?'),
        content: Text(
          'This will overwrite everything with:\n'
          '  • ${bundle.positions.length} position${bundle.positions.length == 1 ? '' : 's'}\n'
          '  • ${bundle.people.length} person${bundle.people.length == 1 ? '' : 's'}\n'
          '  • ${bundle.services.length} service${bundle.services.length == 1 ? '' : 's'}'
          '${bundle.cameras != null ? '\n  • ${bundle.cameras!.length} camera${bundle.cameras!.length == 1 ? '' : 's'} + Roland IP' : ''}'
          '${bundle.operators != null ? '\n  • ${bundle.operators!.length} operator${bundle.operators!.length == 1 ? '' : 's'}' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace all'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await bundle.saveToStores();
    if (bundle.rolandIp != null || bundle.cameras != null) {
      onDeviceConfigSaved(
        bundle.rolandIp ?? DeviceConfigStore.defaultRolandIp,
        bundle.cameras ?? DeviceConfigStore.defaultCameras,
      );
    }
    if (bundle.operators != null) {
      await OperatorStore.saveActiveId(OperatorProfile.defaultId);
      onOperatorsChanged();
    }
    onAllDataChanged();
    onResponse('Configuration imported successfully');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode toggle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      mockMode ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: mockMode
                          ? Colors.orange.shade200
                          : Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      mockMode ? Icons.visibility : Icons.wifi,
                      color: mockMode ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mockMode ? 'Demo Mode' : 'Live Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: mockMode
                                  ? Colors.orange.shade900
                                  : Colors.blue.shade900,
                            ),
                          ),
                          Text(
                            mockMode
                                ? 'UI preview without real devices'
                                : 'Connecting to actual hardware',
                            style: TextStyle(
                              fontSize: 12,
                              color: mockMode
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: mockMode, onChanged: onMockModeChanged),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Operator
              _sectionHeader('Operator'),
              _tile(
                icon: Icons.people_outline,
                title: 'Manage Operators',
                subtitle: 'Add, remove, or configure operator panels',
                onTap: () => _openOperatorManager(context),
              ),
              _tile(
                icon: Icons.dashboard_customize,
                title: 'Preset Labels & Visibility',
                subtitle: 'Name macros and presets, assign visibility tiers',
                onTap: () => _openMasterControl(context),
              ),
              const SizedBox(height: 4),

              // Manage
              _sectionHeader('Manage'),
              _tile(
                icon: Icons.place,
                title: 'Manage Positions',
                subtitle: 'Define physical locations linked to camera presets',
                onTap: () => _openPositionManager(context),
              ),
              _tile(
                icon: Icons.person_add,
                title: 'Manage People',
                subtitle: 'Add people and assign their presets per position',
                onTap: () => _openPeopleManager(context),
              ),
              _tile(
                icon: Icons.format_list_numbered,
                title: 'Manage Services',
                subtitle: 'Build service sequences with steps and participants',
                onTap: () => _openServiceManager(context),
              ),
              _tile(
                icon: Icons.height,
                title: 'Manage Height Ranges',
                subtitle:
                    'Default presets by height, used when a person has no explicit preset',
                onTap: () => _openHeightRangeManager(context),
              ),
              const SizedBox(height: 4),

              // Configure
              _sectionHeader('Configure'),
              _tile(
                icon: Icons.settings_ethernet,
                title: 'Connections',
                subtitle: 'Configure device IPs and connect/disconnect',
                onTap: () => _openConnections(context),
              ),
              _tile(
                icon: Icons.picture_in_picture,
                title: 'PinP',
                subtitle: 'Picture-in-picture source and position',
                onTap: () => _openPinP(context),
              ),
              const SizedBox(height: 4),

              // Data
              _sectionHeader('Data'),
              _tile(
                icon: Icons.upload_file,
                title: 'Export Configuration',
                subtitle: 'Save all data to a JSON file',
                onTap: () => _exportConfig(context),
              ),
              _tile(
                icon: Icons.download,
                title: 'Import Configuration',
                subtitle: 'Replace all data from a previously exported file',
                onTap: () => _importConfig(context),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 2),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Colors.grey)),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
      );
}
