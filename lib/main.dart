import 'package:flutter/material.dart';
import 'services/roland_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roland V-60HD Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RolandControlPage(),
    );
  }
}

class RolandControlPage extends StatefulWidget {
  const RolandControlPage({super.key});

  @override
  State<RolandControlPage> createState() => _RolandControlPageState();
}

class _RolandControlPageState extends State<RolandControlPage> {
  final TextEditingController _ipController = TextEditingController(text: '10.0.1.20');
  RolandService? _rolandService;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _lastResponse = '';
  String _connectionError = '';

  @override
  void initState() {
    super.initState();
    // Auto-connect on app start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  // PinP state
  int _selectedPinP = 1;
  String _pinpSource = 'HDMI1';
  double _pinpH = 0.0;
  double _pinpV = 0.0;
  bool _pinpPgm = false;
  bool _pinpPvw = false;

  // Camera state
  int _selectedCamera = 1;
  bool _autoFocus = false;
  bool _autoExposure = false;
  int _preset = 1;
  int _panTiltSpeed = 12; // default

  @override
  void dispose() {
    _rolandService?.disconnect();
    _ipController.dispose();
    super.dispose();
  }

  // PinP methods
  void _setPinPSource() => _rolandService?.setPinPSource('PinP${_selectedPinP + 1}', _pinpSource);
  void _getPinPSource() => _rolandService?.getPinPSource('PinP${_selectedPinP + 1}');
  void _setPinPPosition() => _rolandService?.setPinPPosition('PinP${_selectedPinP + 1}', _pinpH.toInt(), _pinpV.toInt());
  void _getPinPPosition() => _rolandService?.getPinPPosition('PinP${_selectedPinP + 1}');
  void _setPinPPgm() => _rolandService?.setPinPPgm('PinP${_selectedPinP + 1}', _pinpPgm);
  void _getPinPPgm() => _rolandService?.getPinPPgm('PinP${_selectedPinP + 1}');
  void _setPinPPvw() => _rolandService?.setPinPPvw('PinP${_selectedPinP + 1}', _pinpPvw);
  void _getPinPPvw() => _rolandService?.getPinPPvw('PinP${_selectedPinP + 1}');

  // Camera methods
  void _setPanTilt(PanDirection pan, TiltDirection tilt) => _rolandService?.setPanTilt('CAMERA${_selectedCamera + 1}', pan.name.toUpperCase(), tilt.name.toUpperCase());
  void _setZoom(ZoomDirection direction) => _rolandService?.setZoom('CAMERA${_selectedCamera + 1}', direction.name.replaceAll('tele', 'TELE_').replaceAll('wide', 'WIDE_').toUpperCase());
  void _resetZoom() => _rolandService?.resetZoom('CAMERA${_selectedCamera + 1}');
  void _setFocus(FocusDirection direction) => _rolandService?.setFocus('CAMERA${_selectedCamera + 1}', direction.name.toUpperCase());
  void _setAutoFocus() => _rolandService?.setAutoFocus('CAMERA${_selectedCamera + 1}', _autoFocus);
  void _getAutoFocus() => _rolandService?.getAutoFocus('CAMERA${_selectedCamera + 1}');
  void _setAutoExposure() => _rolandService?.setAutoExposure('CAMERA${_selectedCamera + 1}', _autoExposure);
  void _getAutoExposure() => _rolandService?.getAutoExposure('CAMERA${_selectedCamera + 1}');
  void _recallPreset() => _rolandService?.recallPreset('CAMERA${_selectedCamera + 1}', 'PRESET$_preset');
  void _getCurrentPreset() => _rolandService?.getCurrentPreset('CAMERA${_selectedCamera + 1}');
  void _setPanTiltSpeed() => _rolandService?.setPanTiltSpeed('CAMERA${_selectedCamera + 1}', _panTiltSpeed);
  void _getPanTiltSpeed() => _rolandService?.getPanTiltSpeed('CAMERA${_selectedCamera + 1}');

  Future<void> _connect() async {
    if (_isConnected) {
      _rolandService?.disconnect();
      setState(() {
        _isConnected = false;
        _rolandService = null;
        _connectionError = '';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = '';
    });

    final service = RolandService(host: _ipController.text);
    try {
      await service.connect();
      setState(() {
        _rolandService = service;
        _isConnected = true;
        _isConnecting = false;
        _connectionError = '';
      });

      service.responseStream.listen((data) {
        setState(() {
          _lastResponse = data.toString();
        });
      });

    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roland V-160HD Control'),

      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isConnected && !_isConnecting,
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: _isConnecting ? null : _connect,
                        style: FilledButton.styleFrom(
                          backgroundColor: _isConnected ? Colors.red : null,
                        ),
                        child: _isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                  if (_connectionError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Connection failed. Check IP address and try again.',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Basic'),
                Tab(text: 'PinP'),
                Tab(text: 'Camera'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildBasicTab(),
                  _buildPinPTab(),
                  _buildCameraTab(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Last Response: $_lastResponse', style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicTab() {
    if (!_isConnected) return const Center(child: Text('Connect to device first'));
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Transitions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _rolandService?.cut(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('CUT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _rolandService?.auto(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('AUTO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          const Text('Program Select (PGM)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ActionChip(
                label: Text('Input ${index + 1}'),
                onPressed: () => _rolandService?.setProgram('INPUT${index + 1}'),
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('Preview Select (PST)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ActionChip(
                label: Text('Input ${index + 1}'),
                backgroundColor: Colors.green.shade50,
                onPressed: () => _rolandService?.setPreview('INPUT${index + 1}'),
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('Macros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ElevatedButton(
                onPressed: () => _rolandService?.executeMacro(index + 1),
                child: Text('Macro ${index + 1}'),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPinPTab() {
    if (!_isConnected) return const Center(child: Text('Connect to device first'));
    final sources = ['HDMI1', 'HDMI2', 'HDMI3', 'HDMI4', 'HDMI5', 'HDMI6', 'HDMI7', 'HDMI8', 'SDI1', 'SDI2', 'SDI3', 'SDI4', 'SDI5', 'SDI6', 'SDI7', 'SDI8', 'STILL1', 'STILL2', 'STILL3', 'STILL4', 'STILL5', 'STILL6', 'STILL7', 'STILL8', 'STILL9', 'STILL10', 'STILL11', 'STILL12', 'STILL13', 'STILL14', 'STILL15', 'STILL16', 'INPUT1', 'INPUT2', 'INPUT3', 'INPUT4', 'INPUT5', 'INPUT6', 'INPUT7', 'INPUT8', 'INPUT9', 'INPUT10', 'INPUT11', 'INPUT12', 'INPUT13', 'INPUT14', 'INPUT15', 'INPUT16', 'INPUT17', 'INPUT18', 'INPUT19', 'INPUT20'];
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PinP Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('PinP: '),
                DropdownButton<int>(
                  value: _selectedPinP,
                  items: List.generate(4, (i) => DropdownMenuItem(value: i+1, child: Text('PinP${i+1}'))),
                  onChanged: (v) => setState(() => _selectedPinP = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Source: '),
                DropdownButton<String>(
                  value: _pinpSource,
                  items: sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _pinpSource = v!),
                ),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setPinPSource, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPSource, child: const Text('Get')),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Position'),
            Slider(
              value: _pinpH,
              min: -1000,
              max: 1000,
              label: 'H: ${_pinpH.toInt()}',
              onChanged: (v) => setState(() => _pinpH = v),
            ),
            Slider(
              value: _pinpV,
              min: -1000,
              max: 1000,
              label: 'V: ${_pinpV.toInt()}',
              onChanged: (v) => setState(() => _pinpV = v),
            ),
            Row(
              children: [
                ElevatedButton(onPressed: _setPinPPosition, child: const Text('Set Position')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPPosition, child: const Text('Get Position')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('PGM: '),
                Switch(value: _pinpPgm, onChanged: (v) => setState(() => _pinpPgm = v)),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setPinPPgm, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPPgm, child: const Text('Get')),
              ],
            ),
            Row(
              children: [
                const Text('PVW: '),
                Switch(value: _pinpPvw, onChanged: (v) => setState(() => _pinpPvw = v)),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setPinPPvw, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPPvw, child: const Text('Get')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraTab() {
    if (!_isConnected) return const Center(child: Text('Connect to device first'));
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Camera Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Camera: '),
                DropdownButton<int>(
                  value: _selectedCamera,
                  items: List.generate(16, (i) => DropdownMenuItem(value: i+1, child: Text('Camera${i+1}'))),
                  onChanged: (v) => setState(() => _selectedCamera = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Pan/Tilt'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(onPressed: () => _setPanTilt(PanDirection.left, TiltDirection.stop), child: const Text('LEFT')),
                const SizedBox(width: 8),
                Column(
                  children: [
                    ElevatedButton(onPressed: () => _setPanTilt(PanDirection.stop, TiltDirection.up), child: const Text('UP')),
                    ElevatedButton(onPressed: () => _setPanTilt(PanDirection.stop, TiltDirection.stop), child: const Text('STOP')),
                    ElevatedButton(onPressed: () => _setPanTilt(PanDirection.stop, TiltDirection.down), child: const Text('DOWN')),
                  ],
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => _setPanTilt(PanDirection.right, TiltDirection.stop), child: const Text('RIGHT')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Speed: '),
                Expanded(
                  child: Slider(
                    value: _panTiltSpeed.toDouble(),
                    min: 1,
                    max: 24,
                    label: '$_panTiltSpeed',
                    onChanged: (v) => setState(() => _panTiltSpeed = v.toInt()),
                  ),
                ),
                ElevatedButton(onPressed: _setPanTiltSpeed, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPanTiltSpeed, child: const Text('Get')),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Zoom'),
            Row(
              children: [
                ElevatedButton(onPressed: () => _setZoom(ZoomDirection.wideFast), child: const Text('WIDE FAST')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => _setZoom(ZoomDirection.stop), child: const Text('STOP')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => _setZoom(ZoomDirection.teleFast), child: const Text('TELE FAST')),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _resetZoom, child: const Text('Reset Zoom')),
            const SizedBox(height: 16),
            const Text('Focus'),
            Row(
              children: [
                ElevatedButton(onPressed: () => _setFocus(FocusDirection.near), child: const Text('NEAR')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => _setFocus(FocusDirection.stop), child: const Text('STOP')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => _setFocus(FocusDirection.far), child: const Text('FAR')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Auto Focus: '),
                Switch(value: _autoFocus, onChanged: (v) => setState(() => _autoFocus = v)),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setAutoFocus, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getAutoFocus, child: const Text('Get')),
              ],
            ),
            Row(
              children: [
                const Text('Auto Exposure: '),
                Switch(value: _autoExposure, onChanged: (v) => setState(() => _autoExposure = v)),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setAutoExposure, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getAutoExposure, child: const Text('Get')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Preset: '),
                DropdownButton<int>(
                  value: _preset,
                  items: List.generate(20, (i) => DropdownMenuItem(value: i+1, child: Text('Preset${i+1}'))),
                  onChanged: (v) => setState(() => _preset = v!),
                ),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _recallPreset, child: const Text('Recall')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getCurrentPreset, child: const Text('Get Current')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
