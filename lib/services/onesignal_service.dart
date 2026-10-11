import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Single wrapper around all OneSignal SDK calls.
class OneSignalService {
  static const _appId = '35d61ec6-616e-4b54-a68b-13dd397d0a1c';

  static void initialize() {
    OneSignal.Debug.setLogLevel(OSLogLevel.warn);
    OneSignal.initialize(_appId);
  }

  static Future<bool> requestPermission() {
    return OneSignal.Notifications.requestPermission(true);
  }

  /// Fires when the user taps a push notification — whether the app was
  /// backgrounded or fully closed at the time.
  static void listenForTaps(void Function(Map<String, dynamic>? data) onTap) {
    OneSignal.Notifications.addClickListener((event) {
      onTap(event.notification.additionalData);
    });
  }

  /// The ID OneSignal assigned to this specific device/app install. We send
  /// this to our own backend rather than relying on OneSignal's own
  /// external_id linking, which requires login() to succeed silently in the
  /// background with no easy way to confirm it actually worked.
  static String? get subscriptionId => OneSignal.User.pushSubscription.id;
}
