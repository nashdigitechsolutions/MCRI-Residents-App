import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:mcri_residents_app/config/env.dart'; // contains wsUrl constant

// directory for config is lib/config/env.dart
// This file is not included in the repository for security reasons. Please create your own config/env.dart file with the following content:
// const String wsUrl = 'wss://your-websocket-server-url';

const _pingInterval = Duration(seconds: 25);
const _pongTimeout = Duration(seconds: 10);
const _maxReconnectDelay = Duration(seconds: 30);

/// Realtime event bus over one shared WebSocket connection. Ported from the
/// web app's WebSocketContext: same ping/pong keep-alive, same generation
/// counter to stop a stale reconnect attempt from clobbering a fresh one.
class WebSocketProvider extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final Map<String, Set<void Function(dynamic)>> _listeners = {};

  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  int _generation = 0;
  bool _isConnected = false;
  String? _token;

  bool get isConnected => _isConnected;

  /// Named distinctly from ChangeNotifier's own addListener/removeListener
  /// (different signature — this is per-event-type, not "notify me of any
  /// change") to avoid confusing the two mechanisms.
  void on(String type, void Function(dynamic) callback) {
    _listeners.putIfAbsent(type, () => {}).add(callback);
  }

  void off(String type, void Function(dynamic) callback) {
    _listeners[type]?.remove(callback);
  }

  void _dispatch(String type, dynamic payload) {
    for (final cb in (_listeners[type] ?? const {})) {
      cb(payload);
    }
  }

  void connect(String token) {
    _token = token;
    _reconnectAttempt = 0;
    _startConnection();
  }

  void disconnect() {
    _generation++; // invalidate any in-flight attempt
    _cancelTimers();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _token = null;
    notifyListeners();
  }

  void _cancelTimers() {
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _reconnectTimer?.cancel();
  }

  void _startConnection() {
    if (_token == null) return;
    final myGeneration = ++_generation;

    final uri = Uri.parse('$wsUrl?token=${Uri.encodeComponent(_token!)}');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    _subscription = channel.stream.listen(
      (event) {
        if (myGeneration != _generation) return;
        _pongTimer?.cancel(); // any frame proves the connection is alive

        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(event as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        if (payload['type'] == 'pong' || payload['type'] == 'connected') return;
        _dispatch(payload['type'] as String? ?? '', payload);
      },
      onDone: () => _onClosed(myGeneration),
      onError: (_) => _onClosed(myGeneration),
      cancelOnError: true,
    );

    channel.ready
        .then((_) {
          if (myGeneration != _generation) return;
          _isConnected = true;
          _reconnectAttempt = 0;
          notifyListeners();
        })
        .catchError((_) {
          _onClosed(myGeneration);
        });

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (myGeneration != _generation) return;
      try {
        channel.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {
        return;
      }
      _pongTimer?.cancel();
      _pongTimer = Timer(_pongTimeout, () {
        if (myGeneration != _generation) return;
        _channel?.sink.close();
      });
    });
  }

  void _onClosed(int myGeneration) {
    if (myGeneration != _generation) return; // superseded already

    _isConnected = false;
    notifyListeners();
    _pingTimer?.cancel();
    _pongTimer?.cancel();

    _reconnectAttempt++;
    final delayMs = (1000 * (1 << (_reconnectAttempt - 1))).clamp(
      0,
      _maxReconnectDelay.inMilliseconds,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (myGeneration == _generation) _startConnection();
    });
  }

  /// Send a JSON-encodable payload over the socket, if connected.
  void send(Map<String, dynamic> payload) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(payload));
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
