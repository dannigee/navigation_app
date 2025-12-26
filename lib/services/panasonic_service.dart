import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Custom exception for camera-related errors.
class CameraException implements Exception {
  final String message;
  CameraException(this.message);

  @override
  String toString() => 'CameraException: $message';
}

/// Custom exception for camera protocol errors (e.g., ER1, ER2, ER3).
class CameraProtocolException extends CameraException {
  CameraProtocolException(String code) : super('Protocol error: $code');
}

/// Custom exception for network-related errors.
class NetworkException extends CameraException {
  NetworkException(String message) : super('Network error: $message');
}

/// Custom exception for protocol response parsing errors.
class ProtocolException extends CameraException {
  ProtocolException(String message) : super('Protocol parsing error: $message');
}

/// Represents the current position data from the camera.
class CameraPosition {
  final String pan;
  final String tilt;
  final String zoom;
  final String focus;
  final String iris;

  CameraPosition({
    required this.pan,
    required this.tilt,
    required this.zoom,
    required this.focus,
    required this.iris,
  });

  @override
  String toString() =>
      'Pan: $pan, Tilt: $tilt, Zoom: $zoom, Focus: $focus, Iris: $iris';
}

/// Enums for various camera modes.
enum FocusMode { manual, auto }
enum IrisMode { manual, auto }
enum WhiteBalanceMode { atw, awcA, awcB, k3200, k5600, variable }
enum ShutterMode { off, step, synchro, elc }
enum NdFilter { through, quarter, sixteenth, sixtyFourth }
enum GainMode { manual, agc }
enum SceneFile { none, scene1, scene2, scene3, scene4, scene5 }

/// Manages a queue for PTZ commands to enforce delays between executions.
class CommandQueue {
  final Duration delay;
  final Queue<Future<String> Function()> _queue = Queue<Future<String> Function()>();
  bool _isProcessing = false;
  DateTime? _lastCommandTime;

  CommandQueue(this.delay);

  /// Adds a command to the queue and processes it.
  Future<String> addCommand(Future<String> Function() command) async {
    final completer = Completer<String>();
    _queue.add(() async {
      try {
        final result = await command();
        completer.complete(result);
        return result;
      } catch (e) {
        completer.completeError(e);
        rethrow;
      }
    });
    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      // Enforce delay between commands
      final now = DateTime.now();
      if (_lastCommandTime != null) {
        final elapsed = now.difference(_lastCommandTime!);
        if (elapsed < delay) {
          await Future.delayed(delay - elapsed);
        }
      }
      _lastCommandTime = DateTime.now();

      final commandFunc = _queue.removeFirst();
      await commandFunc();
    }
    _isProcessing = false;
  }
}

/// Manages TCP-based event notifications for the camera.
class NotificationManager {
  ServerSocket? _server;
  StreamController<Object>? _controller;
  final http.Client _httpClient;
  final String _ipAddress;
  final Duration _timeout;
  final bool _useHttps;

  NotificationManager(this._httpClient, this._ipAddress, this._timeout, {bool useHttps = false}) : _useHttps = useHttps;

  /// Starts receiving event notifications via TCP.
  /// Initiates HTTP request to start notifications, then listens on the specified TCP port.
  /// Returns a Stream of notification objects (String for regular, Map for lens positions).
  /// Throws CameraException on error.
  Future<Stream<Object>> startNotifications(int port, {InternetAddress? bindAddress}) async {
    await _startNotificationHttp(port);
    return _setupTcpListener(port, bindAddress);
  }

  Future<void> _startNotificationHttp(int port) async {
    final protocol = _useHttps ? 'https' : 'http';
    final url = '$protocol://$_ipAddress/cgi-bin/event?connect=start&my_port=$port&uid=0';
    final response = await _httpClient.get(Uri.parse(url)).timeout(_timeout);

    if (response.statusCode != 204) {
      throw CameraException('Failed to start notifications: ${response.statusCode}');
    }
  }

  Future<Stream<Object>> _setupTcpListener(int port, InternetAddress? bindAddress) async {
    final address = bindAddress ?? InternetAddress.anyIPv4;
    _server = await ServerSocket.bind(address, port);
    _controller = StreamController<Object>();

    _server!.listen(_handleTcpConnection);

    return _controller!.stream;
  }

  void _handleTcpConnection(Socket socket) {
    final buffer = <int>[];
    socket.listen(
      (data) => _processTcpData(data, buffer),
      onError: (error) => _controller!.addError(NetworkException('TCP error: $error')),
      onDone: () => socket.close(),
    );
  }

  void _processTcpData(List<int> data, List<int> buffer) {
    buffer.addAll(data);
    while (true) {
      final index = buffer.indexOf(13); // \r
      if (index == -1 || index + 1 >= buffer.length || buffer[index + 1] != 10) break; // \n
      final messageBytes = buffer.sublist(0, index);
      buffer.removeRange(0, index + 2);
      final notification = String.fromCharCodes(messageBytes).trim();
      final cleaned = notification.replaceAll('\r\n', '').replaceAll('\n', '');
      _controller!.add(_parseNotification(cleaned));
    }
  }

