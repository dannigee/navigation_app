import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:developer' as dev;

/// Custom exception for Roland service errors.
class RolandException implements Exception {
  final String message;
  RolandException(this.message);

  @override
  String toString() => 'RolandException: $message';
}

/// Custom exceptions for specific errors.
class ConnectionException extends RolandException {
  ConnectionException(String message) : super(message);
}

class CommandException extends RolandException {
  CommandException(String message) : super(message);
}

class ValidationException extends RolandException {
  ValidationException(String message) : super(message);
}

class InvalidParameterException extends RolandException {
  InvalidParameterException(String message) : super(message);
}

class ParsingException extends RolandException {
  ParsingException(String message) : super(message);
}

/// Enums for camera directions.
enum PanDirection { left, stop, right }
enum TiltDirection { down, stop, up }
enum ZoomDirection { wideFast, wideSlow, stop, teleSlow, teleFast }
enum FocusDirection { near, stop, far }

/// Constants for command strings.
const String onString = 'ON';
const String offString = 'OFF';
const String ackString = 'ACK';
const String nackString = 'NACK';

/// Response models for parsed responses.
class FaderLevelResponse {
  const FaderLevelResponse(this.level);
  final int level;
}

class ProgramResponse {
  final String source;
  final String? input;
  ProgramResponse(this.source, this.input);
}

class PinPPositionResponse {
  final int h;
  final int v;
  PinPPositionResponse(this.h, this.v);
}

class VersionResponse {
  final String model;
  final String version;
  VersionResponse(this.model, this.version);
}

/// Response for CAMPTS command.
class PanTiltSpeedResponse {
  final String identifier;
  final int speed;
  PanTiltSpeedResponse(this.identifier, this.speed);
}

/// Response for CAMPR command.
class PresetResponse {
  final String identifier;
  final String preset;
  PresetResponse(this.identifier, this.preset);
}

class AudioLevelResponse {
  final String input;
  final String level; // Can be int or 'INF'
  AudioLevelResponse(this.input, this.level);
}

class MeterResponse {
  final List<String> levels;
  MeterResponse(this.levels);
}

class TallyResponse {
  final List<int> statuses;
  TallyResponse(this.statuses);
}

class MemoryResponse {
  final String memory;
  MemoryResponse(this.memory);
}

class DskSourceResponse {
  final String dsk;
  final String source;
  final String? input;
  DskSourceResponse(this.dsk, this.source, this.input);
}

class DskLevelResponse {
  final int level;
  DskLevelResponse(this.level);
}

/// Response for AUX command.
class AuxResponse {
  final String identifier;
  final String source;
  final String? input;
  AuxResponse(this.identifier, this.source, this.input);
}

class TransitionStatusResponse {
  final String status;
  TransitionStatusResponse(this.status);
}

class FreezeResponse {
  final String status;
  FreezeResponse(this.status);
}

class FadeResponse {
  final String status;
  FadeResponse(this.status);
}

class StillResponse {
  final String status;
  StillResponse(this.status);
}

class HdcpResponse {
  final String status;
  HdcpResponse(this.status);
}

class TestPatternResponse {
  final String pattern;
  TestPatternResponse(this.pattern);
}

class TestToneResponse {
  final String level;
  final String? freqL;
  final String? freqR;
  TestToneResponse(this.level, [this.freqL, this.freqR]);
}

class BusyResponse {
  final String status;
  BusyResponse(this.status);
}

/// Response for MCRST and QMCRST commands.
class MacroStatusResponse {
  final String identifier;
  final String status;
  MacroStatusResponse(this.identifier, this.status);
}

class SequencerStatusResponse {
  final String status;
  SequencerStatusResponse(this.status);
}

class AutoSequenceResponse {
  final String status;
  AutoSequenceResponse(this.status);
}

class VideoInputSourceResponse {
  final int index;
  final String source;
  VideoInputSourceResponse(this.index, this.source);
}

class VideoInputStatusResponse {
  final String input;
  final String status;
  VideoInputStatusResponse(this.input, this.status);
}

class PreviewResponse {
  final String source;
  final String? input;
  PreviewResponse(this.source, this.input);
}

class TransitionTypeResponse {
  final String type;
  TransitionTypeResponse(this.type);
}

class TransitionTimeResponse {
  final String type;
  final int time;
  TransitionTimeResponse(this.type, this.time);
}

class PinPSourceResponse {
  final String pinp;
  final String source;
  PinPSourceResponse(this.pinp, this.source);
}

class PinPProgramResponse {
  final String pinp;
  final String status;
  PinPProgramResponse(this.pinp, this.status);
}

class PinPPreviewResponse {
  final String pinp;
  final String status;
  PinPPreviewResponse(this.pinp, this.status);
}

class DskProgramResponse {
  final String dsk;
  final String status;
  DskProgramResponse(this.dsk, this.status);
}

class DskPreviewResponse {
  final String dsk;
  final String status;
  DskPreviewResponse(this.dsk, this.status);
}

class SplitStatusResponse {
  final String split;
  final String status;
  SplitStatusResponse(this.split, this.status);
}

class SplitPositionsResponse {
  final String split;
  final int pgmCenter;
  final int pvwCenter;
  final int? center;
  SplitPositionsResponse(this.split, this.pgmCenter, this.pvwCenter, this.center);
}

class VideoInputAssignResponse {
  final String input;
  final String source;
  VideoInputAssignResponse(this.input, this.source);
}

class VideoOutputAssignResponse {
  final String output;
  final String source;
  VideoOutputAssignResponse(this.output, this.source);
}

class AudioOutputAssignResponse {
  final String output;
  final String assign;
  AudioOutputAssignResponse(this.output, this.assign);
}

class AudioMuteResponse {
  final String input;
  final String status;
  AudioMuteResponse(this.input, this.status);
}

class AudioSoloResponse {
  final String input;
  final String status;
  AudioSoloResponse(this.input, this.status);
}

class AudioDelayResponse {
  final String input;
  final int delay;
  AudioDelayResponse(this.input, this.delay);
}

class AudioFilterResponse {
  final String input;
  final String status;
  AudioFilterResponse(this.input, this.status);
}

class AudioGateResponse {
  final String input;
  final String status;
  AudioGateResponse(this.input, this.status);
}

class AudioLinkResponse {
  final String input;
  final String status;
  AudioLinkResponse(this.input, this.status);
}

class AudioChangerResponse {
  final String input;
  final String status;
  AudioChangerResponse(this.input, this.status);
}

class AudioOutputMuteResponse {
  final String output;
  final String status;
  AudioOutputMuteResponse(this.output, this.status);
}

class ReverbResponse {
  final String status;
  ReverbResponse(this.status);
}

class AutoMixingResponse {
  final String status;
  AutoMixingResponse(this.status);
}

class MeterAutoTransmitResponse {
  final String status;
  MeterAutoTransmitResponse(this.status);
}

class MeterChannelResponse {
  final int channel;
  final String name;
  MeterChannelResponse(this.channel, this.name);
}

class CompGrAutoTransmitResponse {
  final String status;
  CompGrAutoTransmitResponse(this.status);
}

class AutoMixingAutoTransmitResponse {
  final String status;
  AutoMixingAutoTransmitResponse(this.status);
}

class SigPeakAutoTransmitResponse {
  final String status;
  SigPeakAutoTransmitResponse(this.status);
}

class AuxAutoTransmitResponse {
  final String status;
  AuxAutoTransmitResponse(this.status);
}

class GpoResponse {
  final String gpo;
  final String status;
  GpoResponse(this.gpo, this.status);
}

class AutoFocusResponse {
  final String camera;
  final String status;
  AutoFocusResponse(this.camera, this.status);
}

class AutoExposureResponse {
  final String camera;
  final String status;
  AutoExposureResponse(this.camera, this.status);
}

class AutoSwitchingResponse {
  final String status;
  AutoSwitchingResponse(this.status);
}

