import 'package:flutter/material.dart';

import '../navigation/app_navigator.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/conversation_detail_screen.dart';
import '../screens/duties_screen.dart';
import '../screens/equipment_screen.dart';
import '../screens/events_screen.dart';
import '../screens/house_rules_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/rooms_screen.dart';
import '../screens/weekly_menu_screen.dart';

/// Opens the screen a notification points at.
///
/// Works for every entry point: push taps (cold start, background or
/// foreground), the in-app drop-down banner, and the Notifications list.
/// If the app isn't ready yet (splash still playing, not signed in), the
/// route is held and opened as soon as [markReady] is called by MainShell.
class NotificationRouter {
  NotificationRouter._();

  static bool _ready = false;
  static Map<String, dynamic>? _pending;

  /// Called by MainShell once it's on screen (signed in, splash done).
  static void markReady() {
    _ready = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open(pending));
    }
  }

  /// Called when MainShell goes away (sign-out).
  static void markNotReady() => _ready = false;

  /// Back-compat entry point.
  static void handle(BuildContext _, Map<String, dynamic>? data) => open(data);

  static int? _int(dynamic v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);

  /// Whether this payload has somewhere specific to go.
  static bool canOpen(Map<String, dynamic>? data) =>
      data != null && data['screen'] is String;

  static void open(Map<String, dynamic>? data) {
    if (data == null) return;
    final nav = navigatorKey.currentState;
    if (!_ready || nav == null) {
      _pending = data; // replay once the shell is up
      return;
    }

    final screen = data['screen'] as String?;

    void tab(int index) {
      nav.popUntil((r) => r.isFirst);
      shellTab.value = index;
    }

    void push(Widget page, String name) {
      // Don't stack the same screen twice if it's already on top.
      var onTop = false;
      nav.popUntil((r) {
        onTop = r.settings.name == name;
        return true;
      });
      if (onTop) nav.pop();
      nav.push(
        MaterialPageRoute(
          settings: RouteSettings(name: name),
          builder: (_) => page,
        ),
      );
    }

    switch (screen) {
      case 'conversation':
        final id = _int(data['conversation_id']);
        if (id == null) return tab(ShellTab.messages);
        if (ConversationDetailScreen.openConversationId == id) return;
        push(ConversationDetailScreen(conversationId: id), 'conversation/$id');
      case 'conversations' || 'messages':
        tab(ShellTab.messages);
      case 'poll' || 'polls':
        tab(ShellTab.polls);
      case 'home' || 'announcement' || 'announcements':
        tab(ShellTab.home);
      case 'profile':
        tab(ShellTab.profile);
      case 'settings':
        tab(ShellTab.settings);
      case 'event' || 'events':
        push(const EventsScreen(), 'events');
      case 'duties':
        push(const DutiesScreen(), 'duties');
      case 'equipment':
        push(
          EquipmentScreen(
            initialTab: data['tab'] as String?,
            highlightRequestId: _int(data['request_id']),
            highlightReportId: _int(data['report_id']),
          ),
          'equipment',
        );
      case 'rooms':
        push(const RoomsScreen(), 'rooms');
      case 'weekly_menu' || 'menu':
        push(const WeeklyMenuScreen(), 'weekly_menu');
      case 'house_rules':
        push(const HouseRulesScreen(), 'house_rules');
      case 'admin_users' || 'admin':
        push(const AdminDashboardScreen(), 'admin');
      default:
        push(const NotificationsScreen(), 'notifications');
    }
  }

  /// Best-effort destination for notifications stored before routes were
  /// saved with them, inferred from the title the API uses.
  static Map<String, dynamic>? inferFromTitle(String title) {
    final t = title.toLowerCase();
    if (t.startsWith('new poll') || t.startsWith('poll closed')) {
      return {'screen': 'poll'};
    }
    if (t.startsWith('new announcement')) return {'screen': 'home'};
    if (t.contains('equipment') ||
        t.startsWith('fault') ||
        t.startsWith('repair') ||
        t.startsWith('fixed:') ||
        t.startsWith('bought:') ||
        t.startsWith('approved:') ||
        t.startsWith('request') ||
        t.startsWith('update on your report')) {
      return {'screen': 'equipment'};
    }
    if (t.contains('event')) return {'screen': 'event'};
    if (t.contains('duty') || t.contains('duties')) return {'screen': 'duties'};
    if (t.contains('menu')) return {'screen': 'weekly_menu'};
    if (t.contains('room')) return {'screen': 'rooms'};
    if (t.contains('signed up')) return {'screen': 'admin_users'};
    if (t.startsWith('welcome')) return {'screen': 'profile'};
    return null;
  }
}
