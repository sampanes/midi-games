// Finds MIDI keyboards and connects to them without any taps: every Bluetooth
// LE MIDI device the scan finds, plus every wired device that has an input
// port. Notes from all of them arrive on one stream, de-duplicated.
//
// On Android, connect over Bluetooth only from inside the app. A keyboard
// paired in the phone's Bluetooth settings can be treated as an audio device,
// and the phone then sends app sound to it instead of the speaker.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';

import 'mirror_filter.dart';

class NoteEvent {
  const NoteEvent(this.note, this.velocity, {required this.on});

  final int note;
  final int velocity;
  final bool on;
}

class MidiInput {
  static const _poll = Duration(seconds: 2);
  static const _retryAfter = Duration(seconds: 10);

  final MidiCommand _midi = MidiCommand();
  final MirrorFilter _mirror = MirrorFilter();
  final StreamController<NoteEvent> _notes = StreamController.broadcast();

  // Names of connected devices; empty while still looking.
  final ValueNotifier<List<String>> connected = ValueNotifier(const []);
  final ValueNotifier<List<MidiDevice>> devices = ValueNotifier(const []);
  final ValueNotifier<String> problem = ValueNotifier('');

  final Map<String, DateTime> _failedAt = {};
  final Set<String> _manuallyDisconnected = {};
  StreamSubscription<MidiDataReceivedEvent>? _rxSub;
  StreamSubscription<MidiSetupChange>? _setupSub;
  Timer? _timer;
  bool _bleReady = false;
  bool _scanning = false;
  bool _busy = false;

  Stream<NoteEvent> get notes => _notes.stream;

  Future<void> start() async {
    _midi.configureBleTransport(UniversalBleMidiTransport());
    _rxSub = _midi.onMidiDataReceived?.listen(_onData);
    _setupSub = _midi.onMidiSetupChanged?.listen((_) => unawaited(_refresh()));
    try {
      await _midi.startBluetooth();
      await _midi.waitUntilBluetoothIsInitialized();
      _bleReady = _midi.bluetoothState == BluetoothState.poweredOn;
      if (!_bleReady) problem.value = 'Bluetooth is off. Turn it on to use a wireless keyboard.';
    } catch (error) {
      problem.value = 'Bluetooth unavailable: $error';
    }
    await _refresh();
    _timer = Timer.periodic(_poll, (_) => unawaited(_refresh()));
  }

  Future<void> connect(MidiDevice device) async {
    _manuallyDisconnected.remove(device.id);
    _failedAt.remove(device.id);
    await _connect(device);
  }

  void disconnect(MidiDevice device) {
    _manuallyDisconnected.add(device.id);
    _midi.disconnectDevice(device);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final list = await _midi.devices ?? const <MidiDevice>[];
      devices.value = list;
      for (final device in list) {
        if (!device.connected && _wanted(device)) await _connect(device);
      }
      final names = [for (final d in list) if (d.connected) d.name];
      if (!listEquals(names, connected.value)) connected.value = names;
      await _updateScan(list);
    } catch (error) {
      problem.value = 'MIDI error: $error';
    } finally {
      _busy = false;
    }
  }

  bool _wanted(MidiDevice device) {
    if (_manuallyDisconnected.contains(device.id)) return false;
    if (device.connectionState != MidiConnectionState.disconnected) return false;
    final failed = _failedAt[device.id];
    if (failed != null && DateTime.now().difference(failed) < _retryAfter) return false;
    if (device.type == MidiDeviceType.ble) return true;
    // Wired: only devices that can send notes to us (skips software synths).
    return device.type == MidiDeviceType.serial && device.inputPorts.isNotEmpty;
  }

  Future<void> _connect(MidiDevice device) async {
    try {
      await _midi.connectToDevice(device);
      _failedAt.remove(device.id);
    } catch (error) {
      // Typical cause on Windows: another program (a browser tab) holds the port.
      _failedAt[device.id] = DateTime.now();
      problem.value = 'Could not connect to ${device.name}: $error';
    }
  }

  // Scan only while no Bluetooth keyboard is connected, to save battery.
  Future<void> _updateScan(List<MidiDevice> list) async {
    if (!_bleReady) return;
    final haveBle = list.any((d) => d.type == MidiDeviceType.ble && d.connected);
    if (!haveBle && !_scanning) {
      _scanning = true;
      await _midi.startScanningForBluetoothDevices();
    } else if (haveBle && _scanning) {
      _scanning = false;
      _midi.stopScanningForBluetoothDevices();
    }
  }

  void _onData(MidiDataReceivedEvent event) {
    final message = event.message;
    final NoteEvent note;
    if (message is NoteOnMessage) {
      note = NoteEvent(message.note, message.velocity, on: message.velocity > 0);
    } else if (message is NoteOffMessage) {
      note = NoteEvent(message.note, message.velocity, on: false);
    } else {
      return;
    }
    final key = '${note.on}/${note.note}/${note.velocity}';
    if (_mirror.accept(event.device.id, key, DateTime.now().millisecondsSinceEpoch)) {
      _notes.add(note);
    }
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_rxSub?.cancel());
    unawaited(_setupSub?.cancel());
    if (_scanning) _midi.stopScanningForBluetoothDevices();
    unawaited(_notes.close());
  }
}
