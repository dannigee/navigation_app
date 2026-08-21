// Demonstrates, against the app's real service classes, the three failure modes
// the mock rig exists to expose. Nothing here is simulated at the Dart level --
// every fault is injected into the rig over HTTP and the client is left to cope.
//
//   1. sudo python3 tools/mock_server/run.py
//   2. dart run tools/mock_server/chaos_demo.dart
//
// Takes roughly a minute; the ACK timeouts are deliberately slow.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:navigation_app/services/panasonic_service.dart';
import 'package:navigation_app/services/roland_service.dart';

const rolandHost = '127.0.0.1';
const cameraIp = '127.0.0.2';
const inspector = '127.0.0.1:8080';

Future<void> control(Map<String, Object?> body) async {
  final client = HttpClient();
  try {
    final req = await client.post(inspector.split(':')[0],
        int.parse(inspector.split(':')[1]), '/control');
    req.headers.contentType = ContentType.json;
    // Set the length explicitly: without it HttpClient falls back to chunked
    // transfer encoding.
    final payload = utf8.encode(jsonEncode(body));
    req.contentLength = payload.length;
    req.add(payload);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('control ${res.statusCode} for $body');
    }
    await res.drain<void>();
  } finally {
    client.close();
  }
}

void heading(String text) {
  stdout.writeln('\n${'=' * 68}\n$text\n${'=' * 68}');
}

Future<String> attempt(String label, Future<void> Function() action) async {
  final started = DateTime.now();
  try {
    await action();
    final ms = DateTime.now().difference(started).inMilliseconds;
    stdout.writeln('  $label -> OK (${ms}ms)');
    return 'ok';
  } catch (e) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    final kind = e.runtimeType.toString();
    stdout.writeln('  $label -> $kind after ${ms}ms');
    stdout.writeln('      ${e.toString().split('\n').first}');
    return kind;
  }
}

Future<void> main() async {
  await control({'action': 'fault', 'nackEverything': false,
                 'swallowAcks': false, 'latencyMs': 0});

  await _ackDesync();
  await _silentDrop();

  // The camera queue rethrows into a fire-and-forget _processQueue()
  // (panasonic_service.dart:91), so the error arrives as an unhandled async
  // error that no caller can catch. Without a guarded zone it terminates the
  // process outright -- which is itself the finding.
  final strays = <Object>[];
  await runZonedGuarded(_cameraDeadlock, (error, stack) {
    strays.add(error);
    stdout.writeln('  [uncatchable async error] ${error.runtimeType}: '
        '${error.toString().split('\n').first}');
  });
  if (strays.isNotEmpty) {
    stdout.writeln(
        '\n  ${strays.length} error(s) surfaced with no caller able to catch\n'
        '  them. In the app these reach the Flutter zone handler and are\n'
        '  logged, never shown -- the operator sees nothing at all.');
  }

  stdout.writeln('\nResetting rig faults.');
  await control({'action': 'fault', 'nackEverything': false,
                 'swallowAcks': false, 'latencyMs': 0});
  await control({'action': 'camera', 'ip': cameraIp, 'fault': 'offline',
                 'value': false});
  await control({'action': 'camera', 'ip': cameraIp, 'fault': 'busy',
                 'value': false});
  exit(0);
}

// ---------------------------------------------------------------------------

Future<void> _ackDesync() async {
  heading('1. ACK queue desync  (roland_service.dart:1839)');
  stdout.writeln(
      'A timed-out command leaves its Completer at the head of _ackCompleters.\n'
      'ACKs are matched by queue position with no command correlation, so once\n'
      'one is orphaned every later ACK completes the wrong caller.\n');

  final service = RolandService(host: rolandHost);
  await service.connect();

  await attempt('baseline CUT (rig healthy)', () => service.cut());

  stdout.writeln('\n  -- enabling "swallow all responses" --');
  await control({'action': 'fault', 'swallowAcks': true});
  await attempt('CUT with responses swallowed', () => service.cut());

  stdout.writeln('\n  -- rig healthy again --');
  await control({'action': 'fault', 'swallowAcks': false});
  final after = await attempt('CUT after recovery', () => service.cut());

  stdout.writeln(after == 'ok'
      ? '\n  Recovered. The orphaned completers are still queued, so the desync\n'
        '  may only surface once enough have accumulated.'
      : '\n  Still broken with a healthy rig. The queue did not recover on its\n'
        '  own -- this is the permanent desync.');

  await service.disconnect();
}

// ---------------------------------------------------------------------------

Future<void> _silentDrop() async {
  heading('2. Dropped connection is invisible  (roland_service.dart:1707)');
  stdout.writeln(
      'The service clears its private _isConnected on socket error but never\n'
      'notifies the UI, exposes no getter and emits no connection-state stream.\n'
      'Auto-reconnect is off by default (:1606) and nothing enables it.\n');

  final service = RolandService(host: rolandHost);
  await service.connect();
  await attempt('CUT before the drop', () => service.cut());

  stdout.writeln('\n  -- dropping the socket from the rig --');
  await control({'action': 'drop'});
  await Future<void>.delayed(const Duration(seconds: 1));

  await attempt('CUT after the drop', () => service.cut());
  await attempt('CUT again (any self-healing?)', () => service.cut());

  stdout.writeln(
      '\n  Note what the app can observe here: nothing. There is no public\n'
      '  connection state on RolandService, so multi_device_control_page keeps\n'
      '  its _rolandConnected notifier true and the UI still reads "Live".');

  await service.disconnect();
}

// ---------------------------------------------------------------------------

Future<void> _cameraDeadlock() async {
  heading('3. Camera command queue deadlock  (panasonic_service.dart:111)');
  stdout.writeln(
      'CommandQueue._processQueue sets _isProcessing = true, and the queued\n'
      'wrapper rethrows on failure (:88), so the flag is never cleared (:113).\n'
      'Every later command enqueues a Completer that is never completed.\n');

  final cam = PanasonicService(ipAddress: cameraIp);
  await attempt('recallPreset(1) with camera healthy', () => cam.recallPreset(1));

  stdout.writeln('\n  -- making the camera unreachable --');
  await control({'action': 'camera', 'ip': cameraIp, 'fault': 'offline',
                 'value': true});
  await attempt('recallPreset(2) while unreachable', () => cam.recallPreset(2));

  stdout.writeln('\n  -- camera reachable again --');
  await control({'action': 'camera', 'ip': cameraIp, 'fault': 'offline',
                 'value': false});
  await Future<void>.delayed(const Duration(milliseconds: 500));

  stdout.writeln('  recallPreset(3) with a healthy camera, 20s ceiling...');
  var hung = false;
  try {
    await cam.recallPreset(3).timeout(const Duration(seconds: 20));
    stdout.writeln('  recallPreset(3) -> OK (queue recovered)');
  } on Object catch (e) {
    hung = e is Exception && e.toString().contains('TimeoutException');
    stdout.writeln('  recallPreset(3) -> ${e.runtimeType}');
  }

  stdout.writeln(hung
      ? '\n  CONFIRMED: the camera is reachable and answering, but the queue is\n'
        '  wedged. No timeout, no error -- the app would simply hang forever on\n'
        '  every preset for this camera until it is restarted.'
      : '\n  The queue recovered; re-check the rethrow path before relying on this.');

  cam.dispose();
}