/// Mixins for command groups.
mixin VideoCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Performs a cut transition.
  /// @example
  /// await service.cut(); // Immediately switches to preview
  Future<void> cut() => _sendCommand(_buildCommand('CUT'));

  /// Performs an auto transition.
  /// Variant 1: ATO;
  /// Variant 2: ATO:input;
  /// Variant 3: ATO:input,time;
  /// @example
  /// await service.auto(); // Auto transition with current settings
  /// await service.auto(input: 'HDMI2'); // Auto to HDMI2
  /// await service.auto(input: 'HDMI2', time: 20); // Auto to HDMI2 in 2.0 seconds
  Future<void> auto({String? input, int? time}) {
    List<String> params = [];
    if (input != null) params.add(input);
    if (time != null) {
      if (time == -1 || (time >= 0 && time <= 40)) {
        params.add(time.toString());
      } else {
        throw ArgumentError('time must be -1 or 0-40');
      }
    }
    return _sendCommand(_buildCommand('ATO', params));
  }

  /// Performs a cut transition with optional input.
  Future<void> cutWithInput(String input) => _sendCommand(_buildCommand('CUT', [input]));

  /// Sets the program input.
  /// @example
  /// await service.setProgram('HDMI1'); // Sets program to HDMI1
  Future<void> setProgram(String input) {
    if (!RolandService.validVideoSources.contains(input)) throw ArgumentError('Invalid input: $input');
    return _sendCommand(_buildCommand('PGM', [input]));
  }

  /// Gets the program input.
  Future<void> getProgram() => _sendCommand(_buildCommand('QPGM'));

  /// Sets the preview input.
  Future<void> setPreview(String input) {
    if (!RolandService.validVideoSources.contains(input)) throw ArgumentError('Invalid input: $input');
    return _sendCommand(_buildCommand('PST', [input]));
  }

  /// Gets the preview input.
  Future<void> getPreview() => _sendCommand(_buildCommand('QPST'));

  /// Sets the AUX bus video channel.
  Future<void> setAux(String aux, String input) {
    if (!RegExp(r'^AUX[1-3]$').hasMatch(aux)) throw ArgumentError('Invalid aux: $aux');
    if (input != 'PGMLINK' && !RolandService.validVideoSources.contains(input)) throw ArgumentError('Invalid input: $input');
    return _sendCommand(_buildCommand('AUX', [aux, input]));
  }

  /// Gets the AUX bus video channel.
  Future<void> getAux(String aux) => _sendCommand(_buildCommand('QAUX', [aux]));

  /// Sets the video fader level (0-2047).
  /// @example
  /// await service.setFaderLevel(1024); // Sets fader to mid-level
  Future<void> setFaderLevel(int level) {
    if (level < 0 || level > 2047) throw ArgumentError('level must be 0-2047');
    return _sendCommand(_buildCommand('VFL', [level.toString()]));
  }

  /// Gets the video fader level.
  Future<void> getFaderLevel() => _sendCommand(_buildCommand('QVFL'));

  /// Gets video input source.
  Future<void> getVideoInputSource(int index) {
    if (index < 0 || index > 51) throw ArgumentError('index must be 0-51');
    return _sendCommand(_buildCommand('QVISRC', [index.toString()]));
  }

  /// Gets video input status.
  Future<void> getVideoInputStatus(String input) {
    const validInputs = {'HDMI1', 'HDMI2', 'HDMI3', 'HDMI4', 'HDMI5', 'HDMI6', 'HDMI7', 'HDMI8',
      'SDI1', 'SDI2', 'SDI3', 'SDI4', 'SDI5', 'SDI6', 'SDI7', 'SDI8'};
    if (!validInputs.contains(input)) throw ArgumentError('Invalid input: $input. Must be HDMI1-8 or SDI1-8');
    return _sendCommand(_buildCommand('QVIST', [input]));
  }

  /// Sets the transition type.
  Future<void> setTransitionType(String type) {
    if (!['MIX', 'WIPE'].contains(type.toUpperCase())) throw ArgumentError('Invalid type: $type');
    return _sendCommand(_buildCommand('TRS', [type]));
  }

  /// Gets the transition type.
  Future<void> getTransitionType() => _sendCommand(_buildCommand('QTRS'));

  /// Sets the transition time.
  Future<void> setTransitionTime(String type, int time) {
    if (!RolandService.validTransitionTypes.contains(type)) throw ArgumentError('Invalid type: $type');
    if (time < 0 || time > 40) throw ArgumentError('time must be 0-40');
    return _sendCommand(_buildCommand('TIM', [type, time.toString()]));
  }

  /// Gets the transition time.
  Future<void> getTransitionTime(String type) => _sendCommand(_buildCommand('QTIM', [type]));

  /// Gets the auto transition status.
  Future<void> getAutoTransitionStatus() => _sendCommand(_buildCommand('QATG'));

  /// Sets freeze.
  Future<void> setFreeze(bool on) => _sendCommand(_buildCommand('FRZ', [on ? onString : offString]));

  /// Toggles freeze.
  Future<void> toggleFreeze() => _sendCommand(_buildCommand('FRZ'));

  /// Gets freeze status.
  Future<void> getFreeze() => _sendCommand(_buildCommand('QFRZ'));

  /// Sets output fade.
  Future<void> setFade(bool on) => _sendCommand(_buildCommand('FTB', [on ? 'ON' : 'OFF']));

  /// Toggles output fade.
  Future<void> toggleFade() => _sendCommand(_buildCommand('FTB'));

  /// Gets output fade status.
  Future<void> getFade() => _sendCommand(_buildCommand('QFTB'));

  /// Sets video input assign.
  Future<void> setVideoInputAssign(String input, String source) {
    if (!RolandService.validVideoSources.where((s) => s.startsWith('INPUT')).contains(input)) throw ArgumentError('Invalid input: $input');
    if (source != 'N/A' && !RolandService.validVideoSources.contains(source)) throw ArgumentError('Invalid source: $source');
    return _sendCommand(_buildCommand('VIS', [input, source]));
  }

  /// Gets video input assign.
  Future<void> getVideoInputAssign(String input) => _sendCommand(_buildCommand('QVIS', [input]));

  /// Sets video output assign.
  Future<void> setVideoOutputAssign(String output, String source) {
    if (!RolandService.validVideoOutputs.contains(output)) throw ArgumentError('Invalid output: $output');
    if (!RolandService.validVideoOutputSources.contains(source)) throw ArgumentError('Invalid source: $source');
    return _sendCommand(_buildCommand('VOS', [output, source]));
  }

  /// Gets video output assign.
  Future<void> getVideoOutputAssign(String output) => _sendCommand(_buildCommand('QVOS', [output]));

  /// Sets still image output.
  Future<void> setStillOutput(String still) => _sendCommand(_buildCommand('STO', [still]));

  /// Gets still image output.
  Future<void> getStillOutput() => _sendCommand(_buildCommand('QSTO'));
}

mixin PinPCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets the PinP source.
  Future<void> setPinPSource(String pinp, String source) {
    if (!RegExp(r'^PinP[1-4]$').hasMatch(pinp)) throw ArgumentError('Invalid pinp: $pinp');
    if (!RolandService.validVideoSources.contains(source)) throw ArgumentError('Invalid source: $source');
    return _sendCommand(_buildCommand('PIS', [pinp, source]));
  }

  /// Gets the PinP source.
  Future<void> getPinPSource(String pinp) => _sendCommand(_buildCommand('QPIS', [pinp]));

  /// Sets the PinP position.
  Future<void> setPinPPosition(String pinp, int h, int v) {
    if (h < -1000 || h > 1000 || v < -1000 || v > 1000) throw ArgumentError('h,v must be -1000 to 1000');
    return _sendCommand(_buildCommand('PIP', [pinp, h.toString(), v.toString()]));
  }

  /// Gets the PinP position.
  Future<void> getPinPPosition(String pinp) => _sendCommand(_buildCommand('QPIP', [pinp]));

  /// Sets PinP on program.
  Future<void> setPinPPgm(String pinp, bool on) => _sendCommand(_buildCommand('PPS', [pinp, on ? 'ON' : 'OFF']));

  /// Toggles PinP on program.
  Future<void> togglePinPPgm(String pinp) => _sendCommand(_buildCommand('PPS', [pinp]));

  /// Gets PinP on program status.
  Future<void> getPinPPgm(String pinp) => _sendCommand(_buildCommand('QPPS', [pinp]));

  /// Sets PinP on preview.
  Future<void> setPinPPvw(String pinp, bool on) => _sendCommand(_buildCommand('PPW', [pinp, on ? 'ON' : 'OFF']));

  /// Toggles PinP on preview.
  Future<void> togglePinPPvw(String pinp) => _sendCommand(_buildCommand('PPW', [pinp]));

  /// Gets PinP on preview status.
  Future<void> getPinPPvw(String pinp) => _sendCommand(_buildCommand('QPPW', [pinp]));
}

