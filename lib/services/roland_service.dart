import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class RolandService {
  Socket? _socket;
  final String host;
  final int port;
  
  // STX (Start of Text) - 0x02
  static const int _stx = 0x02;
  // ACK (Acknowledge) - 0x06
  static const int _ack = 0x06;
  
  bool get isConnected => _socket != null;
  
  final _controller = StreamController<String>.broadcast();
  Stream<String> get responseStream => _controller.stream;

  RolandService({required this.host, this.port = 8023});

  Future<void> connect() async {
    try {
      _socket = await Socket.connect(host, port);
      print('Connected to Roland V-60HD at $host:$port');
      
      _socket!.listen(
        (Uint8List data) {
          final response = String.fromCharCodes(data);
          _handleResponse(response);
        },
        onError: (error) {
          print('Socket error: $error');
          disconnect();
        },
        onDone: () {
          print('Socket closed');
          disconnect();
        },
      );
    } catch (e) {
      print('Failed to connect: $e');
      rethrow;
    }
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
  }

  void _handleResponse(String response) {
    // Remove STX and ACK characters for cleaner processing if needed
    // The companion module logic suggests responses might be mixed or need splitting
    // For now, we just broadcast the raw string for debugging/logging
    _controller.add(response);
  }

  /// Sends a raw command string.
  /// Automatically adds STX (0x02) prefix and semicolon suffix if missing.
  void sendCommand(String cmd) {
    if (_socket == null) {
      print('Cannot send command: Not connected');
      return;
    }

    final buffer = StringBuffer();
    
    // Add STX if not present (though usually we construct the command without it and add it here)
    buffer.writeCharCode(_stx);
    
    buffer.write(cmd);
    
    // Add semicolon if not present
    if (!cmd.endsWith(';')) {
      buffer.write(';');
    }

    try {
      _socket!.write(buffer.toString());
    } catch (e) {
      print('Error sending command: $e');
      disconnect();
    }
  }

  // --- High Level Commands ---

  /// Select Program Channel (0-7)
  /// 0-3: SDI 1-4
  /// 4-5: HDMI 5-6
  /// 6-7: STILL/BKG 7-8
  void setProgram(int input) {
    sendCommand('PGM:$input');
  }

  /// Select Preview/Preset Channel (0-7)
  void setPreview(int input) {
    sendCommand('PST:$input');
  }

  /// Select Aux Channel (0-7)
  void setAux(int input) {
    sendCommand('AUX:$input');
  }

  /// Perform Cut Transition
  void cut() {
    sendCommand('CUT');
  }

  /// Perform Auto Transition
  void auto() {
    sendCommand('ATO');
  }

  /// Set Transition Effect
  /// 0: Mix, 1: Wipe 1, 2: Wipe 2
  void setTransitionEffect(int effectId) {
    sendCommand('TRS:$effectId');
  }

  /// Set Transition Time (0-40, representing 0.0s to 4.0s)
  void setTransitionTime(int time) {
    sendCommand('TIM:$time');
  }
  
  /// Poll status (QPL:7)
  void pollStatus() {
    sendCommand('QPL:7');
  }
}
