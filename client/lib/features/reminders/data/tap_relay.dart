import 'dart:async';

/// Fans reminder taps out to every listener on one broadcast stream, and
/// replays a pending launch payload exactly once to whichever listener
/// subscribes first.
class TapRelay {
  TapRelay({String? launchPayload}) {
    _launchPayload = launchPayload;
    _controller = StreamController<String>.broadcast(onListen: _onListen);
  }

  late final StreamController<String> _controller;

  /// The payload of the notification that launched the app, if any and if
  /// not yet delivered. Cleared once handed to a listener.
  String? _launchPayload;

  void _onListen() {
    final payload = _launchPayload;
    if (payload == null) return;
    _launchPayload = null;
    // Deferred so it plays as a normal stream event to whichever listener
    // triggered this onListen, rather than synchronously inside `listen()`.
    scheduleMicrotask(() => _controller.add(payload));
  }

  /// The same broadcast stream on every access, so every subscriber shares
  /// it and a second `listen()` never throws.
  Stream<String> get stream => _controller.stream;

  void add(String payload) => _controller.add(payload);

  Future<void> close() => _controller.close();
}
