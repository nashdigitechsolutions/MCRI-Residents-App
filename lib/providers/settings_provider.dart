import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../utils/haptics.dart';

/// User preferences, stored server-side as one JSON blob
/// (user_settings.preferences) shared by the app and the website.
///
/// Keys this build doesn't know about (e.g. the website's `language`) are
/// kept in [extra] and written back untouched, so saving here never erases
/// a setting made elsewhere.
class Preferences {
  // Appearance
  final String theme; // light | dark | system
  final String textSize; // small | normal | large
  final bool compactLists;
  final bool haptics;

  // Notifications (pushes are filtered server-side by these keys)
  final bool notificationsEnabled;
  final bool chatNotifications;
  final bool notifyAnnouncements;
  final bool notifyPolls;
  final bool notifyEquipment;
  final bool notifyEvents;
  final bool notifyDuties;
  final bool notifyMenu;
  final bool inAppBanners; // app-only: drop-down banner while app is open

  // Privacy
  final bool showOnlineStatus;

  final Map<String, dynamic> extra;

  const Preferences({
    this.theme = 'light',
    this.textSize = 'normal',
    this.compactLists = false,
    this.haptics = true,
    this.notificationsEnabled = true,
    this.chatNotifications = true,
    this.notifyAnnouncements = true,
    this.notifyPolls = true,
    this.notifyEquipment = true,
    this.notifyEvents = true,
    this.notifyDuties = true,
    this.notifyMenu = true,
    this.inAppBanners = true,
    this.showOnlineStatus = true,
    this.extra = const {},
  });

  static const _known = {
    'theme',
    'text_size',
    'compact_lists',
    'haptics',
    'notifications_enabled',
    'chat_notifications',
    'notify_announcements',
    'notify_polls',
    'notify_equipment',
    'notify_events',
    'notify_duties',
    'notify_menu',
    'in_app_banners',
    'show_online_status',
  };

  /// Text scale multiplier for [textSize].
  double get textScale => switch (textSize) {
    'small' => 0.9,
    'large' => 1.15,
    _ => 1.0,
  };

  factory Preferences.fromJson(Map<String, dynamic> json) {
    bool b(String k, [bool d = true]) => json[k] is bool ? json[k] as bool : d;
    return Preferences(
      theme: json['theme'] as String? ?? 'light',
      textSize: json['text_size'] as String? ?? 'normal',
      compactLists: b('compact_lists', false),
      haptics: b('haptics'),
      notificationsEnabled: b('notifications_enabled'),
      chatNotifications: b('chat_notifications'),
      notifyAnnouncements: b('notify_announcements'),
      notifyPolls: b('notify_polls'),
      notifyEquipment: b('notify_equipment'),
      notifyEvents: b('notify_events'),
      notifyDuties: b('notify_duties'),
      notifyMenu: b('notify_menu'),
      inAppBanners: b('in_app_banners'),
      showOnlineStatus: b('show_online_status'),
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'theme': theme,
    'text_size': textSize,
    'compact_lists': compactLists,
    'haptics': haptics,
    'notifications_enabled': notificationsEnabled,
    'chat_notifications': chatNotifications,
    'notify_announcements': notifyAnnouncements,
    'notify_polls': notifyPolls,
    'notify_equipment': notifyEquipment,
    'notify_events': notifyEvents,
    'notify_duties': notifyDuties,
    'notify_menu': notifyMenu,
    'in_app_banners': inAppBanners,
    'show_online_status': showOnlineStatus,
  };

  Preferences copyWith({
    String? theme,
    String? textSize,
    bool? compactLists,
    bool? haptics,
    bool? notificationsEnabled,
    bool? chatNotifications,
    bool? notifyAnnouncements,
    bool? notifyPolls,
    bool? notifyEquipment,
    bool? notifyEvents,
    bool? notifyDuties,
    bool? notifyMenu,
    bool? inAppBanners,
    bool? showOnlineStatus,
  }) {
    return Preferences(
      theme: theme ?? this.theme,
      textSize: textSize ?? this.textSize,
      compactLists: compactLists ?? this.compactLists,
      haptics: haptics ?? this.haptics,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      chatNotifications: chatNotifications ?? this.chatNotifications,
      notifyAnnouncements: notifyAnnouncements ?? this.notifyAnnouncements,
      notifyPolls: notifyPolls ?? this.notifyPolls,
      notifyEquipment: notifyEquipment ?? this.notifyEquipment,
      notifyEvents: notifyEvents ?? this.notifyEvents,
      notifyDuties: notifyDuties ?? this.notifyDuties,
      notifyMenu: notifyMenu ?? this.notifyMenu,
      inAppBanners: inAppBanners ?? this.inAppBanners,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      extra: extra,
    );
  }
}

class SettingsProvider extends ChangeNotifier {
  Preferences _prefs = const Preferences();
  bool _loaded = false;

  Preferences get prefs => _prefs;
  bool get loaded => _loaded;

  Future<void> fetch() async {
    try {
      final data = await ApiService.get('/user-settings');
      final raw = (data is Map && data['preferences'] is Map)
          ? Map<String, dynamic>.from(data['preferences'] as Map)
          : <String, dynamic>{};
      _prefs = Preferences.fromJson(raw);
    } catch (e) {
      // Fall back to defaults — same graceful behavior as the web app.
    } finally {
      _loaded = true;
      AppHaptics.enabled = _prefs.haptics;
      notifyListeners();
    }
  }

  /// Called on logout, so a new login never briefly shows a leftover theme
  /// from the previous session before the fresh fetch resolves.
  void reset() {
    _prefs = const Preferences();
    _loaded = false;
    AppHaptics.enabled = true;
    notifyListeners();
  }

  Future<bool> update(Preferences Function(Preferences) updater) async {
    final previous = _prefs;
    _prefs = updater(_prefs);
    AppHaptics.enabled = _prefs.haptics;
    notifyListeners(); // optimistic — screen updates instantly

    try {
      await ApiService.post('/user-settings', {'preferences': _prefs.toJson()});
      return true;
    } catch (e) {
      _prefs = previous;
      AppHaptics.enabled = _prefs.haptics;
      notifyListeners(); // revert on failure
      return false;
    }
  }
}