  Object _parseNotification(String cleaned) {
    if (cleaned.startsWith(NotificationManager.lensPositionPrefix)) {
      final dataPart = cleaned.substring(3);
      if (PanasonicService.hex9Regex.hasMatch(dataPart)) {
        return Map<String, String>.fromEntries([
          MapEntry('zoom', dataPart.substring(0, 3)),
          MapEntry('focus', dataPart.substring(3, 6)),
          MapEntry('iris', dataPart.substring(6, 9)),
        ]);
      } else {
        return cleaned; // Fallback
      }
    } else if (cleaned.startsWith('pTV')) {
      // Handle position change notifications
      try {
        final ptvRegex = RegExp(r'^pTV([0-9A-Fa-f]{4})([0-9A-Fa-f]{4})([0-9A-Fa-f]{3})([0-9A-Fa-f]{3})([0-9A-Fa-f]{3})$');
        final match = ptvRegex.firstMatch(cleaned);
        if (match != null) {
          return {
            'type': 'position',
            'pan': match.group(1)!,
            'tilt': match.group(2)!,
            'zoom': match.group(3)!,
            'focus': match.group(4)!,
            'iris': match.group(5)!,
          };
        }
      } catch (e) {
        // Log error but continue
        log('Error parsing position notification: $e', name: 'NotificationManager');
      }
      return cleaned;
    } else {
      return cleaned;
    }
  }

  /// Stops receiving event notifications.
  /// Closes the TCP server and stream.
  /// Throws CameraException on error.
  Future<String> stopNotifications(int port) async {
    final protocol = _useHttps ? 'https' : 'http';
    final url = '$protocol://$_ipAddress/cgi-bin/event?connect=stop&my_port=$port&uid=0';
    final response = await _httpClient.get(Uri.parse(url)).timeout(_timeout);

    if (response.statusCode != 204) {
      throw CameraException('Failed to stop notifications: ${response.statusCode}');
    }

    await _controller?.close();
    await _server?.close();
    _server = null;
    _controller = null;

    return 'Stopped';
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await _controller?.close();
    await _server?.close();
  }

  static const String lensPositionPrefix = 'lPI';
}

/// Service for controlling Panasonic AW-UE100 camera via HTTP API.
/// 
/// Changelog:
/// - v1.0: Initial implementation with basic commands.
/// - v1.1: Added enhanced error handling with NetworkException and ProtocolException.
/// - v1.1: Improved response parsing with regex validation.
/// - v1.1: Added getAllLensPositions for individual lens queries.
/// - v1.1: Refactored notification setup into helper methods.
/// - v1.1: Expanded unit tests for error scenarios.
/// - v1.2: Refactored PTZ queue into separate CommandQueue class.
/// - v1.2: Made delays and retries configurable.
/// - v1.2: Enhanced notification parsing for position changes.
/// - v1.2: Added stricter response validation.
/// - v1.2: Added query methods for current settings.
class PanasonicService {
  static const String ptzEndpoint = 'aw_ptz';
  static const String camEndpoint = 'aw_cam';
  static const Duration defaultPtzCommandDelay = Duration(milliseconds: 40);
  static const Duration defaultRequestTimeout = Duration(seconds: 5);
  static const int defaultMaxRetries = 3;

  // Command constants
  static const String powerOnCmd = '#O1';
  static const String powerOffCmd = '#O0';
  static const String getCameraInfoCmd = 'QID';
  static const String getVersionCmd = 'QSV';
  static const String getPtzvCmd = '#PTV';
  static const String getZoomCmd = '#GZ';
  static const String getFocusCmd = '#GF';
  static const String getIrisCmd = '#GI';
  static const String getErrorCmd = '#RER';
  static const String setPanSpeedCmd = '#P';
  static const String setTiltSpeedCmd = '#T';
  static const String setPanTiltSpeedCmd = '#PTS';
  static const String setAbsolutePositionCmd = '#APC';
  static const String setAbsolutePositionWithSpeedCmd = '#APS';
  static const String setInstallPositionCmd = '#INS';
  static const String setZoomSpeedCmd = '#Z';
  static const String setZoomPositionCmd = '#AXZ';
  static const String setDigitalZoomCmd = 'OSE:70:';
  static const String setDigitalZoomMagnificationCmd = 'OSE:76:';
  static const String setFocusModeCmd = 'OAF:';
  static const String setFocusModePtzCmd = '#D1';
  static const String setFocusSpeedCmd = '#F';
  static const String setFocusPositionCmd = '#AXF';
  static const String pushAutoFocusCmd = 'OSE:69:1';
  static const String setIrisModeCmd = 'ORS:';
  static const String setIrisModePtzCmd = '#D3';
  static const String setIrisPositionCmd = '#AXI';
  static const String setIrisSpeedCmd = '#I';
  static const String recallPresetCmd = '#R';
  static const String savePresetCmd = '#M';
  static const String deletePresetCmd = '#C';
  static const String setPresetSpeedCmd = '#UPVS';
  static const String savePresetNameCmd = 'OSJ:35:';
  static const String setGainCmd = 'OGU:';
  static const String setShutterModeCmd = 'OSJ:03:';
  static const String setShutterSpeedCmd = 'OSJ:06:';
  static const String setNdFilterCmd = 'OFT:';
  static const String setWhiteBalanceModeCmd = 'OAW:';
  static const String executeAutoWhiteBalanceCmd = 'OWS';
  static const String setColorTemperatureCmd = 'OSI:20:';
  static const String setRGainCmd = 'OSG:39:';
  static const String setBGainCmd = 'OSG:3A:';
  static const String setSceneFileCmd = 'XSF:';
  static const String setColorBarCmd = 'DCB:';
  static const String setTallyEnableCmd = '#TAE';
  static const String setRedTallyCmd = 'TLR:';
  static const String setGreenTallyCmd = 'TLG:';
  static const String setLensPositionContinuousCmd = '#LPC';