mixin DskCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets DSK on program.
  Future<void> setDskPgm(String dsk, bool on) => _sendCommand(_buildCommand('DSK', [dsk, on ? 'ON' : 'OFF']));

  /// Toggles DSK on program.
  Future<void> toggleDskPgm(String dsk) => _sendCommand(_buildCommand('DSK', [dsk]));

  /// Gets DSK on program status.
  Future<void> getDskPgm(String dsk) => _sendCommand(_buildCommand('QDSK', [dsk]));

  /// Sets DSK on preview.
  Future<void> setDskPvw(String dsk, bool on) => _sendCommand(_buildCommand('DVW', [dsk, on ? 'ON' : 'OFF']));

  /// Toggles DSK on preview.
  Future<void> toggleDskPvw(String dsk) => _sendCommand(_buildCommand('DVW', [dsk]));

  /// Gets DSK on preview status.
  Future<void> getDskPvw(String dsk) => _sendCommand(_buildCommand('QDVW', [dsk]));

  /// Sets DSK fill source.
  Future<void> setDskSource(String dsk, String source) {
    if (!RegExp(r'^DSK[1-2]$').hasMatch(dsk)) throw ArgumentError('Invalid dsk: $dsk');
    if (!RolandService.validVideoSources.contains(source)) throw ArgumentError('Invalid source: $source');
    return _sendCommand(_buildCommand('DSS', [dsk, source]));
  }

  /// Gets DSK fill source.
  Future<void> getDskSource(String dsk) => _sendCommand(_buildCommand('QDSS', [dsk]));

  /// Sets DSK level.
  Future<void> setDskLevel(String dsk, int level) {
    if (level < 0 || level > 255) throw ArgumentError('level must be 0-255');
    return _sendCommand(_buildCommand('KYL', [dsk, level.toString()]));
  }

  /// Gets DSK level.
  Future<void> getDskLevel(String dsk) => _sendCommand(_buildCommand('QKYL', [dsk]));

  /// Sets DSK gain.
  Future<void> setDskGain(String dsk, int gain) {
    if (gain < 0 || gain > 255) throw ArgumentError('gain must be 0-255');
    return _sendCommand(_buildCommand('KYG', [dsk, gain.toString()]));
  }

  /// Gets DSK gain.
  Future<void> getDskGain(String dsk) => _sendCommand(_buildCommand('QKYG', [dsk]));
}

mixin AudioCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets audio output assign.
  Future<void> setAudioOutputAssign(String output, String assign) {
    if (!RolandService.validAudioOutputs.contains(output)) throw ArgumentError('Invalid output: $output');
    if (!RolandService.validAudioOutputAssigns[output]!.contains(assign)) throw ArgumentError('Invalid assign for $output: $assign');
    return _sendCommand(_buildCommand('AOS', [output, assign]));
  }

  /// Gets audio output assign.
  Future<void> getAudioOutputAssign(String output) => _sendCommand(_buildCommand('QAOS', [output]));

  /// Sets audio input level (in tenths of dB, e.g., -60 for -6.0 dB).
  Future<void> setAudioInputLevel(String input, int level) {
    if (level < -800 || level > 100) throw ArgumentError('level must be -800 to 100 (tenths of dB)');
    return _sendCommand(_buildCommand('IAL', [input, level.toString()]));
  }

  /// Gets audio input level.
  Future<void> getAudioInputLevel(String input) => _sendCommand(_buildCommand('QIAL', [input]));

  /// Sets audio input mute.
  Future<void> setAudioInputMute(String input, bool mute) => _sendCommand(_buildCommand('IAM', [input, mute ? 'ON' : 'OFF']));

  /// Toggles audio input mute.
  Future<void> toggleAudioInputMute(String input) => _sendCommand(_buildCommand('IAM', [input]));

  /// Gets audio input mute status.
  Future<void> getAudioInputMute(String input) => _sendCommand(_buildCommand('QIAM', [input]));

  /// Sets audio input solo.
  Future<void> setAudioInputSolo(String input, bool solo) => _sendCommand(_buildCommand('IAS', [input, solo ? 'ON' : 'OFF']));

  /// Toggles audio input solo.
  Future<void> toggleAudioInputSolo(String input) => _sendCommand(_buildCommand('IAS', [input]));

  /// Gets audio input solo status.
  Future<void> getAudioInputSolo(String input) => _sendCommand(_buildCommand('QIAS', [input]));

  /// Sets audio input delay time.
  Future<void> setAudioInputDelay(String input, int delay) {
    if (delay < 0 || delay > 5000) throw ArgumentError('delay must be 0-5000');
    return _sendCommand(_buildCommand('ADT', [input, delay.toString()]));
  }

  /// Gets audio input delay time.
  Future<void> getAudioInputDelay(String input) => _sendCommand(_buildCommand('QADT', [input]));

  /// Sets high pass filter.
  Future<void> setHighPassFilter(String input, bool on) => _sendCommand(_buildCommand('HPF', [input, on ? 'ON' : 'OFF']));

  /// Gets high pass filter status.
  Future<void> getHighPassFilter(String input) => _sendCommand(_buildCommand('QHPF', [input]));

  /// Sets gate.
  Future<void> setGate(String input, bool on) => _sendCommand(_buildCommand('GATE', [input, on ? 'ON' : 'OFF']));

  /// Gets gate status.
  Future<void> getGate(String input) => _sendCommand(_buildCommand('QGATE', [input]));

  /// Sets stereo link.
  Future<void> setStereoLink(String input, bool on) => _sendCommand(_buildCommand('STLK', [input, on ? 'ON' : 'OFF']));

  /// Toggles stereo link.
  Future<void> toggleStereoLink(String input) => _sendCommand(_buildCommand('STLK', [input]));

  /// Gets stereo link status.
  Future<void> getStereoLink(String input) => _sendCommand(_buildCommand('QSTLK', [input]));

  /// Sets voice changer.
  Future<void> setVoiceChanger(String input, bool on) => _sendCommand(_buildCommand('VOCH', [input, on ? 'ON' : 'OFF']));

  /// Toggles voice changer.
  Future<void> toggleVoiceChanger(String input) => _sendCommand(_buildCommand('VOCH', [input]));

  /// Gets voice changer status.
  Future<void> getVoiceChanger(String input) => _sendCommand(_buildCommand('QVOCH', [input]));

  /// Sets audio output level (in tenths of dB, e.g., -60 for -6.0 dB).
  Future<void> setAudioOutputLevel(String output, int level) {
    if (level < -800 || level > 100) throw ArgumentError('level must be -800 to 100 (tenths of dB)');
    return _sendCommand(_buildCommand('OAL', [output, level.toString()]));
  }

  /// Gets audio output level.
  Future<void> getAudioOutputLevel(String output) => _sendCommand(_buildCommand('QOAL', [output]));

  /// Sets audio output mute.
  Future<void> setAudioOutputMute(String output, bool mute) => _sendCommand(_buildCommand('OAM', [output, mute ? 'ON' : 'OFF']));

  /// Gets audio output mute status.
  Future<void> getAudioOutputMute(String output) => _sendCommand(_buildCommand('QOAM', [output]));

  /// Sets reverb.
  Future<void> setReverb(bool on) => _sendCommand(_buildCommand('RVB', [on ? 'ON' : 'OFF']));

  /// Toggles reverb.
  Future<void> toggleReverb() => _sendCommand(_buildCommand('RVB'));

  /// Gets reverb status.
  Future<void> getReverb() => _sendCommand(_buildCommand('QRVB'));

  /// Sets audio auto mixing.
  Future<void> setAutoMixing(bool on) => _sendCommand(_buildCommand('ATM', [on ? 'ON' : 'OFF']));

  /// Toggles audio auto mixing.
  Future<void> toggleAutoMixing() => _sendCommand(_buildCommand('ATM'));

  /// Gets audio auto mixing status.
  Future<void> getAutoMixing() => _sendCommand(_buildCommand('QATM'));
}

mixin MeterCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets auto-transmit for audio level meter.
  Future<void> setMeterAutoTransmit(bool on) => _sendCommand(_buildCommand('MTRSW', [on ? 'ON' : 'OFF']));

  /// Gets auto-transmit status for audio level meter.
  Future<void> getMeterAutoTransmit() => _sendCommand(_buildCommand('QMTRSW'));

  /// Gets audio level meter.
  Future<void> getAudioLevelMeter(String mode) => _sendCommand(_buildCommand('MTRLV', [mode]));

  /// Gets audio level meter channel info.
  Future<void> getAudioLevelMeterChannel(int channel) => _sendCommand(_buildCommand('MTRCH', [channel.toString()]));

  /// Sets auto-transmit for comp GR level.
  Future<void> setCompGrAutoTransmit(bool on) => _sendCommand(_buildCommand('GRSW', [on ? 'ON' : 'OFF']));

  /// Gets auto-transmit status for comp GR level.
  Future<void> getCompGrAutoTransmit() => _sendCommand(_buildCommand('QGRSW'));

  /// Gets comp GR level.
  Future<void> getCompGrLevel() => _sendCommand(_buildCommand('GRLV'));

  /// Gets comp GR channel info.
  Future<void> getCompGrChannel(int channel) => _sendCommand(_buildCommand('GRCH', [channel.toString()]));

  /// Sets auto-transmit for auto mixing level.
  Future<void> setAutoMixingAutoTransmit(bool on) => _sendCommand(_buildCommand('AMSW', [on ? 'ON' : 'OFF']));

  /// Gets auto-transmit status for auto mixing level.
  Future<void> getAutoMixingAutoTransmit() => _sendCommand(_buildCommand('QAMSW'));

  /// Gets auto mixing level.
  Future<void> getAutoMixingLevel() => _sendCommand(_buildCommand('AMLV'));

  /// Gets auto mixing channel info.
  Future<void> getAutoMixingChannel(int channel) => _sendCommand(_buildCommand('AMCH', [channel.toString()]));

  /// Sets auto-transmit for sig/peak level.
  Future<void> setSigPeakAutoTransmit(bool on) => _sendCommand(_buildCommand('SPSW', [on ? 'ON' : 'OFF']));

  /// Gets auto-transmit status for sig/peak level.
  Future<void> getSigPeakAutoTransmit() => _sendCommand(_buildCommand('QSPSW'));

  /// Gets sig/peak level.
  Future<void> getSigPeakLevel() => _sendCommand(_buildCommand('SPLV'));

  /// Gets sig/peak channel info.
  Future<void> getSigPeakChannel(int channel) => _sendCommand(_buildCommand('SPCH', [channel.toString()]));

  /// Sets auto-transmit for AUX level.
  Future<void> setAuxAutoTransmit(bool on) => _sendCommand(_buildCommand('AUXSW', [on ? 'ON' : 'OFF']));

  /// Gets auto-transmit status for AUX level.
  Future<void> getAuxAutoTransmit() => _sendCommand(_buildCommand('QAUXSW'));

  /// Gets AUX meter level.
  Future<void> getAuxLevel(String aux) => _sendCommand(_buildCommand('AUXLV', [aux]));

  /// Gets AUX meter channel info.
  Future<void> getAuxChannel(int channel) => _sendCommand(_buildCommand('AUXCH', [channel.toString()]));
}

