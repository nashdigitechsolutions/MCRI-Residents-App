import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

class Preferences {
  String theme;
  bool notificationsEnabled;
  bool chatNotifications;
  bool showOnlineStatus;
  bool compactLists;

  Preferences({
    this.theme = 'light',
    this.notificationsEnabled = true,
    this.chatNotifications = true,
    this.showOnlineStatus = true,
    this.compactLists = false,
  });

  factory Preferences.fromJson(Map<String, dynamic> json) {
    return Preferences(
      theme: json['theme'] as String? ?? 'light',
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      chatNotifications: json['chat_notifications'] as bool? ?? true,
      showOnlineStatus: json['show_online_status'] as bool? ?? true,
      compactLists: json['compact_lists'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'notifications_enabled': notificationsEnabled,
      'chat_notifications': chatNotifications,
      'show_online_status': showOnlineStatus,
      'compact_lists': compactLists,
    };
  }

  Preferences copyWith({
    String? theme,
    bool? notificationsEnabled,
    bool? chatNotifications,
    bool? showOnlineStatus,
    bool? compactLists,
  }) {
    return Preferences(
      theme: theme ?? this.theme,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      chatNotifications: chatNotifications ?? this.chatNotifications,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      compactLists: compactLists ?? this.compactLists,
    );
  }
}

class SettingsProvider extends ChangeNotifier {
  Preferences _prefs = Preferences();
  bool _loaded = false;

  Preferences get prefs => _prefs;
  bool get loaded => _loaded;

  Future<void> fetch() async {
    try {
      final data = await ApiService.get('/user-settings');
      final raw = (data is Map && data['preferences'] is Map)
          ? data['preferences'] as Map<String, dynamic>
          : <String, dynamic>{};
      _prefs = Preferences.fromJson(raw);
    } catch (e) {
      // Fall back to defaults — same graceful behavior as the web app.
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Called on logout, so a new login never briefly shows a leftover theme
  /// from the previous session before the fresh fetch resolves.
  void reset() {
    _prefs = Preferences();
    _loaded = false;
    notifyListeners();
  }

  Future<bool> update(Preferences Function(Preferences) updater) async {
    final previous = _prefs;
    _prefs = updater(_prefs);
    notifyListeners(); // optimistic — screen updates instantly

    try {
      await ApiService.post('/user-settings', {'preferences': _prefs.toJson()});
      return true;
    } catch (e) {
      _prefs = previous;
      notifyListeners(); // revert on failure
      return false;
    }
  }
}
