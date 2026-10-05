# keys_spike

Latency spike for a Flutter version of the games: connect a MIDI keyboard over
Bluetooth LE (or USB), play notes through a low-latency SoLoud synth, and show
each note's color. The buffer-size menu compares audio latency settings.

Targets Android and Windows.

    flutter build apk --debug
    flutter build windows --debug

`no_xiph_libs` in pubspec.yaml skips flutter_soloud's prebuilt Ogg/Opus
downloads; the spike only synthesizes waveforms.
