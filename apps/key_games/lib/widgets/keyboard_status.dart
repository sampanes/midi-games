// Corner chip showing whether a keyboard is connected; tapping it opens a
// device list for manual connect/disconnect.

import 'package:flutter/material.dart';

import '../midi/midi_input.dart';

class KeyboardStatus extends StatelessWidget {
  const KeyboardStatus({super.key, required this.midi});

  final MidiInput midi;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: midi.connected,
      builder: (context, connected, _) {
        final ready = connected.isNotEmpty;
        return ActionChip(
          avatar: Icon(Icons.piano, color: ready ? Colors.greenAccent : Colors.amber),
          label: Text(
            ready ? 'Keyboard ready' : 'Looking for keyboard...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => DeviceSheet(midi: midi),
          ),
        );
      },
    );
  }
}

// Lists MIDI devices with manual connect/disconnect, for troubleshooting.
class DeviceSheet extends StatelessWidget {
  const DeviceSheet({super.key, required this.midi});

  final MidiInput midi;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder(
        valueListenable: midi.devices,
        builder: (context, devices, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('MIDI devices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Keyboards connect by themselves. On a phone, do not pair the '
                'keyboard in Bluetooth settings; that sends the sound to the keyboard.'),
            ValueListenableBuilder(
              valueListenable: midi.problem,
              builder: (context, problem, _) => problem.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(problem, style: const TextStyle(color: Colors.amber)),
                    ),
            ),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('None found yet. Turn the keyboard on.'),
              ),
            for (final d in devices)
              ListTile(
                title: Text(d.name),
                subtitle: Text('${d.type.name} - ${d.connectionState.name}'),
                trailing: d.connected
                    ? OutlinedButton(onPressed: () => midi.disconnect(d), child: const Text('Disconnect'))
                    : FilledButton(onPressed: () => midi.connect(d), child: const Text('Connect')),
              ),
          ],
        ),
      ),
    );
  }
}
