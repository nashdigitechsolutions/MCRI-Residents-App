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
const _accentSoft = Color(0xFF6B7CFF);
const _danger = Color(0xFFEF4444);

class _DrawerItem {
  final IconData icon;
  final String label;
  final String routeName;
  final Widget Function() screenBuilder;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.routeName,
    required this.screenBuilder,
  });
}

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static final List<_DrawerItem> _items = [
    _DrawerItem(
      icon: Icons.meeting_room_outlined,
      label: 'Rooms',
      routeName: 'rooms',
      screenBuilder: () => const RoomsScreen(),
    ),
    _DrawerItem(
      icon: Icons.calendar_today_outlined,
      label: 'Events',
      routeName: 'events',
      screenBuilder: () => const EventsScreen(),
    ),
    _DrawerItem(
      icon: Icons.build_outlined,
      label: 'Equipment',
      routeName: 'equipment',
      screenBuilder: () => const EquipmentScreen(),
    ),
    _DrawerItem(
      icon: Icons.cleaning_services_outlined,
      label: 'Duties',
      routeName: 'duties',
      screenBuilder: () => const DutiesScreen(),
    ),
    _DrawerItem(
      icon: Icons.menu_book_outlined,
      label: 'House rules',
      routeName: 'house_rules',
      screenBuilder: () => const HouseRulesScreen(),
    ),
    _DrawerItem(
      icon: Icons.restaurant_outlined,
      label: 'Weekly menu',
      routeName: 'weekly_menu',
      screenBuilder: () => const WeeklyMenuScreen(),
    ),
  ];

  static final _adminItem = _DrawerItem(
    icon: Icons.admin_panel_settings_outlined,
    label: 'Admin dashboard',
    routeName: 'admin_dashboard',
    screenBuilder: () => const AdminDashboardScreen(),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Staggered interval for item at [index] out of [total].
  Animation<double> _itemAnim(int index, int total) {
    final step = 0.45 / (total + 1);
    final start = (index * step).clamp(0.0, 1.0);
    final end = (start + 0.55).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  void _open(BuildContext context, _DrawerItem item) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: item.routeName),
        builder: (_) => item.screenBuilder(),
      ),
    );
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

    Navigator.of(context).pop();
    await context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.user?.roleId == 1;
    final currentRoute = ModalRoute.of(context)?.settings.name;

    final totalItems = _items.length + (isAdmin ? 1 : 0) + 1; // +1 for logout

    return Drawer(
      backgroundColor: colors.surface,
      elevation: 16,
      shadowColor: _accent.withValues(alpha: 0.25),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // --- gradient header ---
              _AnimatedItem(
                animation: _itemAnim(0, totalItems),
                child: _Header(colors: colors),
              ),

              // --- nav items ---
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  children: [
                    for (int i = 0; i < _items.length; i++) ...[
                      _AnimatedItem(
                        animation: _itemAnim(i + 1, totalItems),
                        child: _DrawerRow(
                          item: _items[i],
                          selected: _items[i].routeName == currentRoute,
                          onTap: () => _open(context, _items[i]),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (isAdmin) ...[
                      _AnimatedItem(
                        animation: _itemAnim(_items.length + 1, totalItems),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                          child: Text(
                            'ADMIN',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                      ),
                      _AnimatedItem(
                        animation: _itemAnim(_items.length + 2, totalItems),
                        child: _DrawerRow(
                          item: _adminItem,
                          selected: _adminItem.routeName == currentRoute,
                          onTap: () => _open(context, _adminItem),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // --- logout ---
              _AnimatedItem(
                animation: _itemAnim(totalItems - 1, totalItems),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: _LogoutButton(onTap: () => _handleLogout(context)),
                ),
              ),

              // --- footer ---
              Padding(
                padding: const EdgeInsets.only(bottom: 14, top: 6),
                child: Text(
                  '© ${DateTime.now().year} MCRI Residents',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 10.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final ColorScheme colors;
  const _Header({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accent, _accentSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset(
                'lib/assets/logo.png',
                height: 40,
                width: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'MCRI Residents',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your community hub',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nav row
// ---------------------------------------------------------------------------

class _DrawerRow extends StatefulWidget {
  final _DrawerItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DrawerRow> createState() => _DrawerRowState();
}

class _DrawerRowState extends State<_DrawerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selected;

    // Elevated active state + soft hover glow.
    final bgColor = selected
        ? _accent
        : _hovered
        ? _accent.withValues(alpha: 0.08)
        : Colors.transparent;

    final shadows = <BoxShadow>[];
    if (selected) {
      shadows.add(
        BoxShadow(
          color: _accent.withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: shadows,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            splashColor: _accent.withValues(alpha: 0.15),
            highlightColor: _accent.withValues(alpha: 0.06),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Icon in a soft rounded tile.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.20)
                          : colors.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      widget.item.icon,
                      size: 17,
                      color: selected ? Colors.white : _accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: TextStyle(
                        color: selected ? Colors.white : colors.onSurface,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  // Active pill indicator.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------------

class _LogoutButton extends StatefulWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hovered
              ? _danger.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            splashColor: _danger.withValues(alpha: 0.15),
            onTap: widget.onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entrance animation wrapper
// ---------------------------------------------------------------------------

class _AnimatedItem extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _AnimatedItem({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.12, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
