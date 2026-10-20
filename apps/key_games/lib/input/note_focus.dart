// Registers the page it sits in with the KeyRouter, so the page gets the
// player's keys while it is on top: [picks] for letters that choose
// something, [onNote] for everything else. Every page has exactly one, inside
// GamePage.

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../midi/midi_input.dart';
import 'key_router.dart';

class NoteFocus extends StatefulWidget {
  const NoteFocus({super.key, this.picks = const {}, this.onNote, required this.child});

  final Map<int, VoidCallback> picks;
  final void Function(NoteEvent event)? onNote;
  final Widget child;

  @override
  State<NoteFocus> createState() => _NoteFocusState();
}

class _NoteFocusState extends State<NoteFocus> {
  late final KeyHandler _handler = KeyHandler(picks: widget.picks, onNote: widget.onNote);
  KeyRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handler.route = ModalRoute.of(context);
    if (_router == null) {
      _router = AppServices.of(context).router;
      _router!.attach(_handler);
    }
  }

  @override
  void didUpdateWidget(NoteFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handler
      ..picks = widget.picks
      ..onNote = widget.onNote;
  }

  @override
  void dispose() {
    _router?.detach(_handler);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
