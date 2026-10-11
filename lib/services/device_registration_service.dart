import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'api_service.dart';
import 'onesignal_service.dart';

class DeviceRegistrationService {
  /// The push subscription ID isn't always ready the instant permission is
  /// granted — OneSignal sets it up asynchronously. We register immediately
  /// if it's already available, and also listen for it to become available,
  /// so we never miss sending it to the backend.
  static Future<void> registerWhenReady() async {
    final existing = OneSignalService.subscriptionId;
    if (existing != null && existing.isNotEmpty) {
      await _sendToBackend(existing);
    }

    OneSignal.User.pushSubscription.addObserver((state) {
      final id = state.current.id;
      if (id != null && id.isNotEmpty) {
        _sendToBackend(id);
      }
    });
  }

  static Future<void> _sendToBackend(String playerId) async {
    try {
      await ApiService.post('/device-tokens', {'player_id': playerId});
    } catch (e) {
      // non-fatal — next app open will retry via registerWhenReady()
    }
  }

  static Future<void> unregister() async {
    final id = OneSignalService.subscriptionId;
    if (id == null) return;
    try {
      await ApiService.delete('/device-tokens');
    } catch (e) {
      // non-fatal
    }
  }
}
