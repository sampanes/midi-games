// Learns the Back control: the next pad or button pressed on the keyboard
// (a note on any channel, or a control change) is remembered, a confirmation
// shows for a moment, and the page closes. Listens to the raw MIDI streams,
// not the router, because pads outside the game note range must count too;
// the router stands aside meanwhile, so the pad does not go back instead.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../input/back_control.dart';
import '../input/key_router.dart';
import '../midi/midi_input.dart';
import '../widgets/game_page.dart';

class LearnBackPage extends StatefulWidget {
  const LearnBackPage({super.key});

  @override
  State<LearnBackPage> createState() => _LearnBackPageState();
}

class _LearnBackPageState extends State<LearnBackPage> {
  StreamSubscription<NoteEvent>? _noteSub;
  StreamSubscription<ButtonEvent>? _buttonSub;
  Timer? _closeTimer;
  BackControl? _learned;
  KeyRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_noteSub != null) return;
    final services = AppServices.of(context);
    final midi = services.midi;
    _router = services.router..learning = true;
    _noteSub = midi.notes.listen(_onNote);
    _buttonSub = midi.buttons.listen(_onButton);
  }

  @override
  void dispose() {
    _router?.learning = false;
    unawaited(_noteSub?.cancel());
    unawaited(_buttonSub?.cancel());
    _closeTimer?.cancel();
    super.dispose();
  }

  void _onNote(NoteEvent event) {
    if (!event.on || _learned != null) return;
    _save(BackControl(ControlKind.note, event.channel, event.note));
  }

  void _onButton(ButtonEvent event) {
    if (event.value <= 0 || _learned != null) return;
    _save(BackControl(ControlKind.button, event.channel, event.controller));
  }

  void _save(BackControl control) {
    // Learned: from now on that pad goes back, even during the confirmation.
    _router?.learning = false;
    final services = AppServices.of(context);
    unawaited(services.settings.setBackControl(control));
    services.synth.tune([84, 88, 91], stepMs: 90, lengthMs: 160);
    setState(() => _learned = control);
    _closeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final learned = _learned;
    final scale = uiScale(context);
    return GamePage(
      title: 'Back pad',
      body: ScaledChrome(
        scale: scale,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  learned == null ? Icons.touch_app_rounded : Icons.check_circle_rounded,
                  size: 96 * scale,
                  color: learned == null ? Colors.white70 : AppColors.starGold,
                ),
                SizedBox(height: 16 * scale),
                Text(
                  learned == null
                      ? 'Press the pad or button you want to use for Back.'
                      : 'Back is now ${learned.label}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12 * scale),
                const Text(
                  'Not a piano key: that key would leave every game.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