mixin ControlCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Executes a macro.
  Future<void> executeMacro(int macro) {
    if (macro < 1 || macro > 100) throw ArgumentError('macro must be 1-100');
    return _sendCommand(_buildCommand('MCREX', [macro.toString()]));
  }

  /// Checks if macro is executing.
  Future<void> getMacroStatus(int macro) {
    if (macro < 1 || macro > 100) throw ArgumentError('macro must be 1-100');
    return _sendCommand(_buildCommand('QMCRST', [macro.toString()]));
  }

  /// Recalls scene memory.
  Future<void> recallMemory(String memory) {
    if (!RegExp(r'^MEMORY(30|[1-2][0-9]|[1-9])$').hasMatch(memory)) throw ArgumentError('Invalid memory: $memory');
    return _sendCommand(_buildCommand('MEM', [memory]));
  }

  /// Gets selected scene memory.
  Future<void> getMemory() => _sendCommand(_buildCommand('QMEM'));

  /// Outputs GPO.
  Future<void> outputGpo(String gpo, {bool? state}) {
    if (!RegExp(r'^GPO(1[0-6]|[1-9])$').hasMatch(gpo)) throw ArgumentError('Invalid gpo: $gpo');
    List<String> params = [gpo];
    if (state != null) params.add(state ? 'ON' : 'OFF');
    return _sendCommand(_buildCommand('GPO', params));
  }

  /// Gets GPO status.
  Future<void> getGpo(String gpo) {
    if (!RegExp(r'^GPO(1[0-6]|[1-9])$').hasMatch(gpo)) throw ArgumentError('Invalid gpo: $gpo');
    return _sendCommand(_buildCommand('QGPO', [gpo]));
  }

  /// Gets tally status.
  Future<void> getTally() => _sendCommand(_buildCommand('TLY'));

  /// Sets auto switching.
  Future<void> setAutoSwitching(bool on) => _sendCommand(_buildCommand('ASW', [on ? 'ON' : 'OFF']));

  /// Toggles auto switching.
  Future<void> toggleAutoSwitching() => _sendCommand(_buildCommand('ASW'));

  /// Gets auto switching status.
  Future<void> getAutoSwitching() => _sendCommand(_buildCommand('QASW'));

  /// Executes input scan.
  Future<void> executeInputScan(String type) {
    const validTypes = {'NORMAL', 'REVERSE', 'RANDOM'};
    if (!validTypes.contains(type.toUpperCase())) throw ArgumentError('Invalid type: $type');
    return _sendCommand(_buildCommand('INSC', [type]));
  }

  /// Executes scene memory scan.
  Future<void> executeMemoryScan(String type) {
    const validTypes = {'NORMAL', 'REVERSE', 'RANDOM'};
    if (!validTypes.contains(type.toUpperCase())) throw ArgumentError('Invalid type: $type');
    return _sendCommand(_buildCommand('MEMSC', [type]));
  }

  /// Executes PinP source scan.
  Future<void> executePinPScan(String pinp, String type) {
    if (!RegExp(r'^PinP[1-4]$').hasMatch(pinp)) throw ArgumentError('Invalid pinp: $pinp');
    const validTypes = {'NORMAL', 'REVERSE', 'RANDOM'};
    if (!validTypes.contains(type.toUpperCase())) throw ArgumentError('Invalid type: $type');
    return _sendCommand(_buildCommand('PPSC', [pinp, type]));
  }

  /// Executes DSK source scan.
  Future<void> executeDskScan(String dsk, String type) {
    if (!RegExp(r'^DSK[1-2]$').hasMatch(dsk)) throw ArgumentError('Invalid dsk: $dsk');
    const validTypes = {'NORMAL', 'REVERSE', 'RANDOM'};
    if (!validTypes.contains(type.toUpperCase())) throw ArgumentError('Invalid type: $type');
    return _sendCommand(_buildCommand('DSKSC', [dsk, type]));
  }
}

mixin SystemCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Returns ACK.
  Future<void> ack() => _sendCommand(_buildCommand('ACS'));

  /// Gets model and version.
  Future<void> getVersion() => _sendCommand(_buildCommand('VER'));

  /// Gets model and version (alias for QVER if needed, but uses VER as per docs).
  Future<void> getVersionQuery() => getVersion();

  /// Gets busy status.
  Future<void> getBusyStatus() => _sendCommand(_buildCommand('QBSY'));

  /// Sets HDCP.
  Future<void> setHdcp(bool on) => _sendCommand(_buildCommand('HDCP', [on ? 'ON' : 'OFF']));

  /// Gets HDCP status.
  Future<void> getHdcp() => _sendCommand(_buildCommand('QHDCP'));

  /// Sets test pattern.
  Future<void> setTestPattern(String pattern) {
    if (!RolandService.validTestPatterns.contains(pattern)) throw ArgumentError('Invalid pattern: $pattern');
    return _sendCommand(_buildCommand('TPT', [pattern]));
  }

  /// Gets test pattern.
  Future<void> getTestPattern() => _sendCommand(_buildCommand('QTPT'));

  /// Sets test tone.
  Future<void> setTestTone(String level, {String? freqL, String? freqR}) {
    const validLevels = {'OFF', '-20', '-10', '0dB'};
    if (!validLevels.contains(level)) throw ArgumentError('Invalid level: $level');
    const validFreqs = {'500', '1k', '2kHz'};
    if (freqL != null && !validFreqs.contains(freqL)) throw ArgumentError('Invalid freqL: $freqL');
    if (freqR != null && !validFreqs.contains(freqR)) throw ArgumentError('Invalid freqR: $freqR');
    List<String> params = [level];
    if (freqL != null) params.add(freqL);
    if (freqR != null) params.add(freqR);
    return _sendCommand(_buildCommand('TTN', params));
  }

  /// Gets test tone.
  Future<void> getTestTone() => _sendCommand(_buildCommand('QTTN'));
}

mixin CameraCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets pan and tilt.
  /// @example
  /// await service.setPanTilt('CAMERA1', 'LEFT', 'UP'); // Pans left and tilts up
  Future<void> setPanTilt(String camera, String pan, String tilt) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera format: $camera');
    int index = int.parse(camera.substring(6));
    if (index < 1 || index > 16) throw ArgumentError('Camera index must be 1-16');
    const validPans = {'LEFT', 'STOP', 'RIGHT'};
    const validTilts = {'DOWN', 'STOP', 'UP'};
    if (!validPans.contains(pan.toUpperCase())) throw ArgumentError('Invalid pan direction: $pan');
    if (!validTilts.contains(tilt.toUpperCase())) throw ArgumentError('Invalid tilt direction: $tilt');
    return _sendCommand(_buildCommand('CAMPT', [camera, pan, tilt]));
  }

  /// Sets pan/tilt speed.
  Future<void> setPanTiltSpeed(String camera, int speed) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    if (speed < 1 || speed > 24) throw ArgumentError('speed must be 1-24');
    return _sendCommand(_buildCommand('CAMPTS', [camera, speed.toString()]));
  }

  /// Gets pan/tilt speed.
  Future<void> getPanTiltSpeed(String camera) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('QCAMPTS', [camera]));
  }

  /// Sets zoom.
  Future<void> setZoom(String camera, String direction) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    const validDirections = {'WIDE_FAST', 'WIDE_SLOW', 'STOP', 'TELE_SLOW', 'TELE_FAST'};
    if (!validDirections.contains(direction.toUpperCase())) throw ArgumentError('Invalid direction: $direction');
    return _sendCommand(_buildCommand('CAMZM', [camera, direction]));
  }

  /// Resets zoom.
  Future<void> resetZoom(String camera) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('CAMZMR', [camera]));
  }

  /// Sets focus.
  Future<void> setFocus(String camera, String direction) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    const validDirections = {'NEAR', 'STOP', 'FAR'};
    if (!validDirections.contains(direction.toUpperCase())) throw ArgumentError('Invalid direction: $direction');
    return _sendCommand(_buildCommand('CAMFC', [camera, direction]));
  }

  /// Sets auto focus.
  Future<void> setAutoFocus(String camera, bool on) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('CAMAFC', [camera, on ? 'ON' : 'OFF']));
  }

  /// Gets auto focus status.
  Future<void> getAutoFocus(String camera) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('QCAMAFC', [camera]));
  }

  /// Sets auto exposure.
  Future<void> setAutoExposure(String camera, bool on) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('CAMAEP', [camera, on ? 'ON' : 'OFF']));
  }

  /// Gets auto exposure status.
  Future<void> getAutoExposure(String camera) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('QCAMAEP', [camera]));
  }

  /// Recalls preset.
  Future<void> recallPreset(String camera, String preset) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    if (!RegExp(r'^PRESET(\d+)$').hasMatch(preset)) throw ArgumentError('Invalid preset: $preset'); /// 10|[1-9]
    return _sendCommand(_buildCommand('CAMPR', [camera, preset]));
  }

  /// Gets current preset.
  Future<void> getCurrentPreset(String camera) {
    if (!RolandService.cameraRegex.hasMatch(camera)) throw ArgumentError('Invalid camera: $camera');
    return _sendCommand(_buildCommand('QCAMPR', [camera]));
  }
}

