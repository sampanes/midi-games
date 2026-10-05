// Latency spike: connect to a MIDI keyboard (USB or Bluetooth LE) and play a
// tone per key, on Android and Windows. Answers one question: does the
// key-to-sound delay feel good enough to build the games in Flutter?

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';

import 'synth.dart';

void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keys Spike',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const SpikePage(),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final MidiCommand _midi = MidiCommand();
  final Synth _synth = Synth();
  StreamSubscription<MidiDataReceivedEvent>? _rxSub;
  StreamSubscription<MidiSetupChange>? _setupSub;
  List<MidiDevice> _devices = const [];
  String _status = 'Starting...';
  String _audioStatus = 'Audio not started';
  int _bufferSize = 256;
  int _events = 0;
  int? _lastNote;
  String _lastMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_startAudio());
    unawaited(_startMidi());
  }

  Future<void> _startAudio() async {
    setState(() => _audioStatus = 'Starting audio (buffer $_bufferSize)...');
    try {
      await _synth.start(bufferSize: _bufferSize);
      setState(() => _audioStatus =
          'Audio ready: buffer $_bufferSize frames '
          '(~${(_bufferSize / 44.1).toStringAsFixed(1)} ms)');
    } catch (error) {
      setState(() => _audioStatus = 'Audio failed: $error');
    }
  }

  Future<void> _startMidi() async {
    try {
      _midi.configureBleTransport(UniversalBleMidiTransport());
      _setupSub = _midi.onMidiSetupChanged?.listen((_) {
        unawaited(_refreshDevices());
      });
      _rxSub = _midi.onMidiDataReceived?.listen(_onMidi);
      await _midi.startBluetooth();
      await _midi.waitUntilBluetoothIsInitialized();
      if (_midi.bluetoothState != BluetoothState.poweredOn) {
        _setStatus('Bluetooth is ${_midi.bluetoothState.name}. USB devices still work.');
      } else {
        await _midi.startScanningForBluetoothDevices();
        _setStatus('Scanning. Turn the keyboard on, then tap Connect.');
      }
    } catch (error) {
      _setStatus('MIDI setup failed: $error');
    }
    await _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    final devices = await _midi.devices ?? const <MidiDevice>[];
    if (!mounted) return;
    setState(() => _devices = devices);
  }

  Future<void> _connect(MidiDevice device) async {
    _setStatus('Connecting to ${device.name}...');
    try {
      await _midi.connectToDevice(device);
      _setStatus('Connected: ${device.name}. Play some keys.');
    } catch (error) {
      _setStatus('Connect failed: $error');
    }
    await _refreshDevices();
  }

  void _disconnect(MidiDevice device) {
    _midi.disconnectDevice(device);
    _setStatus('Disconnected ${device.name}.');
    unawaited(_refreshDevices());
  }

  void _onMidi(MidiDataReceivedEvent event) {
    final message = event.message;
    if (message is NoteOnMessage && message.velocity > 0) {
      _synth.noteOn(message.note, message.velocity);
      setState(() {
        _events++;
        _lastNote = message.note;
        _lastMessage = 'note ${message.note} on ch ${message.channel + 1} '
            'vel ${message.velocity} via ${event.transport.name}';
      });
    } else if (message is NoteOnMessage || message is NoteOffMessage) {
      final note = message is NoteOnMessage
          ? message.note
          : (message as NoteOffMessage).note;
      _synth.noteOff(note);
    }
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _status = text);
  }

  Future<void> _changeBuffer(int? size) async {
    if (size == null || size == _bufferSize) return;
    _bufferSize = size;
    await _synth.stop();
    await _startAudio();
  }

  @override
  void dispose() {
    unawaited(_rxSub?.cancel());
    unawaited(_setupSub?.cancel());
    _midi.stopScanningForBluetoothDevices();
    unawaited(_synth.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _lastNote == null ? Colors.grey.shade800 : noteColor(_lastNote!);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text(_audioStatus)),
                  DropdownButton<int>(
                    value: _bufferSize,
                    items: const [128, 256, 512, 1024, 2048]
                        .map((s) => DropdownMenuItem(value: s, child: Text('buf $s')))
                        .toList(),
                    onChanged: _changeBuffer,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Devices', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(onPressed: _refreshDevices, child: const Text('Refresh')),
                ],
              ),
              SizedBox(
                height: 150,
                child: _devices.isEmpty
                    ? const Center(child: Text('No MIDI devices yet.'))
                    : ListView(
                        children: [
                          for (final d in _devices)
                            ListTile(
                              dense: true,
                              title: Text(d.name),
                              subtitle: Text('${d.type.name} - ${d.connectionState.name}'),
                              trailing: d.connected
                                  ? OutlinedButton(
                                      onPressed: () => _disconnect(d),
                                      child: const Text('Disconnect'))
                                  : FilledButton(
                                      onPressed: () => _connect(d),
                                      child: const Text('Connect')),
                            ),
                        ],
                      ),
              ),
              Expanded(
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 60),
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      _lastNote == null ? '-' : noteName(_lastNote!),
                      style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
              Text('Notes: $_events   $_lastMessage', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              // On-screen key: compare touch-to-sound with key-to-sound.
              GestureDetector(
                onTapDown: (_) => _synth.noteOn(72, 100),
                onTapUp: (_) => _synth.noteOff(72),
                onTapCancel: () => _synth.noteOff(72),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Tap to test sound (C5)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

