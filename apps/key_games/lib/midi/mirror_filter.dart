// A keyboard plugged in by USB AND connected over Bluetooth (or exposing
// several USB ports) sends every message on more than one device at once.
// This drops a message when the same message arrived from a different device
// within the window. Repeats from the same device always pass.
//
// Port of createMirrorFilter in src/games/color-keys.js.

class MirrorFilter {
  MirrorFilter({this.windowMs = 60});

  final int windowMs;
  final Map<String, ({String deviceId, int atMs})> _lastSeen = {};

  bool accept(String deviceId, String messageKey, int atMs) {
    final previous = _lastSeen[messageKey];
    _lastSeen[messageKey] = (deviceId: deviceId, atMs: atMs);
    if (_lastSeen.length > 512) {
      _lastSeen.removeWhere((_, seen) => atMs - seen.atMs > windowMs);
    }
    if (previous == null) return true;
    return previous.deviceId == deviceId || atMs - previous.atMs > windowMs;
  }
}