mixin SplitCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets SPLIT control.
  Future<void> setSplit(String split, bool on) => _sendCommand(_buildCommand('SPS', [split, on ? 'ON' : 'OFF']));

  /// Toggles SPLIT.
  Future<void> toggleSplit(String split) => _sendCommand(_buildCommand('SPS', [split]));

  /// Gets SPLIT status.
  Future<void> getSplit(String split) => _sendCommand(_buildCommand('QSPS', [split]));

  /// Sets SPLIT positions.
  Future<void> setSplitPositions(String split, int pgmCenter, int pvwCenter, {int? center}) {
    if (pgmCenter < RolandService.minSplitCenter || pgmCenter > RolandService.maxSplitCenter) throw ArgumentError('pgmCenter must be -500 to 500');
    if (pvwCenter < RolandService.minSplitCenter || pvwCenter > RolandService.maxSplitCenter) throw ArgumentError('pvwCenter must be -500 to 500');
    if (center != null && (center < RolandService.minSplitCenter || center > RolandService.maxSplitCenter)) throw ArgumentError('center must be -500 to 500');
    List<String> params = [split, pgmCenter.toString(), pvwCenter.toString()];
    if (center != null) params.add(center.toString());
    return _sendCommand(_buildCommand('SPT', params));
  }

  /// Gets SPLIT positions.
  Future<void> getSplitPositions(String split) => _sendCommand(_buildCommand('QSPT', [split]));
}

mixin SequencerCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Sets sequencer ON/OFF.
  Future<void> setSequencer(bool on) => _sendCommand(_buildCommand('SEQSW', [on ? 'ON' : 'OFF']));

  /// Gets sequencer status.
  Future<void> getSequencerStatus() => _sendCommand(_buildCommand('QSEQSW'));

  /// Sets sequencer auto sequence.
  Future<void> setAutoSequence(bool on) => _sendCommand(_buildCommand('SEQAS', [on ? 'ON' : 'OFF']));

  /// Gets sequencer auto sequence status.
  Future<void> getAutoSequenceStatus() => _sendCommand(_buildCommand('QSEQAS'));

  /// Sets sequencer to previous.
  Future<void> previousSequence({int? steps}) {
    if (steps != null && (steps < 0 || steps > 1)) throw ArgumentError('steps must be 0 or 1');
    List<String> params = [];
    if (steps != null) params.add(steps.toString());
    return _sendCommand(_buildCommand('SEQPV', params));
  }

  /// Advances sequencer.
  Future<void> nextSequence() => _sendCommand(_buildCommand('SEQNX'));

  /// Sets sequencer number.
  Future<void> setSequenceNumber(String seq) {
    if (seq != 'START' && !RegExp(r'^SEQ\d+$').hasMatch(seq)) throw ArgumentError('Invalid seq: $seq');
    if (seq.startsWith('SEQ')) {
      int num = int.parse(seq.substring(3));
      if (num < 1 || num > 1000) throw ArgumentError('seq number must be 1-1000');
    }
    return _sendCommand(_buildCommand('SEQJP', [seq]));
  }
}

mixin GraphicsCommands {
  String _buildCommand(String cmd, [List<String>? params]);
  Future<void> _sendCommand(String command);

  /// Selects next content.
  Future<void> nextContent() => _sendCommand(_buildCommand('GPNC'));

  /// Selects content.
  Future<void> selectContent(String content) {
    if (!RegExp(r'^CONTENT\d+$').hasMatch(content)) throw ArgumentError('Invalid content: $content');
    int num = int.parse(content.substring(7));
    if (num < 1 || num > 124) throw ArgumentError('content number must be 1-124');
    return _sendCommand(_buildCommand('GPSC', [content]));
  }

  /// Hides front content.
  Future<void> hideFrontContent() => _sendCommand(_buildCommand('GPHF'));

  /// Hides background content.
  Future<void> hideBackgroundContent() => _sendCommand(_buildCommand('GPHB'));

  /// Toggles ON AIR.
  Future<void> toggleOnAir() => _sendCommand(_buildCommand('GPOA'));
}

