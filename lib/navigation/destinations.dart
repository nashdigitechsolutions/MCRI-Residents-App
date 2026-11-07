import 'package:flutter/material.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_profiles_screen.dart';
import '../screens/duties_screen.dart';
import '../screens/equipment_screen.dart';
import '../screens/events_screen.dart';
import '../screens/house_rules_screen.dart';
import '../screens/rooms_screen.dart';
import '../screens/weekly_menu_screen.dart';

/// One secondary area of the app. The drawer and the "All services" hub are
/// both built from [appDestinations], so they can never drift apart.
class AppDestination {
  final IconData icon;
  final String label;
  final String caption;
  final String routeName;
  final Widget Function() builder;
  final bool adminOnly;

  const AppDestination({
    required this.icon,
    required this.label,
    required this.caption,
    required this.routeName,
    required this.builder,
    this.adminOnly = false,
  });
}

final List<AppDestination> appDestinations = [
  AppDestination(
    icon: Icons.meeting_room_outlined,
    label: 'Rooms',
    caption: 'Room allocation and occupancy',
    routeName: 'rooms',
    builder: () => const RoomsScreen(),
  ),
  AppDestination(
    icon: Icons.calendar_today_outlined,
    label: 'Events',
    caption: 'Community calendar and RSVPs',
    routeName: 'events',
    builder: () => const EventsScreen(),
  ),
  AppDestination(
    icon: Icons.build_outlined,
    label: 'Equipment',
    caption: 'Request items and report faults',
    routeName: 'equipment',
    builder: () => const EquipmentScreen(),
  ),
  AppDestination(
    icon: Icons.cleaning_services_outlined,
    label: 'Duties',
    caption: 'Your chores and the weekly roster',
    routeName: 'duties',
    builder: () => const DutiesScreen(),
  ),
  AppDestination(
    icon: Icons.menu_book_outlined,
    label: 'House rules',
    caption: 'Guidelines everyone follows',
    routeName: 'house_rules',
    builder: () => const HouseRulesScreen(),
  ),
  AppDestination(
    icon: Icons.restaurant_outlined,
    label: 'Weekly menu',
    caption: "What's cooking this week",
    routeName: 'weekly_menu',
    builder: () => const WeeklyMenuScreen(),
  ),
  AppDestination(
    icon: Icons.admin_panel_settings_outlined,
    label: 'Admin dashboard',
    caption: 'Manage residents, roles and requests',
    routeName: 'admin_dashboard',
    builder: () => const AdminDashboardScreen(),
    adminOnly: true,
  ),
  AppDestination(
    icon: Icons.groups_2_outlined,
    label: 'All profiles',
    caption: 'View everyone · log in as a user',
    routeName: 'admin_profiles',
    builder: () => const AdminProfilesScreen(),
    adminOnly: true,
  ),
];

List<AppDestination> destinationsFor({required bool isAdmin}) =>
    appDestinations.where((d) => isAdmin || !d.adminOnly).toList();
