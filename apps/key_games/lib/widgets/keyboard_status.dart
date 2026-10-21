// Corner chip showing whether a keyboard is connected: a quiet green piano
// once one is, a labeled chip while looking (just the amber piano on a
// narrow phone). Tapping it opens a device list for manual
// connect/disconnect.

import 'package:flutter/material.dart';

import '../app/services.dart';

// Below this width (a phone held upright) header buttons drop their labels.
const narrowHeaderWidth = 600.0;

class KeyboardStatus extends StatelessWidget {
  const KeyboardStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final midi = AppServices.of(context).midi;
    final narrow = MediaQuery.sizeOf(context).width < narrowHeaderWidth;
    void openSheet() => showModalBottomSheet<void>(
          context: context,
          builder: (_) => const DeviceSheet(),
        );
    return ValueListenableBuilder<List<String>>(
      valueListenable: midi.connected,
      builder: (context, connected, _) {
        final ready = connected.isNotEmpty;
        if (ready || narrow) {
          return IconButton(
            tooltip: ready ? 'Keyboard ready' : 'Looking for keyboard...',
            icon: Icon(Icons.piano, color: ready ? Colors.greenAccent : Colors.amber),
            onPressed: openSheet,
          );
        }
        return ActionChip(
          avatar: const Icon(Icons.piano, color: Colors.amber),
          label: const Text('Looking for keyboard...', maxLines: 1, overflow: TextOverflow.ellipsis),
          onPressed: openSheet,
        );
      },
    );
  }
}

// Lists MIDI devices with manual connect/disconnect, for troubleshooting.
class DeviceSheet extends StatelessWidget {
  const DeviceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final midi = AppServices.of(context).midi;
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