/// Service for communicating with Roland V-160HD device.
/// 
/// This service provides methods to control various aspects of the Roland V-160HD
/// video mixer via TCP socket commands. It supports the following command groups
/// as per the official documentation:
/// - VIDEO: CUT, ATO, QATG, FRZ, FTB, VIS, QVIS, VOS, QVOS, TRS, QTRS, TIM, QTIM,
///   PIS, QPIS, PPS, PPW, PIP, QPIP, DSK, DVW, DSS, QDSS, KYL, QKYL, KYG, QKYG,
///   SPS, SPT, QSPT, STO, QSTO, PGM, QPGM, PST, QPST, AUX, QAUX, VFL, QVFL,
///   QVISRC, QVIST
/// - AUDIO: AOS, QAOS, IAL, QIAL, IAM, QIAM, IAS, QIAS, ADT, QADT, HPF, QHPF,
///   GATE, QGATE, STLK, QSTLK, VOCH, QVOCH, OAL, QOAL, OAM, QOAM, RVB, QRVB,
///   ATM, QATM
/// - METER: MTRSW, QMTRSW, MTRLV, MTRCH, GRSW, QGRSW, GRLV, GRCH, AMSW, QAMSW,
///   AMLV, AMCH, SPSW, QSPSW, SPLV, SPCH, AUXSW, QAUXSW, AUXLV, AUXCH
/// - CONTROL: MEM, QMEM, GPO, QGPO, TLY, ASW, QASW, INSC, MEMSC, PPSC, DSKSC,
///   MCREX, QMCRST
/// - SYSTEM: ACS, VER, QBSY, HDCP, QHDCP, TPT, QTPT, TTN, QTTN
/// - CAMERA: CAMPT, CAMPTS, QCAMPTS, CAMZM, CAMZMR, CAMFC, CAMAFC, QCAMAFC,
///   CAMAEP, QCAMAEP, CAMPR, QCAMPR
/// - SPLIT: SPS, QSPS, SPT, QSPT
/// - SEQUENCER: SEQSW, QSEQSW, SEQAS, QSEQAS, SEQPV, SEQNX, SEQJP
/// - GRAPHICS: GPNC, GPSC, GPHF, GPHB, GPOA
/// 
/// Note: Auto-transmit for meters sends responses periodically without ACK; ensure listeners handle continuous data.
/// For security in production networks, enable SSL.
/// Auto-reconnect can be configured via setAutoReconnect() for resilience.
/// 
/// Example usage:
/// ```dart
/// final service = RolandService(host: '192.168.1.100', useSSL: true);
/// await service.connect();
/// await service.setProgram('INPUT1'); // Set program to INPUT1
/// await service.setFaderLevel(1024); // Set fader to mid-level
/// service.disconnect();
/// ```
class RolandService with
  VideoCommands,
  PinPCommands,
  DskCommands,
  AudioCommands,
  MeterCommands,
  ControlCommands,
  SystemCommands,
  CameraCommands,
  SplitCommands,
  SequencerCommands,
  GraphicsCommands {
  static const int defaultPort = 8023;
  static const int maxFaderLevel = 2047;
  static const int minFaderLevel = 0;
  static const int maxInputIndex = 19; // INPUT1-20
  static const int minInputIndex = 0;
  static const int maxPinPIndex = 3; // PinP1-4
  static const int minPinPIndex = 0;
  static const int maxCameraIndex = 15; // CAMERA1-16
  static const int minCameraIndex = 0;
  static const int maxMacro = 100;
  static const int minMacro = 1;
  static const int maxPreset = 10;
  static const int minPreset = 1;
  static const int maxPanTiltSpeed = 24;
  static const int minPanTiltSpeed = 1;

  // Additional constants for new commands
  static const int maxAudioLevel = 100; // 10.0 dB
  static const int minAudioLevel = -800; // -80.0 dB
  static const int maxTransitionTime = 40; // 4.0 sec
  static const int minTransitionTime = 0;
  static const int maxDskLevel = 255;
  static const int minDskLevel = 0;
  static const int maxAuxBus = 2; // AUX1-3 (0-2)
  static const int minAuxBus = 0;
  static const int maxSplit = 1; // SPLIT1-2 (0-1)
  static const int minSplit = 0;
  static const int maxMemory = 30;
  static const int minMemory = 1;
  static const int maxDelay = 5000; // 500.0 msec
  static const int minDelay = 0;
  static const int maxPinPH = 1000;
  static const int minPinPH = -1000;
  static const int maxPinPV = 1000;
  static const int minPinPV = -1000;
  static const int maxSplitCenter = 500;
  static const int minSplitCenter = -500;
  static const Duration defaultConnectTimeout = Duration(seconds: 10);
  static const Duration defaultAckTimeout = Duration(seconds: 5);
  static const Duration defaultCommandRetryDelay = Duration(milliseconds: 100);

  // Regex constants
  static final RegExp hostRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
  static final RegExp inputRegex = RegExp(r'^INPUT\d+$');
  static final RegExp cameraRegex = RegExp(r'^CAMERA\d+$');

  // Auto-transmit prefixes
  static const Set<String> _autoTransmitPrefixes = {'MTRLV', 'GRLV', 'AMLV', 'SPLV', 'AUXLV'};

  // Valid sources and parameters
  static const Set<String> validVideoSources = {
    'HDMI1', 'HDMI2', 'HDMI3', 'HDMI4', 'HDMI5', 'HDMI6', 'HDMI7', 'HDMI8',
    'SDI1', 'SDI2', 'SDI3', 'SDI4', 'SDI5', 'SDI6', 'SDI7', 'SDI8',
    'STILL1', 'STILL2', 'STILL3', 'STILL4', 'STILL5', 'STILL6', 'STILL7', 'STILL8',
    'STILL9', 'STILL10', 'STILL11', 'STILL12', 'STILL13', 'STILL14', 'STILL15', 'STILL16',
    'INPUT1', 'INPUT2', 'INPUT3', 'INPUT4', 'INPUT5', 'INPUT6', 'INPUT7', 'INPUT8',
    'INPUT9', 'INPUT10', 'INPUT11', 'INPUT12', 'INPUT13', 'INPUT14', 'INPUT15', 'INPUT16',
    'INPUT17', 'INPUT18', 'INPUT19', 'INPUT20'
  };
  static const Set<String> validVideoOutputs = {'HDMI1', 'HDMI2', 'HDMI3', 'SDI1', 'SDI2', 'SDI3', 'USB'};
  static const Set<String> validVideoOutputSources = {'PGM', 'SUB', 'PVW', 'AUX1', 'AUX2', 'AUX3', 'DSK1', 'DSK2', 'MULTI', 'INPUT1', 'STILL'};
  static const Set<String> validTransitionTypes = {'MIX', 'WIPE', 'PinP1', 'PinP2', 'PinP3', 'PinP4', 'DSK1', 'DSK2', 'OUTPUTFADE'};
  static const Set<String> validAudioOutputs = {'HDMI1', 'HDMI2', 'HDMI3', 'SDI1', 'SDI2', 'SDI3', 'XLR1', 'RCA1', 'USB', 'PHONES'};
  static const Map<String, Set<String>> validAudioOutputAssigns = {
    'HDMI1': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'HDMI2': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'HDMI3': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'SDI1': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'SDI2': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'SDI3': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'XLR1': {'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'RCA1': {'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'USB': {'AUTO', 'MAIN', 'AUX1', 'AUX2', 'AUX3'},
    'PHONES': {'MAIN', 'AUX1', 'AUX2', 'AUX3'},
  };
  static const Set<String> validTestPatterns = {'OFF', 'COLORBAR75', 'COLORBAR100', 'RAMP', 'STEP', 'HATCH', 'DIAMOND', 'CIRCLE', 'COLORBAR75-SP', 'COLORBAR100-SP', 'RAMP-SP', 'STEP-SP', 'HATCH-SP'};

  final String host;
  final int port;
  final bool useSSL;
  final Duration connectTimeout;
  final Duration ackTimeout;
  final Duration commandRetryDelay;
  Socket? _socket;
  final StreamController<dynamic> _responseController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get responseStream => _responseController.stream;
  final Queue<Completer<void>> _ackCompleters = Queue<Completer<void>>();
  final Queue<String> _commandQueue = Queue<String>();
  int _commandId = 0;
  bool _isProcessing = false;
  bool _isConnected = false;
  final StringBuffer _responseBuffer = StringBuffer();
  int _pendingCount = 0;
  static const int maxConcurrentCommands = 5;
  static const int maxBufferSize = 1024 * 1024; // 1MB

  // Auto-reconnect
  bool _autoReconnect = false;
  int _maxReconnectAttempts = 3;
  Duration _reconnectDelay = const Duration(seconds: 5);
  final Duration _minCommandInterval = const Duration(milliseconds: 10);
  DateTime _lastCommandTime = DateTime.now();

  /// Creates a new RolandService instance for communicating with a Roland V-160HD device.
  /// @example
  /// final service = RolandService(host: '192.168.1.100', port: 8023, useSSL: false);
  RolandService({required this.host, this.port = defaultPort, this.useSSL = false, this.connectTimeout = defaultConnectTimeout, this.ackTimeout = defaultAckTimeout, this.commandRetryDelay = defaultCommandRetryDelay}) {
    // Validate host
    if (host.isEmpty || !hostRegex.hasMatch(host)) {
      throw ValidationException('Invalid host: $host');
    }
  }

  /// Public method for testing response parsing
  dynamic parseResponseForTest(String response) {
    return _parseResponse(response);
  }

  /// Sets auto-reconnect on disconnection.
  void setAutoReconnect(bool enable, {int maxAttempts = 3, Duration delay = const Duration(seconds: 5)}) {
    _autoReconnect = enable;
    _maxReconnectAttempts = maxAttempts;
    _reconnectDelay = delay;
  }

  /// Helper to build commands.
  @override
  String _buildCommand(String cmd, [List<String>? params]) {
    final buffer = StringBuffer(cmd);
    if (params != null && params.isNotEmpty) {
      buffer.write(':${params.join(',')}');
    }
    buffer.write(';');
    return buffer.toString();
  }

  /// Connects to the Roland device with retries.
  /// @example
  /// final service = RolandService(host: '192.168.1.100');
  /// await service.connect();
  /// print('Connected successfully');
  Future<void> connect({int retryCount = 3}) async {
    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        dev.log('Connecting to $host:$port (attempt ${attempt + 1})');
        _socket = useSSL
            ? await SecureSocket.connect(host, port).timeout(connectTimeout)
            : await Socket.connect(host, port).timeout(connectTimeout);
        _isConnected = true;
        _socket!.listen(
          (data) => _handleResponse(utf8.decode(data)),
          onError: (error) {
            dev.log('Socket error: $error');
            _isConnected = false;
            _responseController.addError(ConnectionException('Socket error: $error'));
            _responseController.close();
          },
          onDone: () {
            dev.log('Socket closed');
            _isConnected = false;
            disconnect();
          },
        );
        dev.log('Connected successfully');
        return;
      } catch (e) {
        dev.log('Connection attempt ${attempt + 1} failed: $e');
        if (attempt == retryCount) throw ConnectionException('Connection failed after $retryCount attempts: $e');
        await Future.delayed(commandRetryDelay * (attempt + 1)); // Backoff
      }
    }
  }

  /// Reconnects to the Roland device.
  Future<void> reconnect() async {
    if (_isConnected) disconnect();
    await connect();
  }

  /// Disconnects from the Roland device.
  void disconnect() {
    dev.log('Disconnecting');
    _socket?.close();
    _socket = null;
    _isConnected = false;
    _responseBuffer.clear();
    _responseController.close();
    // Complete any pending acks with error
    while (_ackCompleters.isNotEmpty) {
      _ackCompleters.removeFirst().completeError(RolandException('Disconnected'));
    }
    // Auto-reconnect if enabled
    if (_autoReconnect && !_isConnected) {
      _attemptReconnect();
    }
  }

  /// Attempts to reconnect with retries.
  void _attemptReconnect() async {
    for (int i = 0; i < _maxReconnectAttempts; i++) {
      try {
        await connect(retryCount: 0); // No internal retries
        return;
      } catch (e) {
        if (i < _maxReconnectAttempts - 1) {
          final delay = Duration(seconds: _reconnectDelay.inSeconds * (1 << i));
          dev.log('Reconnection attempt ${i + 1} failed: $e, retrying in ${delay.inSeconds} seconds');
          await Future.delayed(delay);
        } else {
          dev.log('Reconnection failed after $_maxReconnectAttempts attempts');
        }
      }
    }
  }

  @override
  Future<void> _sendCommand(String command, {int retryCount = 3}) async {
    // Queues the command, sends it via socket, and waits for ACK using a Completer
    if (!_isConnected) throw ConnectionException('Not connected');
    // Rate limiting
    final now = DateTime.now();
    final elapsed = now.difference(_lastCommandTime);
    if (elapsed < _minCommandInterval) {
      await Future.delayed(_minCommandInterval - elapsed);
    }
    _lastCommandTime = DateTime.now();
    // Wait if too many pending
    while (_pendingCount >= maxConcurrentCommands) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _pendingCount++;
    int currentId = ++_commandId;
    dev.log('Queueing command ID $currentId: $command');
    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        final completer = Completer<void>();
        _ackCompleters.add(completer);
        _commandQueue.add('$currentId:$command');
        await _processQueue();
        await completer.future.timeout(ackTimeout);
        _pendingCount--;
        dev.log('Command ID $currentId completed successfully');
        return;
      } catch (e) {
        dev.log('Command ID $currentId attempt ${attempt + 1} failed: $e');
        if (attempt == retryCount) {
          _pendingCount--;
          rethrow;
        }
        await Future.delayed(commandRetryDelay * (attempt + 1)); // Exponential backoff
      }
    }
  }

  Future<void> _processQueue() async {
    // Processes the command queue sequentially to avoid overwhelming the device
    if (_isProcessing || !_isConnected) return;
    _isProcessing = true;
    while (_commandQueue.isNotEmpty && _isConnected) {
      String entry = _commandQueue.removeFirst();
      List<String> parts = entry.split(':');
      String id = parts[0];
      String cmd = parts.sublist(1).join(':');
      dev.log('Sending command ID $id: $cmd');
      _socket!.write(cmd);
      await _socket!.flush().timeout(const Duration(seconds: 5));
      await Future.delayed(Duration.zero); // Yield control to prevent blocking
    }
    _isProcessing = false;
  }

  void _handleResponse(String data) {
    // Accumulates incoming data into buffer, checks for overflow, processes complete responses (ended by \n), parses and emits via stream
    _responseBuffer.write(data.replaceAll('\r', ''));
    if (_responseBuffer.length > maxBufferSize) {
      _responseBuffer.clear();
      _responseController.addError(RolandException('Response buffer overflow'));
      return;
    }
    String buffer = _responseBuffer.toString();
    int endIndex;
    while ((endIndex = buffer.indexOf('\n')) != -1) {
      String response = buffer.substring(0, endIndex).trim();
      buffer = buffer.substring(endIndex + 1);
      int retryCount = 0;
      const int maxRetries = 3;
      bool parsed = false;
      while (retryCount < maxRetries && !parsed) {
        try {
          _processCompleteResponse(response);
          parsed = true;
        } catch (e) {
          retryCount++;
          if (retryCount >= maxRetries) {
            dev.log('Failed to parse response after $maxRetries attempts: $response. Error: $e');
            _responseController.addError(e);
          } else {
            dev.log('Parsing failed with error: $e for response: $response, attempt $retryCount');
          }
        }
      }
    }
    _responseBuffer.clear();
    _responseBuffer.write(buffer);
  }

  void _processCompleteResponse(String response) {
    dev.log('Received response: $response');
    // Check for ACK completion: either explicit ACK, or query responses without ACK
    bool shouldCompleteAck = response.endsWith(';ACK;') || response == 'ACK;' ||
        (response.contains(':') && !response.contains('NACK') && !response.contains('ERROR') &&
         !_autoTransmitPrefixes.any((prefix) => response.startsWith('$prefix:')));
    if (shouldCompleteAck) {
      // Complete the next pending ACK
      if (_ackCompleters.isNotEmpty) {
        _ackCompleters.removeFirst().complete();
      }
      // Parse the response
      final parsed = _parseResponse(response);
      if (parsed != null) {
        _responseController.add(parsed);
      }
    } else if (_autoTransmitPrefixes.any((prefix) => response.startsWith('$prefix:'))) {
      // Handle auto-transmit responses (no ACK completion)
      final parsed = _parseResponse(response);
      if (parsed != null) {
        _responseController.add(parsed);
      }
    } else if (response.contains('NACK') || response.contains('ERROR')) {
      // Handle errors
      if (_ackCompleters.isNotEmpty) {
        _ackCompleters.removeFirst().completeError(CommandException('Command failed: $response'));
      }
    } else {
      // Raw response for unparsed
      _responseController.add(response);
    }
  }

  dynamic _parseVideoResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'VFL':
        try {
          return FaderLevelResponse(int.parse(params[0]));
        } catch (e) {
          throw InvalidParameterException('Invalid VFL response: $response');
        }
      case 'PGM':
        return ProgramResponse(params[0], params.length > 1 ? params[1] : null);
      case 'PST':
        return PreviewResponse(params[0], params.length > 1 ? params[1] : null);
      case 'PIP':
        try {
          return PinPPositionResponse(int.parse(params[1]), int.parse(params[2]));
        } catch (e) {
          throw InvalidParameterException('Invalid PIP response: $response');
        }
      case 'VISRC':
        try {
          return VideoInputSourceResponse(int.parse(params[0]), params[1]);
        } catch (e) {
          throw InvalidParameterException('Invalid VISRC response: $response');
        }
      case 'VIST':
        return VideoInputStatusResponse(params[0], params[1]);
      case 'VIS':
        return VideoInputAssignResponse(params[0], params[1]);
      case 'QVIS':
        return VideoInputAssignResponse(params[0], params[1]);
      case 'VOS':
        return VideoOutputAssignResponse(params[0], params[1]);
      case 'QVOS':
        return VideoOutputAssignResponse(params[0], params[1]);
      case 'TRS':
        return TransitionTypeResponse(params[0]);
      case 'QTRS':
        return TransitionTypeResponse(params[0]);
      case 'TIM':
        try {
          return TransitionTimeResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid TIM response: $response');
        }
      case 'QTIM':
        try {
          return TransitionTimeResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid QTIM response: $response');
        }
      case 'ATG':
        return TransitionStatusResponse(params[0]);
      case 'QATG':
        return TransitionStatusResponse(params[0]);
      case 'FRZ':
        return FreezeResponse(params[0]);
      case 'QFRZ':
        return FreezeResponse(params[0]);
      case 'FTB':
        return FadeResponse(params[0]);
      case 'QFTB':
        return FadeResponse(params[0]);
      case 'PIS':
        return PinPSourceResponse(params[0], params[1]);
      case 'QPIS':
        return PinPSourceResponse(params[0], params[1]);
      case 'PPS':
        return PinPProgramResponse(params[0], params[1]);
      case 'QPPS':
        return PinPProgramResponse(params[0], params[1]);
      case 'PPW':
        return PinPPreviewResponse(params[0], params[1]);
      case 'QPPW':
        return PinPPreviewResponse(params[0], params[1]);
      case 'DSK':
        return DskProgramResponse(params[0], params[1]);
      case 'QDSK':
        return DskProgramResponse(params[0], params[1]);
      case 'DVW':
        return DskPreviewResponse(params[0], params[1]);
      case 'QDVW':
        return DskPreviewResponse(params[0], params[1]);
      case 'DSS':
        return DskSourceResponse(params[0], params[1], params.length > 2 ? params[2] : null);
      case 'QDSS':
        return DskSourceResponse(params[0], params[1], params.length > 2 ? params[2] : null);
      case 'KYL':
        try {
          return DskLevelResponse(int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid KYL response: $response');
        }
      case 'QKYL':
        try {
          return DskLevelResponse(int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid QKYL response: $response');
        }
      case 'KYG':
        try {
          return DskLevelResponse(int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid KYG response: $response');
        }
      case 'QKYG':
        try {
          return DskLevelResponse(int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid QKYG response: $response');
        }
      case 'AUX':
        return AuxResponse(params[0], params[1], params.length > 2 ? params[2] : null);
      case 'QAUX':
        return AuxResponse(params[0], params[1], params.length > 2 ? params[2] : null);
      case 'SPS':
        return SplitStatusResponse(params[0], params[1]);
      case 'QSPS':
        return SplitStatusResponse(params[0], params[1]);
      case 'SPT':
        try {
          return SplitPositionsResponse(params[0], int.parse(params[1]), int.parse(params[2]), params.length > 3 ? int.parse(params[3]) : null);
        } catch (e) {
          throw InvalidParameterException('Invalid SPT response: $response');
        }
      case 'QSPT':
        try {
          return SplitPositionsResponse(params[0], int.parse(params[1]), int.parse(params[2]), params.length > 3 ? int.parse(params[3]) : null);
        } catch (e) {
          throw InvalidParameterException('Invalid QSPT response: $response');
        }
      case 'STO':
        return StillResponse(params[0]);
      case 'QSTO':
        return StillResponse(params[0]);
      case 'HCP':
        return HdcpResponse(params[0]);
    }
    return null;
  }

  dynamic _parseAudioResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'AOS':
        return AudioOutputAssignResponse(params[0], params[1]);
      case 'QAOS':
        return AudioOutputAssignResponse(params[0], params[1]);
      case 'IAL':
        return AudioLevelResponse(params[0], params[1]);
      case 'QIAL':
        return AudioLevelResponse(params[0], params[1]);
      case 'OAL':
        return AudioLevelResponse(params[0], params[1]);
      case 'QOAL':
        return AudioLevelResponse(params[0], params[1]);
      case 'IAM':
        return AudioMuteResponse(params[0], params[1]);
      case 'QIAM':
        return AudioMuteResponse(params[0], params[1]);
      case 'IAS':
        return AudioSoloResponse(params[0], params[1]);
      case 'QIAS':
        return AudioSoloResponse(params[0], params[1]);
      case 'ADT':
        try {
          return AudioDelayResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid ADT response: $response');
        }
      case 'QADT':
        try {
          return AudioDelayResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid QADT response: $response');
        }
      case 'HPF':
        return AudioFilterResponse(params[0], params[1]);
      case 'QHPF':
        return AudioFilterResponse(params[0], params[1]);
      case 'GATE':
        return AudioGateResponse(params[0], params[1]);
      case 'QGATE':
        return AudioGateResponse(params[0], params[1]);
      case 'STLK':
        return AudioLinkResponse(params[0], params[1]);
      case 'QSTLK':
        return AudioLinkResponse(params[0], params[1]);
      case 'VOCH':
        return AudioChangerResponse(params[0], params[1]);
      case 'QVOCH':
        return AudioChangerResponse(params[0], params[1]);
      case 'OAM':
        return AudioOutputMuteResponse(params[0], params[1]);
      case 'QOAM':
        return AudioOutputMuteResponse(params[0], params[1]);
      case 'RVB':
        return ReverbResponse(params[0]);
      case 'QRVB':
        return ReverbResponse(params[0]);
      case 'ATM':
        return AutoMixingResponse(params[0]);
      case 'QATM':
        return AutoMixingResponse(params[0]);
    }
    return null;
  }

  dynamic _parseMeterResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'MTRLV':
        return MeterResponse(params);
      case 'GRLV':
        return MeterResponse(params);
      case 'AMLV':
        return MeterResponse(params);
      case 'SPLV':
        return MeterResponse(params);
      case 'AUXLV':
        return MeterResponse(params);
      case 'MTRCH':
        try {
          return MeterChannelResponse(int.parse(params[0]), params[1]);
        } catch (e) {
          throw InvalidParameterException('Invalid MTRCH response: $response');
        }
      case 'GRCH':
        try {
          return MeterChannelResponse(int.parse(params[0]), params[1]);
        } catch (e) {
          throw InvalidParameterException('Invalid GRCH response: $response');
        }
      case 'AMCH':
        try {
          return MeterChannelResponse(int.parse(params[0]), params[1]);
        } catch (e) {
          throw InvalidParameterException('Invalid AMCH response: $response');
        }
      case 'SPCH':
        try {
          return MeterChannelResponse(int.parse(params[0]), params[1]);
        } catch (e) {
          throw InvalidParameterException('Invalid SPCH response: $response');
        }
      case 'AUXCH':
        try {
          return MeterChannelResponse(int.parse(params[0]), params[1]);
        } catch (e) {
          throw InvalidParameterException('Invalid AUXCH response: $response');
        }
      case 'MTRSW':
        return MeterAutoTransmitResponse(params[0]);
      case 'QMTRSW':
        return MeterAutoTransmitResponse(params[0]);
      case 'GRSW':
        return CompGrAutoTransmitResponse(params[0]);
      case 'QGRSW':
        return CompGrAutoTransmitResponse(params[0]);
      case 'AMSW':
        return AutoMixingAutoTransmitResponse(params[0]);
      case 'QAMSW':
        return AutoMixingAutoTransmitResponse(params[0]);
      case 'SPSW':
        return SigPeakAutoTransmitResponse(params[0]);
      case 'QSPSW':
        return SigPeakAutoTransmitResponse(params[0]);
      case 'AUXSW':
        return AuxAutoTransmitResponse(params[0]);
      case 'QAUXSW':
        return AuxAutoTransmitResponse(params[0]);
    }
    return null;
  }

  dynamic _parseControlResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'MEM':
        return MemoryResponse(params[0]);
      case 'QMEM':
        return MemoryResponse(params[0]);
      case 'GPO':
        return GpoResponse(params[0], params[1]);
      case 'QGPO':
        return GpoResponse(params[0], params[1]);
      case 'TLY':
        try {
          return TallyResponse(params.map(int.parse).toList());
        } catch (e) {
          throw InvalidParameterException('Invalid TLY response: $response');
        }
      case 'ASW':
        return AutoSwitchingResponse(params[0]);
      case 'QASW':
        return AutoSwitchingResponse(params[0]);
    }
    return null;
  }

  dynamic _parseSystemResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'VER':
        if (params.length != 2) throw ParsingException('Invalid VER response: $response');
        return VersionResponse(params[0], params[1]);
      case 'BSY':
        return BusyResponse(params[0]);
      case 'QBSY':
        return BusyResponse(params[0]);
      case 'HDCP':
        return HdcpResponse(params[0]);
      case 'QHDCP':
        return HdcpResponse(params[0]);
      case 'TPT':
        return TestPatternResponse(params[0]);
      case 'QTPT':
        return TestPatternResponse(params[0]);
      case 'TTN':
        if (params.isEmpty) throw ParsingException('Invalid TTN response: $response');
        return TestToneResponse(params[0], params.length > 1 ? params[1] : null, params.length > 2 ? params[2] : null);
      case 'QTTN':
        if (params.isEmpty) throw ParsingException('Invalid QTTN response: $response');
        return TestToneResponse(params[0], params.length > 1 ? params[1] : null, params.length > 2 ? params[2] : null);
    }
    return null;
  }

  dynamic _parseCameraResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'CAMPTS':
        if (params.length != 2) throw ParsingException('Invalid CAMPTS response: $response');
        try {
          return PanTiltSpeedResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid CAMPTS response: $response');
        }
      case 'QCAMPTS':
        if (params.length != 2) throw ParsingException('Invalid QCAMPTS response: $response');
        try {
          return PanTiltSpeedResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid QCAMPTS response: $response');
        }
      case 'CAMPR':
        if (params.length != 2) throw ParsingException('Invalid CAMPR response: $response');
        return PresetResponse(params[0], params[1]);
      case 'QCAMPR':
        if (params.length != 2) throw ParsingException('Invalid QCAMPR response: $response');
        return PresetResponse(params[0], params[1]);
      case 'CAFC':
        return AutoFocusResponse(params[0], params[1]);
      case 'QCAMAFC':
        return AutoFocusResponse(params[0], params[1]);
      case 'CAEP':
        return AutoExposureResponse(params[0], params[1]);
      case 'QCAMAEP':
        return AutoExposureResponse(params[0], params[1]);
      case 'CPTS':
        try {
          return PanTiltSpeedResponse(params[0], int.parse(params[1]));
        } catch (e) {
          throw InvalidParameterException('Invalid CPTS response: $response');
        }
      case 'CPR':
        return PresetResponse(params[0], params[1]);
    }
    return null;
  }

  dynamic _parseMacroResponse(String cmd, List<String> params, String response) {
    switch (cmd) {
      case 'MCRST':
        return MacroStatusResponse(params[0], params[1]);
      case 'QMCRST':
        return MacroStatusResponse(params[0], params[1]);
      case 'SQS':
        return SequencerStatusResponse(params[0]);
      case 'QSEQSW':
        return SequencerStatusResponse(params[0]);
      case 'SQA':
        return AutoSequenceResponse(params[0]);
      case 'QSEQAS':
        return AutoSequenceResponse(params[0]);
    }
    return null;
  }

  dynamic _parseResponse(String response) {
    // Remove ;ACK;
    final clean = response.replaceAll(';ACK;', '').replaceAll('ACK;', '');
    final parts = clean.split(':');
    if (parts.length < 2) return null;
    final cmd = parts[0];
    final paramStr = parts[1];
    final params = paramStr.split(',');
    dynamic result;
    if ((result = _parseVideoResponse(cmd, params, response)) != null) return result;
    if ((result = _parseAudioResponse(cmd, params, response)) != null) return result;
    if ((result = _parseMeterResponse(cmd, params, response)) != null) return result;
    if ((result = _parseControlResponse(cmd, params, response)) != null) return result;
    if ((result = _parseSystemResponse(cmd, params, response)) != null) return result;
    if ((result = _parseCameraResponse(cmd, params, response)) != null) return result;
    if ((result = _parseMacroResponse(cmd, params, response)) != null) return result;
    return null;
  }

  /// Disposes the service, closing streams and disconnecting.
  void dispose() {
    disconnect();
    _responseController.close();
  }
}
