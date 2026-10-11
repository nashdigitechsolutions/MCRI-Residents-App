import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mcri_residents_app/screens/rooms_screen.dart';
import 'package:mcri_residents_app/screens/house_rules_screen.dart';
import 'package:mcri_residents_app/screens/events_screen.dart';
import 'package:mcri_residents_app/screens/equipment_screen.dart';
import 'package:mcri_residents_app/screens/duties_screen.dart';
import 'package:mcri_residents_app/screens/weekly_menu_screen.dart';
import 'package:mcri_residents_app/screens/admin/admin_dashboard_screen.dart';

import '../providers/auth_provider.dart';

const _accent = Color(0xFF3355FF);
const _danger = Color(0xFFEF4444);

class _DrawerItem {
  final IconData icon;
  final String label;
  final Widget Function() screenBuilder;
  final bool highlighted;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.screenBuilder,
    this.highlighted = false,
  });
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  static final List<_DrawerItem> _items = [
    _DrawerItem(
      icon: Icons.meeting_room_outlined,
      label: 'Rooms',
      screenBuilder: () => const RoomsScreen(),
    ),
    _DrawerItem(
      icon: Icons.calendar_today_outlined,
      label: 'Events',
      screenBuilder: () => const EventsScreen(),
    ),
    _DrawerItem(
      icon: Icons.build_outlined,
      label: 'Equipment',
      screenBuilder: () => const EquipmentScreen(),
    ),
    _DrawerItem(
      icon: Icons.cleaning_services_outlined,
      label: 'Duties',
      screenBuilder: () => const DutiesScreen(),
    ),
    _DrawerItem(
      icon: Icons.menu_book_outlined,
      label: 'House rules',
      screenBuilder: () => const HouseRulesScreen(),
    ),
    _DrawerItem(
      icon: Icons.restaurant_outlined,
      label: 'Weekly menu',
      highlighted: true,
      screenBuilder: () => const WeeklyMenuScreen(),
    ),
  ];

  static final _adminItem = _DrawerItem(
    icon: Icons.admin_panel_settings_outlined,
    label: 'Admin dashboard',
    screenBuilder: () => const AdminDashboardScreen(),
  );

  void _open(BuildContext context, _DrawerItem item) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => item.screenBuilder()));
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Log out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out', style: TextStyle(color: _danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    Navigator.of(context).pop(); // close the drawer
    await context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.user?.roleId == 1;

    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          children: [
            // --- header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'lib/assets/logo.png',
                      height: 38,
                      width: 38,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'MCRI Residents',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),

            // --- nav items ---
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                children: [
                  for (final item in _items) ...[
                    _DrawerRow(item: item, onTap: () => _open(context, item)),
                    const SizedBox(height: 2),
                  ],
                  if (isAdmin) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                      child: Text(
                        'ADMIN',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    _DrawerRow(
                      item: _adminItem,
                      onTap: () => _open(context, _adminItem),
                    ),
                  ],
                ],
              ),
            ),

            // --- logout + footer ---
            Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _handleLogout(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 19, color: _danger),
                        SizedBox(width: 14),
                        Text(
                          'Log out',
                          style: TextStyle(
                            color: _danger,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Text(
                '© ${DateTime.now().year} MCRI Residents',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  final _DrawerItem item;
  final VoidCallback onTap;

  const _DrawerRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: item.highlighted ? _accent : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 19,
                color: item.highlighted
                    ? Colors.white
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Text(
                item.label,
                style: TextStyle(
                  color: item.highlighted ? Colors.white : colors.onSurface,
                  fontSize: 14,
                  fontWeight: item.highlighted
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
