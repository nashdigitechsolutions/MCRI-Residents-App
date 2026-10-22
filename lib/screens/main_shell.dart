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
      bottomNavigationBar: SafeArea(
  minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
  child: Container(
    height: 72,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: colors.outlineVariant.withValues(alpha: 0.6),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: List.generate(_tabs.length, (i) {
        final selected = i == _currentIndex;
        final tab = _tabs[i];
        final count = tab.badgeCount?.call(unread) ?? 0;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _currentIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: selected
                    ? _accent.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.12 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          tab.icon,
                          size: 22,
                          color: selected
                              ? _accent
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: -6,
                          right: -9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            decoration: BoxDecoration(
                              color: _badgeRed,
                              borderRadius: BorderRadius.circular(10),
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
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: selected ? 10 : 9,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selected
                          ? _accent
                          : colors.onSurfaceVariant,
                    ),
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 3,
                    width: selected ? 14 : 0,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(10),
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
