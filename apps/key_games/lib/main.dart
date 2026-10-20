// Key Games: kids' games played on a MIDI keyboard, on a phone (keyboard over
// Bluetooth LE or USB) or a PC (streamed to a TV). The games live under
// lib/games and lib/songs; the shared bones are lib/app (services, settings,
// theme), lib/input (one router for every key) and lib/widgets/game_page.dart
// (the frame every screen uses).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/services.dart';
import 'app/theme.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(KeyGamesApp(services: await AppServices.boot()));
}

class KeyGamesApp extends StatelessWidget {
  const KeyGamesApp({super.key, required this.services, this.home, this.builder});

  final AppServices services;

  // Another first screen, and a wrapper around every page (a text scale),
  // for tests.
  final Widget? home;
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return services.provide(
      child: MaterialApp(
        title: 'Key Games',
        debugShowCheckedModeBanner: false,
        theme: keyGamesTheme(),
        navigatorObservers: [services.router],
        builder: builder,
        home: home ?? const HomePage(),
      ),
    );
  }
}
