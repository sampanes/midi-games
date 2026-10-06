// Key Games: kids' games played on a MIDI keyboard, on a phone (keyboard over
// Bluetooth LE or USB) or a PC (streamed to a TV). Games: Color Keys, Songs.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/synth.dart';
import 'home_page.dart';
import 'midi/midi_input.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const KeyGamesApp());
}

class KeyGamesApp extends StatefulWidget {
  const KeyGamesApp({super.key});

  @override
  State<KeyGamesApp> createState() => _KeyGamesAppState();
}

class _KeyGamesAppState extends State<KeyGamesApp> {
  final Synth _synth = Synth();
  final MidiInput _midi = MidiInput();

  @override
  void initState() {
    super.initState();
    unawaited(_synth.start());
    unawaited(_midi.start());
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Key Games',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(synth: _synth, midi: _midi),
    );
  }
}