  // Response prefixes
  static const String ptzResponsePrefix = 'pTV';
  static const String zoomResponsePrefix = 'gz';
  static const String focusResponsePrefix = 'gf';
  static const String irisResponsePrefix = 'gi';
  static const String errorResponsePrefix = 'rER';
  static const String lensPositionPrefix = 'lPI';

  // Position ranges
  static const String minPosition = '555';
  static const String maxPosition = 'FFF';

  // Pre-compiled regex for performance
  static final RegExp ipRegex = RegExp(r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$');
  static final RegExp hex3Regex = RegExp(r'^[0-9A-Fa-f]{3}$');
  static final RegExp hex4Regex = RegExp(r'^[0-9A-Fa-f]{4}$');
  static final RegExp hex9Regex = RegExp(r'^[0-9A-Fa-f]{9}$');
  static final RegExp hex17Regex = RegExp(r'^[0-9A-Fa-f]{17}$');
  static final RegExp asciiRegex = RegExp(r'^[\x20-\x7E]*$');

  final String ipAddress;
  final http.Client _client;
  final Duration requestTimeout;
  final bool useHttps;
  final int maxRetries;
  final CommandQueue _ptzCommandQueue;
  final NotificationManager _notificationManager;

  PanasonicService({
    required this.ipAddress,
    http.Client? client,
    this.requestTimeout = defaultRequestTimeout,
    this.useHttps = false,
    Duration ptzCommandDelay = defaultPtzCommandDelay,
    this.maxRetries = defaultMaxRetries,
  }) : _client = client ?? http.Client(),
       _ptzCommandQueue = CommandQueue(ptzCommandDelay),
       _notificationManager = NotificationManager(client ?? http.Client(), ipAddress, requestTimeout, useHttps: useHttps) {
    // Validate IP address
    if (!ipRegex.hasMatch(ipAddress)) {
      throw ArgumentError('Invalid IP address format');
    }
  }

  String _encodeCommand(String command) {
    return command.replaceAll('#', '%23');
  }

  void _validateSpeed(int speed) {
    if (speed < 1 || speed > 99) {
      throw ArgumentError('Speed must be between 1 and 99');
    }
  }

  void _validateHexPosition(String position, {bool is4Char = false}) {
    final regex = is4Char ? hex4Regex : hex3Regex;
    if (!regex.hasMatch(position)) {
      throw ArgumentError('Position must be ${is4Char ? 4 : 3}-character hex string');
    }
    final posValue = int.parse(position, radix: 16);
    final minValue = int.parse(minPosition, radix: 16);
    final maxValue = int.parse(maxPosition, radix: 16);
    if (posValue < minValue || posValue > maxValue) {
      throw ArgumentError('Position must be between $minPosition and $maxPosition');
    }
  }

  String _buildSpeedCommand(String prefix, int speed) {
    _validateSpeed(speed);
    return '$prefix${speed.toString().padLeft(2, '0')}';
  }

  String _buildPositionCommand(String prefix, String position) {
    _validateHexPosition(position);
    return '$prefix$position';
  }

  /// Sends a command to the camera and handles response parsing and errors.
  Future<String> _sendCommand(String endpoint, String command, {bool isPtz = false}) async {
    if (isPtz) {
      return _ptzCommandQueue.addCommand(() => _executeCommand(endpoint, command));
    }
    return _executeCommand(endpoint, command);
  }

  Future<String> _executeCommand(String endpoint, String command) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final protocol = useHttps ? 'https' : 'http';
        final url = '$protocol://$ipAddress/cgi-bin/$endpoint?cmd=${_encodeCommand(command)}&res=1';
        log('Sending command to $url', name: 'PanasonicService');
        final response = await _client.get(Uri.parse(url)).timeout(requestTimeout);

        if (response.statusCode != 200) {
          log('HTTP error: ${response.statusCode} for command $command', name: 'PanasonicService', level: 900);
          throw CameraException('HTTP ${response.statusCode}: ${response.body}');
        }

        final body = response.body.trim();
        final cleanedResponse = body.startsWith('"') && body.endsWith('"')
            ? body.substring(1, body.length - 1)
            : body;

        // Validate response format more strictly
        if (!cleanedResponse.contains(RegExp(r'^[a-zA-Z0-9#:\-\.]+$'))) {
          log('Warning: Response does not match expected format: $cleanedResponse', name: 'PanasonicService', level: 700);
        }

        log('Received response: $cleanedResponse for command $command', name: 'PanasonicService');

        // Check for protocol errors
        if (cleanedResponse.startsWith('ER')) {
          log('Protocol error: $cleanedResponse', name: 'PanasonicService', level: 900);
          // Special handling for ER2 (busy): retry with delay
          if (cleanedResponse == 'ER2') {
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          throw CameraProtocolException(cleanedResponse);
        }

        return cleanedResponse;
      } on TimeoutException catch (e) {
        log('Timeout on attempt ${attempt + 1} for command $command: $e', name: 'PanasonicService', level: 800);
        if (attempt == maxRetries - 1) {
          throw NetworkException('Request timed out after $maxRetries attempts: $e');
        }
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1))); // Exponential backoff
      } on SocketException catch (e) {
        log('Network error on attempt ${attempt + 1} for command $command: $e', name: 'PanasonicService', level: 800);
        if (attempt == maxRetries - 1) {
          throw NetworkException('Network error after $maxRetries attempts: $e');
        }
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw CameraException('Unexpected error in _executeCommand');
  }

  // Power & System Control
  /// Powers on the camera.
  ///
  /// Sends command #O1 to turn on the camera.
  ///
  /// Returns response like 'p1' on success.
  ///
  /// Throws [CameraException] on error.
  ///
  /// See panasonic-ue100-commands.md section "Power & System Control"
  Future<String> powerOn() async {
    return await _sendCommand(ptzEndpoint, powerOnCmd, isPtz: true);
  }

  /// Powers off the camera.
  ///
  /// Sends command #O0 to turn off the camera.
  ///
  /// Returns response like 'p0' on success.
  ///
  /// Throws [CameraException] on error.
  Future<String> powerOff() async {
    return await _sendCommand(ptzEndpoint, powerOffCmd, isPtz: true);
  }

  /// Retrieves camera information.
  ///
  /// Sends QID command.
  ///
  /// Returns response like 'OID:AW-UE100'.
  ///
  /// Throws [CameraException] on error.
  Future<String> getCameraInfo() async {
    return await _sendCommand(camEndpoint, getCameraInfoCmd);
  }

  /// Retrieves camera version.
  ///
  /// Sends QSV command.
  ///
  /// Returns response like 'OSV:[Version]'.
  ///
  /// Throws [CameraException] on error.
  Future<String> getVersion() async {
    return await _sendCommand(camEndpoint, getVersionCmd);
  }

  // Pan/Tilt Control
  /// Sets the pan speed.
  ///
  /// [speed] The pan speed value (1-49 left, 50 stop, 51-99 right).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setPanSpeed(int speed) async {
    final cmd = _buildSpeedCommand(setPanSpeedCmd, speed);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets the tilt speed.
  ///
  /// [speed] The tilt speed value (1-49 down, 50 stop, 51-99 up).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setTiltSpeed(int speed) async {
    final cmd = _buildSpeedCommand(setTiltSpeedCmd, speed);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets combined pan and tilt speeds.
  ///
  /// [panSpeed] The pan speed (1-99).
  /// [tiltSpeed] The tilt speed (1-99).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speeds are out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setPanTiltSpeed(int panSpeed, int tiltSpeed) async {
    if (panSpeed < 1 || panSpeed > 99 || tiltSpeed < 1 || tiltSpeed > 99) {
      throw ArgumentError('Pan and tilt speeds must be between 1 and 99');
    }
    final cmd = '$setPanTiltSpeedCmd${panSpeed.toString().padLeft(2, '0')}${tiltSpeed.toString().padLeft(2, '0')}';
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets absolute pan and tilt positions.
  ///
  /// [panPos] Pan position (4-character hex).
  /// [tiltPos] Tilt position (4-character hex).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if positions are invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setAbsolutePosition(String panPos, String tiltPos) async {
    _validateHexPosition(panPos, is4Char: true);
    _validateHexPosition(tiltPos, is4Char: true);
    final cmd = '#APC$panPos$tiltPos';
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets absolute position with speed.
  ///
  /// [panPos] Pan position (4-character hex).
  /// [tiltPos] Tilt position (4-character hex).
  /// [speed] Speed (1-30).
  /// [speedTable] Speed table (0-2).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if parameters are invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setAbsolutePositionWithSpeed(String panPos, String tiltPos, int speed, int speedTable) async {
    _validateHexPosition(panPos, is4Char: true);
    _validateHexPosition(tiltPos, is4Char: true);
    if (speed < 1 || speed > 30 || speedTable < 0 || speedTable > 2) {
      throw ArgumentError('Speed must be 1-30, speedTable 0-2');
    }
    final cmd = '#APS$panPos$tiltPos${speed.toString().padLeft(2, '0')}$speedTable';
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets install position (flip).
  ///
  /// [hanging] True for hanging, false for desktop.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setInstallPosition(bool hanging) async {
    final data = hanging ? '1' : '0';
    return await _sendCommand(ptzEndpoint, '#INS$data', isPtz: true);
  }

  // Zoom Control
  /// Sets zoom speed.
  ///
  /// [speed] The zoom speed value (1-49 wide, 50 stop, 51-99 tele).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setZoomSpeed(int speed) async {
    final cmd = _buildSpeedCommand(setZoomSpeedCmd, speed);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets zoom position.
  ///
  /// [position] The zoom position in hex (3-character).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if position is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setZoomPosition(String position) async {
    final cmd = _buildPositionCommand(setZoomPositionCmd, position);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Enables or disables digital zoom.
  ///
  /// [enabled] True to enable, false to disable.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setDigitalZoom(bool enabled) async {
    final data = enabled ? '1' : '0';
    return await _sendCommand(camEndpoint, '$setDigitalZoomCmd$data');
  }

  /// Sets digital zoom magnification.
  ///
  /// [magnification] The magnification value as a 4-digit string (0100-9999).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if magnification is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setDigitalZoomMagnification(String magnification) async {
    if (!RegExp(r'^\d{4}$').hasMatch(magnification) || int.parse(magnification) < 100 || int.parse(magnification) > 9999) {
      throw ArgumentError('Magnification must be 0100-9999');
    }
    return await _sendCommand(camEndpoint, '$setDigitalZoomMagnificationCmd$magnification');
  }

  // Focus Control
  /// Sets focus mode.
  ///
  /// [mode] The focus mode (manual or auto).
  ///
  /// Sends OAF command.
  ///
  /// Returns response on success.
  ///
  /// Throws [CameraException] on error.
  Future<String> setFocusMode(FocusMode mode) async {
    final data = mode == FocusMode.auto ? '1' : '0';
    return await _sendCommand(camEndpoint, 'OAF:$data');
  }

  /// Alternative method to set focus mode using PTZ command.
  ///
  /// [mode] The focus mode (manual or auto).
  ///
  /// Sends #D1 command.
  ///
  /// Returns response on success.
  ///
  /// Throws [CameraException] on error.
  Future<String> setFocusModePtz(FocusMode mode) async {
    final data = mode == FocusMode.auto ? '1' : '0';
    return await _sendCommand(ptzEndpoint, '#D1$data', isPtz: true);
  }

  /// Sets focus speed in manual mode.
  ///
  /// [speed] Speed (1-99, 1-49 near, 50 stop, 51-99 far).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setFocusSpeed(int speed) async {
    final cmd = _buildSpeedCommand('#F', speed);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets focus position.
  ///
  /// [position] Position (3-character hex).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if position is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setFocusPosition(String position) async {
    final cmd = _buildPositionCommand('#AXF', position);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Triggers push auto focus.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> pushAutoFocus() async {
    return await _sendCommand(camEndpoint, 'OSE:69:1');
  }

  // Iris Control
  /// Sets iris mode.
  ///
  /// [mode] The iris mode (manual or auto).
  ///
  /// Sends ORS command.
  ///
  /// Returns response on success.
  ///
  /// Throws [CameraException] on error.
  Future<String> setIrisMode(IrisMode mode) async {
    final data = mode == IrisMode.auto ? '1' : '0';
    return await _sendCommand(camEndpoint, 'ORS:$data');
  }

  /// Alternative method to set iris mode using PTZ command.
  ///
  /// [mode] The iris mode (manual or auto).
  ///
  /// Sends #D3 command.
  ///
  /// Returns response on success.
  ///
  /// Throws [CameraException] on error.
  Future<String> setIrisModePtz(IrisMode mode) async {
    final data = mode == IrisMode.auto ? '1' : '0';
    return await _sendCommand(ptzEndpoint, '#D3$data', isPtz: true);
  }

  /// Sets iris position in manual mode.
  ///
  /// [position] Position (3-character hex).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if position is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setIrisPosition(String position) async {
    final cmd = _buildPositionCommand('#AXI', position);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets iris speed.
  ///
  /// [speed] Speed (1-99).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setIrisSpeed(int speed) async {
    final cmd = _buildSpeedCommand('#I', speed);
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  // Preset Management
  /// Recalls a preset.
  ///
  /// [presetNum] Preset number (0-99).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if preset number is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> recallPreset(int presetNum) async {
    if (presetNum < 0 || presetNum > 99) {
      throw ArgumentError('Preset number must be 0-99');
    }
    final cmd = '#R${presetNum.toString().padLeft(2, '0')}';
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Saves current position as preset.
  ///
  /// [presetNum] Preset number (0-99).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if preset number is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> savePreset(int presetNum) async {
    if (presetNum < 0 || presetNum > 99) {
      throw ArgumentError('Preset number must be 0-99');
    }
    final cmd = '#M${presetNum.toString().padLeft(2, '0')}';
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Deletes a preset.
  ///
  /// [presetNum] Preset number (0-99).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if preset number is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> deletePreset(int presetNum) async {
    if (presetNum < 0 || presetNum > 99) {
      throw ArgumentError('Preset number must be 0-99');
    }
    final cmd = '#C${presetNum.toString().padLeft(2, '0')}';
    return await _sendCommand(ptzEndpoint, cmd, isPtz: true);
  }

  /// Sets preset speed.
  ///
  /// [speed] Speed (001-999).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setPresetSpeed(String speed) async {
    if (!RegExp(r'^\d{3}$').hasMatch(speed) || int.parse(speed) < 1 || int.parse(speed) > 999) {
      throw ArgumentError('Preset speed must be 001-999');
    }
    return await _sendCommand(ptzEndpoint, '#UPVS$speed', isPtz: true);
  }

  /// Saves preset name.
  ///
  /// [presetNum] Preset number (0-99).
  /// [name] Name (up to 15 ASCII characters).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if parameters are invalid.
  /// Throws [CameraException] on communication error.
  Future<String> savePresetName(int presetNum, String name) async {
    if (presetNum < 0 || presetNum > 99) {
      throw ArgumentError('Preset number must be 0-99');
    }
    if (name.length > 15 || !asciiRegex.hasMatch(name)) {
      throw ArgumentError('Name must be up to 15 ASCII characters');
    }
    return await _sendCommand(camEndpoint, 'OSJ:35:$presetNum:$name');
  }

  // Exposure Control
  /// Sets gain.
  ///
  /// [gain] Gain (8-32 or 80 for AGC).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if gain is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setGain(int gain) async {
    if ((gain < 8 || gain > 32) && gain != 80) {
      throw ArgumentError('Gain must be 8-32 or 80');
    }
    final gainStr = gain.toString().padLeft(2, '0');
    return await _sendCommand(camEndpoint, 'OGU:$gainStr');
  }

  /// Sets shutter mode.
  ///
  /// [mode] Mode (0-3).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if mode is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setShutterMode(int mode) async {
    if (mode < 0 || mode > 3) {
      throw ArgumentError('Shutter mode must be 0-3');
    }
    return await _sendCommand(camEndpoint, 'OSJ:03:$mode');
  }

  /// Sets shutter speed in step mode.
  ///
  /// [speed] Speed (4-character hex).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if speed is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setShutterSpeed(String speed) async {
    if (!RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(speed)) {
      throw ArgumentError('Shutter speed must be 4-character hex string');
    }
    return await _sendCommand(camEndpoint, 'OSJ:06:$speed');
  }

  /// Sets ND filter.
  ///
  /// [filter] Filter (0-3).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if filter is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setNdFilter(int filter) async {
    if (filter < 0 || filter > 3) {
      throw ArgumentError('ND filter must be 0-3');
    }
    return await _sendCommand(camEndpoint, 'OFT:$filter');
  }

  // White Balance
  /// Sets white balance mode.
  ///
  /// [mode] The white balance mode.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setWhiteBalanceMode(WhiteBalanceMode mode) async {
    int data;
    switch (mode) {
      case WhiteBalanceMode.atw:
        data = 0;
        break;
      case WhiteBalanceMode.awcA:
        data = 1;
        break;
      case WhiteBalanceMode.awcB:
        data = 2;
        break;
      case WhiteBalanceMode.k3200:
        data = 4;
        break;
      case WhiteBalanceMode.k5600:
        data = 5;
        break;
      case WhiteBalanceMode.variable:
        data = 9;
        break;
    }
    return await _sendCommand(camEndpoint, 'OAW:$data');
  }

  /// Executes auto white balance.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> executeAutoWhiteBalance() async {
    return await _sendCommand(camEndpoint, 'OWS');
  }

  /// Sets color temperature in VAR mode.
  ///
  /// [temp] Temperature (4-character hex).
  /// [status] Status (0-2).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if parameters are invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setColorTemperature(String temp, int status) async {
    if (!hex4Regex.hasMatch(temp) || status < 0 || status > 2) {
      throw ArgumentError('Temp must be 4-char hex, status 0-2');
    }
    final tempValue = int.parse(temp, radix: 16);
    if (tempValue < 0x7D0 || tempValue > 0x3A98) {
      throw ArgumentError('Temp must be between 007D0 and 03A98');
    }
    return await _sendCommand(camEndpoint, '$setColorTemperatureCmd$temp:$status');
  }

  /// Sets R gain.
  ///
  /// [gain] Gain (3-character hex, 738-8C8).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if gain is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setRGain(String gain) async {
    if (!hex3Regex.hasMatch(gain)) {
      throw ArgumentError('R gain must be 3-character hex string');
    }
    final gainValue = int.parse(gain, radix: 16);
    if (gainValue < 0x738 || gainValue > 0x8C8) {
      throw ArgumentError('R gain must be between 738 and 8C8');
    }
    return await _sendCommand(camEndpoint, '$setRGainCmd$gain');
  }

  /// Sets B gain.
  ///
  /// [gain] Gain (3-character hex, 738-8C8).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if gain is invalid.
  /// Throws [CameraException] on communication error.
  Future<String> setBGain(String gain) async {
    if (!hex3Regex.hasMatch(gain)) {
      throw ArgumentError('B gain must be 3-character hex string');
    }
    final gainValue = int.parse(gain, radix: 16);
    if (gainValue < 0x738 || gainValue > 0x8C8) {
      throw ArgumentError('B gain must be between 738 and 8C8');
    }
    return await _sendCommand(camEndpoint, '$setBGainCmd$gain');
  }

  // Scene Files
  /// Sets scene file.
  ///
  /// [scene] Scene (0-4).
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [ArgumentError] if scene is out of range.
  /// Throws [CameraException] on communication error.
  Future<String> setSceneFile(int scene) async {
    if (scene < 0 || scene > 4) {
      throw ArgumentError('Scene must be 0-4');
    }
    return await _sendCommand(camEndpoint, 'XSF:$scene');
  }

  // Output & Display
  /// Sets color bar.
  ///
  /// [enabled] True for color bar, false for camera.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setColorBar(bool enabled) async {
    final data = enabled ? '1' : '0';
    return await _sendCommand(camEndpoint, 'DCB:$data');
  }

  /// Enables or disables tally.
  ///
  /// [enabled] True to enable.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setTallyEnable(bool enabled) async {
    final data = enabled ? '1' : '0';
    return await _sendCommand(ptzEndpoint, '#TAE$data', isPtz: true);
  }

  /// Sets red tally.
  ///
  /// [on] True for on, false for off.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setRedTally(bool on) async {
    final data = on ? '1' : '0';
    return await _sendCommand(camEndpoint, 'TLR:$data');
  }

  /// Sets green tally.
  ///
  /// [on] True for on, false for off.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setGreenTally(bool on) async {
    final data = on ? '1' : '0';
    return await _sendCommand(camEndpoint, 'TLG:$data');
  }

  // Status Query Commands
  CameraPosition _parsePtvResponse(String response) {
    final ptvRegex = RegExp(r'^pTV([0-9A-Fa-f]{4})([0-9A-Fa-f]{4})([0-9A-Fa-f]{3})([0-9A-Fa-f]{3})([0-9A-Fa-f]{3})$');
    final match = ptvRegex.firstMatch(response);
    if (match == null) {
      throw ProtocolException('Invalid PTV response format: $response');
    }
    return CameraPosition(
      pan: match.group(1)!,
      tilt: match.group(2)!,
      zoom: match.group(3)!,
      focus: match.group(4)!,
      iris: match.group(5)!,
    );
  }

  /// Gets pan/tilt/zoom/focus/iris positions.
  ///
  /// Sends #PTV command.
  ///
  /// Returns a CameraPosition object with parsed values.
  ///
  /// Throws [ProtocolException] on error or parsing failure.
  ///
  /// See panasonic-ue100-commands.md section "Status Query Commands"
  Future<CameraPosition> getPanTiltZoomFocusIris() async {
    final response = await _sendCommand(ptzEndpoint, getPtzvCmd, isPtz: true);
    return _parsePtvResponse(response);
  }

  /// Gets all lens positions (zoom, focus, iris) individually.
  ///
  /// Returns a map with 'zoom', 'focus', 'iris' as 3-char hex strings.
  ///
  /// Useful for consistency with individual queries.
  ///
  /// Throws [ProtocolException] or [NetworkException] on error.
  Future<Map<String, String>> getAllLensPositions() async {
    final zoom = await getZoomPosition();
    final focus = await getFocusPosition();
    final iris = await getIrisPosition();
    return {'zoom': zoom, 'focus': focus.split(':')[0], 'iris': iris.split(':')[0]};
  }

  /// Gets zoom position.
  ///
  /// Returns the zoom position as a 3-character hex string.
  ///
  /// Throws [ProtocolException] on invalid response.
  /// Throws [NetworkException] on communication error.
  Future<String> getZoomPosition() async {
    final response = await _sendCommand(ptzEndpoint, getZoomCmd, isPtz: true);
    final zoomRegex = RegExp(r'^gz([0-9A-Fa-f]{3})$');
    final match = zoomRegex.firstMatch(response);
    if (match == null) {
      throw ProtocolException('Invalid zoom response: $response');
    }
    return match.group(1)!;
  }

  /// Gets focus position.
  ///
  /// Returns the focus position as a 3-character hex string.
  ///
  /// Throws [ProtocolException] on invalid response.
  /// Throws [NetworkException] on communication error.
  Future<String> getFocusPosition() async {
    final response = await _sendCommand(ptzEndpoint, getFocusCmd, isPtz: true);
    final focusRegex = RegExp(r'^gf([0-9A-Fa-f]{3})$');
    final match = focusRegex.firstMatch(response);
    if (match == null) {
      throw ProtocolException('Invalid focus response: $response');
    }
    return match.group(1)!;
  }

  /// Gets iris position and mode.
  ///
  /// Returns a string in the format "position:mode" where position is 3-char hex and mode is 1-char.
  ///
  /// Throws [ProtocolException] on invalid response.
  /// Throws [NetworkException] on communication error.
  Future<String> getIrisPosition() async {
    final response = await _sendCommand(ptzEndpoint, getIrisCmd, isPtz: true);
    final irisRegex = RegExp(r'^gi([0-9A-Fa-f]{3})(\d)$');
    final match = irisRegex.firstMatch(response);
    if (match == null) {
      throw ProtocolException('Invalid iris response: $response');
    }
    return '${match.group(1)!}:${match.group(2)!}';
  }

  /// Enables or disables continuous lens position updates.
  ///
  /// [enabled] True to enable.
  ///
  /// Returns the response from the camera.
  ///
  /// Throws [CameraException] on communication error.
  Future<String> setLensPositionContinuous(bool enabled) async {
    final data = enabled ? '1' : '0';
    return await _sendCommand(ptzEndpoint, '#LPC$data', isPtz: true);
  }

  /// Gets error status.
  ///
  /// Returns the error code as a string.
  ///
  /// Throws [CameraException] on error or invalid response.
  Future<String> getErrorStatus() async {
    final response = await _sendCommand(ptzEndpoint, getErrorCmd, isPtz: true);
    if (!response.startsWith(errorResponsePrefix)) {
      throw CameraException('Invalid response: $response');
    }
    return response.substring(3);
  }

  /// Gets the current gain setting from camera data.
  ///
  /// Parses the response from getAllCameraData for gain value.
  ///
  /// Returns the gain value as an integer.
  ///
  /// Throws [CameraException] if unable to retrieve or parse data.
  Future<int> getCurrentGain() async {
    final data = await getAllCameraData();
    final gainStr = data['gain'];
    if (gainStr == null) {
      throw CameraException('Gain data not available');
    }
    return int.parse(gainStr);
  }

  /// Gets the current shutter mode from camera data.
  ///
  /// Parses the response from getAllCameraData for shutter mode.
  ///
  /// Returns the shutter mode as an integer.
  ///
  /// Throws [CameraException] if unable to retrieve or parse data.
  Future<int> getCurrentShutterMode() async {
    final data = await getAllCameraData();
    final modeStr = data['shutter_mode'];
    if (modeStr == null) {
      throw CameraException('Shutter mode data not available');
    }
    return int.parse(modeStr);
  }

  // Batch Information Retrieval
  /// Retrieves all camera data.
  ///
  /// Parses the response as key=value pairs and returns a map.
  ///
  /// Assumes responses are quoted as per documentation examples, but handles unquoted as fallback.
  ///
  /// Throws [CameraException] on HTTP error.
  Future<Map<String, String>> getAllCameraData() async {
    final protocol = useHttps ? 'https' : 'http';
    final url = '$protocol://$ipAddress/live/camdata.html';
    final response = await _client.get(Uri.parse(url)).timeout(requestTimeout);

    if (response.statusCode == 200) {
      final body = response.body.trim();
      final cleanedBody = body.startsWith('"') && body.endsWith('"')
          ? body.substring(1, body.length - 1)
          : body;
      final lines = cleanedBody.split('\n');
      final map = <String, String>{};
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && trimmed.contains('=')) {
          final parts = trimmed.split('=');
          if (parts.length == 2) {
            map[parts[0]] = parts[1];
          }
        }
      }
      return map;
    } else {
      throw CameraException('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  /// Starts receiving event notifications via TCP.
  ///
  /// Initiates HTTP request to start notifications, then listens on the specified TCP port.
  ///
  /// Returns a Stream of notification objects (String for regular, Map for lens positions or position changes).
  ///
  /// Call stopEventNotifications to stop.
  ///
  /// Throws [CameraException] on error.
  Future<Stream<Object>> startEventNotifications(int port, {InternetAddress? bindAddress}) async {
    return await _notificationManager.startNotifications(port, bindAddress: bindAddress);
  }

  /// Stops receiving event notifications.
  ///
  /// Closes the TCP server and stream.
  ///
  /// Throws [CameraException] on error.
  Future<String> stopEventNotifications(int port) async {
    return await _notificationManager.stopNotifications(port);
  }

  /// Disposes the HTTP client and closes any open TCP connections.
  Future<void> dispose() async {
    _client.close();
    await _notificationManager.dispose();
  }
}