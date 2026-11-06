import 'dart:io';
import 'dart:async';

import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'api_service.dart';
import 'onesignal_service.dart';

class DeviceRegistrationService {
  DeviceRegistrationService._();

  static bool _observing = false;
  static String? _lastSent;

  /// The push subscription ID isn't always ready the instant permission is
  /// granted — OneSignal sets it up asynchronously. We register immediately
  /// if it's already available, and also listen (once) for it to change.
  static Future<void> registerWhenReady() async {
    _lastSent = null;
    final existing = OneSignalService.subscriptionId;
    if (existing != null && existing.isNotEmpty) {
      await _sendToBackend(existing);
    }

    if (_observing) return;
    _observing = true;
    OneSignal.User.pushSubscription.addObserver((state) {
      final id = state.current.id;
      if (id != null && id.isNotEmpty) _sendToBackend(id);
    });
  }

  static Future<void> _sendToBackend(String playerId) async {
    if (_lastSent == playerId) return;
    try {
      await ApiService.post('/device-tokens', {
        'player_id': playerId,
        // This build creates the high-importance "mcri_alerts" channel
        // (MainActivity.kt), so the API may target it for heads-up banners.
        'alerts_channel': Platform.isAndroid,
      });
      _lastSent = playerId;
    } catch (_) {
      // non-fatal — next app open will retry via registerWhenReady()
    }
  }

  /// Must run while the auth token is still present, otherwise the API
  /// rejects it and this device keeps receiving the old user's pushes.
  static Future<void> unregister() async {
    _lastSent = null;
    if (OneSignalService.subscriptionId == null) return;
    try {
      await ApiService.delete('/device-tokens')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // non-fatal
    }
  }
}
