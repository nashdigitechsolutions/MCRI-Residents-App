import 'package:flutter/material.dart';
// import 'package:mcri_residents_app/screens/admin/admin_roles_screen.dart';

import '../screens/admin/admin_roles_screen.dart';
import '../screens/polls_screen.dart';
import '../screens/events_screen.dart';
import '../screens/duties_screen.dart';
import '../screens/equipment_screen.dart';
import '../screens/rooms_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/weekly_menu_screen.dart';
import '../screens/conversation_detail_screen.dart';

class NotificationRouter {
  static void handle(BuildContext context, Map<String, dynamic>? data) {
    if (data == null) return;
    final screen = data['screen'] as String?;

    switch (screen) {
      case 'poll':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PollsScreen()));
        break;
      case 'event':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const EventsScreen()));
        break;
      case 'duties':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DutiesScreen()));
        break;
      case 'equipment':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const EquipmentScreen()));
        break;
      case 'rooms':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const RoomsScreen()));
        break;
      case 'profile':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
        break;
      case 'admin_users':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AdminRolesScreen()));
        break;
      case 'home':
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case 'weekly_menu':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const WeeklyMenuScreen()));
        break;
      case 'conversation':
        final rawId = data['conversation_id'];
        final conversationId = rawId is int
            ? rawId
            : int.tryParse(rawId.toString());
        if (conversationId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ConversationDetailScreen(conversationId: conversationId),
            ),
          );
        }
        break;
      default:
        break;
    }
  }
}
