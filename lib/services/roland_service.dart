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
    
    // Add STX if not present
    if (!cmd.startsWith(String.fromCharCode(_stx))) {
      buffer.writeCharCode(_stx);
    }
    
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

  /// Helper to send DTH (Data Transmit Hex) command
  /// [address] should be a 6-character hex string (e.g., "002100")
  /// [value] is the integer value to set
  void _sendDTH(String address, int value) {
    final valueHex = value.toRadixString(16).padLeft(2, '0').toUpperCase();
    sendCommand('DTH:$address,$valueHex');
  }

  // --- High Level Commands (V-160HD) ---

  // --- Video Switching ---

  /// Select Program Channel
  /// 0-7: HDMI 1-8
  /// 8-15: SDI 1-8
  /// 16-31: STILL 1-16
  void setProgram(int input) {
    _sendDTH('002100', input);
  }

  /// Select Preview/Preset Channel
  void setPreview(int input) {
    _sendDTH('002101', input);
  }

  /// Select Aux 1 Channel
  void setAux1(int input) {
    _sendDTH('000011', input);
  }

  /// Select Aux 2 Channel
  void setAux2(int input) {
    _sendDTH('00002E', input);
  }

  /// Select Aux 3 Channel
  void setAux3(int input) {
    _sendDTH('00002F', input);
  }

  // --- Transitions ---

  /// Perform Cut Transition
  void cut() {
    _sendDTH('0B001E', 1);
  }

  /// Perform Auto Transition
  void auto() {
    _sendDTH('0B001F', 1);
  }

  /// Set Transition Effect Type
  /// 0: Mix, 1: Wipe
  void setTransitionEffect(int effectId) {
    _sendDTH('001800', effectId);
  }

  /// Set Transition Time (0-40, representing 0.0s to 4.0s)
  void setTransitionTime(int time) {
    _sendDTH('001700', time);
  }

  // --- PinP & Key ---

  /// Set PinP & Key 1 Source
  void setPinP1Source(int input) {
    _sendDTH('001B02', input);
  }

  /// Set PinP & Key 1 On/Off (Program Layer)
  void setPinP1Program(bool enabled) {
    _sendDTH('000012', enabled ? 1 : 0);
  }

  /// Set PinP & Key 1 On/Off (Preview Layer)
  void setPinP1Preview(bool enabled) {
    _sendDTH('001B01', enabled ? 1 : 0);
  }

  // --- DSK ---

  /// Set DSK 1 Source (Key)
  void setDSK1Source(int input) {
    _sendDTH('001F03', input);
  }

  /// Set DSK 1 On/Off (Program Layer)
  void setDSK1Program(bool enabled) {
    _sendDTH('000016', enabled ? 1 : 0);
  }

  /// Set DSK 1 On/Off (Preview Layer)
  void setDSK1Preview(bool enabled) {
    _sendDTH('001F01', enabled ? 1 : 0);
  }

  // --- Split ---

  /// Set Split 1 On/Off
  void setSplit1(bool enabled) {
    _sendDTH('001900', enabled ? 1 : 0);
  }

  /// Set Split 1 Type (0: V, 1: H)
  void setSplit1Type(int type) {
    _sendDTH('001901', type);
  }

  // --- Audio ---

  /// Set Audio Input Level
  /// [inputIndex] 0-19 (Audio In 1-4, USB, BT, HDMI 1-8, SDI 1-8)
  /// [level] 0 = -INF, 100 = 0dB. Intermediate values are not yet supported.
  void setAudioInputLevel(int inputIndex, int level) {
    // Address: 01H xxH 03H
    final addr = '01${inputIndex.toRadixString(16).padLeft(2, '0')}03';
    
    // Value: 3 bytes. 
    // -INF: 7E 00 00
    // 0dB: 00 00 00
    // +10dB: 00 00 64
    String valueHex;
    if (level <= 0) {
      valueHex = '7E,00,00';
    } else if (level >= 100) {
      valueHex = '00,00,00';
    } else {
       // Fallback to 0dB for now for any positive level
       valueHex = '00,00,00';
    }
    
    sendCommand('DTH:$addr,$valueHex');
  }

  /// Set Audio Input Mute
  /// [inputIndex] 0-19
  void setAudioInputMute(int inputIndex, bool muted) {
    final addr = '01${inputIndex.toRadixString(16).padLeft(2, '0')}06';
    _sendDTH(addr, muted ? 1 : 0);
  }

  /// Set Master Output Mute
  void setMasterMute(bool muted) {
    _sendDTH('012103', muted ? 1 : 0);
  }

  // --- Camera Control ---

  /// Recall Camera Preset
  /// [cameraIndex] 0-15 (Camera 1-16)
  /// [presetIndex] 0-9 (Preset 1-10)
  void recallCameraPreset(int cameraIndex, int presetIndex) {
    final addr = '0D${cameraIndex.toRadixString(16).padLeft(2, '0')}00';
    _sendDTH(addr, presetIndex);
  }

  /// Store Camera Preset
  void storeCameraPreset(int cameraIndex, int presetIndex) {
    final addr = '0D${cameraIndex.toRadixString(16).padLeft(2, '0')}01';
    _sendDTH(addr, presetIndex);
  }

  // --- Macros & Memory ---

  /// Execute Macro (1-100)
  void executeMacro(int macroIndex) {
    // Macro 1 is 00H
    _sendDTH('500504', macroIndex - 1);
  }

  /// Load Memory (1-30)
  void loadMemory(int memoryIndex) {
    // Memory 1 is 00H
    _sendDTH('0A0000', memoryIndex - 1);
  }

  /// Save Memory (1-30)
  void saveMemory(int memoryIndex) {
    _sendDTH('0A0001', memoryIndex - 1);
  }
  
  /// Poll status (Request Program Input)
  void pollStatus() {
    // RQH: Address, Size
    // Request Program Select (002100)
    sendCommand('RQH:002100,01');
  }
}
