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
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.10');
  RolandService? _rolandService;
  bool _isConnected = false;
  String _lastResponse = '';

  @override
  void dispose() {
    _rolandService?.disconnect();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_isConnected) {
      _rolandService?.disconnect();
      setState(() {
        _isConnected = false;
        _rolandService = null;
      });
      return;
    }

    final service = RolandService(host: _ipController.text);
    try {
      await service.connect();
      setState(() {
        _rolandService = service;
        _isConnected = true;
      });
      
      service.responseStream.listen((data) {
        setState(() {
          _lastResponse = data;
        });
      });
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roland V-60HD Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Section
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_isConnected,
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _connect,
                  style: FilledButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.red : null,
                  ),
                  child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Controls Section (Only enabled when connected)
            if (_isConnected) ...[
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
                    onPressed: () => _rolandService?.setProgram(index),
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
                    onPressed: () => _rolandService?.setPreview(index),
                  );
                }),
              ),
              
              const Spacer(),
              const Divider(),
              Text('Last Response: $_lastResponse', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
