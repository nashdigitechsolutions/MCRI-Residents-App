import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/websocket_provider.dart';

/// Keeps a screen in sync with the server in real time.
///
/// Call [listenLive] once from `initState` with the socket event types that
/// mean "your data changed" and a quiet refetch callback. Bursts of events
/// (e.g. twenty residents voting at once) are debounced into one refetch,
/// and the screen also refetches when the socket reconnects so nothing
/// missed while offline is lost. Everything is torn down in `dispose`.
mixin LiveRefresh<T extends StatefulWidget> on State<T> {
  WebSocketProvider? _liveWs;
  final Map<String, void Function(dynamic)> _liveHandlers = {};
  Timer? _liveDebounce;
  VoidCallback? _liveOnChange;
  bool _liveWasConnected = true;
  Duration _liveDelay = const Duration(milliseconds: 500);

  void listenLive(
    List<String> eventTypes,
    VoidCallback onChange, {
    Duration debounce = const Duration(milliseconds: 500),
    bool Function(Map<String, dynamic> payload)? where,
  }) {
    final ws = _liveWs = context.read<WebSocketProvider>();
    _liveOnChange = onChange;
    _liveDelay = debounce;
    _liveWasConnected = ws.isConnected;

    for (final type in eventTypes) {
      void handler(dynamic payload) {
        if (where != null &&
            payload is Map<String, dynamic> &&
            !where(payload)) {
          return;
        }
        scheduleLiveRefresh();
      }

      _liveHandlers[type] = handler;
      ws.on(type, handler);
    }
    ws.addListener(_onLiveSocketChanged);
  }

  /// Queue a debounced refetch (also handy after a local action).
  void scheduleLiveRefresh() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(_liveDelay, () {
      if (mounted) _liveOnChange?.call();
    });
  }

  void _onLiveSocketChanged() {
    final connected = _liveWs?.isConnected ?? false;
    if (connected && !_liveWasConnected) scheduleLiveRefresh();
    _liveWasConnected = connected;
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    final ws = _liveWs;
    if (ws != null) {
      _liveHandlers.forEach(ws.off);
      ws.removeListener(_onLiveSocketChanged);
    }
    super.dispose();
  }
}
