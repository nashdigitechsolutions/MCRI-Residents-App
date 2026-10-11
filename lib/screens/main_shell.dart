import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/unread_provider.dart';
import '../widgets/app_drawer.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'conversation_screen.dart';
import 'polls_screen.dart';

const _accent = Color(0xFF3355FF);
const _badgeRed = Color(0xFFEF4444);

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static final List<
    ({
      IconData icon,
      String title,
      Widget screen,
      int Function(UnreadProvider)? badgeCount,
    })
  >
  _tabs = [
    (
      icon: Icons.chat_bubble_rounded,
      title: 'Messages',
      screen: const ConversationsScreen(),
      badgeCount: (u) => u.unreadConversations,
    ),
    (
      icon: Icons.ramen_dining_rounded,
      title: 'Meal polls',
      screen: const PollsScreen(),
      badgeCount: null,
    ),
    (
      icon: Icons.home_rounded,
      title: 'Home',
      screen: const HomeScreen(),
      badgeCount: null,
    ),
    (
      icon: Icons.person_rounded,
      title: 'Profile',
      screen: const ProfileScreen(),
      badgeCount: null,
    ),
    (
      icon: Icons.settings_rounded,
      title: 'Settings',
      screen: const SettingsScreen(),
      badgeCount: null,
    ),
  ];

  // Home is the middle tab and the default on launch.
  int _currentIndex = 2;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = context.watch<UnreadProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(_tabs[_currentIndex].title), elevation: 0),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _tabs.map((t) => t.screen).toList(),
        ),
      ),
      bottomNavigationBar: Container(
        height: 60,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final selected = i == _currentIndex;
              final tab = _tabs[i];
              final count = tab.badgeCount?.call(unread) ?? 0;

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _currentIndex = i),
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          transform: Matrix4.translationValues(
                            0,
                            selected ? -14 : 0,
                            0,
                          ),
                          padding: EdgeInsets.all(selected ? 12 : 8),
                          decoration: BoxDecoration(
                            color: selected ? _accent : Colors.transparent,
                            shape: BoxShape.circle,
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: _accent.withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            tab.icon,
                            size: 22,
                            color: selected
                                ? Colors.white
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        if (count > 0)
                          Positioned(
                            // When selected, the icon is translated up -14,
                            // so the badge needs to ride along with it rather
                            // than staying pinned to the unselected position.
                            top: selected ? -14 : -2,
                            right: selected ? 2 : -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              decoration: BoxDecoration(
                                color: _badgeRed,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.surface,
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                count > 9 ? '9+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
