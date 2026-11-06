import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/unread_provider.dart';
import '../providers/websocket_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/ui.dart';
import 'conversation_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'polls_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

typedef _Tab = ({
  IconData icon,
  IconData activeIcon,
  String title,
  Widget Function() build,
  int Function(UnreadProvider)? badgeCount,
});

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static final List<_Tab> _tabs = [
    (
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      title: 'Messages',
      build: () => const ConversationsScreen(),
      badgeCount: (u) => u.unreadConversations,
    ),
    (
      icon: Icons.ramen_dining_outlined,
      activeIcon: Icons.ramen_dining_rounded,
      title: 'Meal polls',
      build: () => const PollsScreen(),
      badgeCount: null,
    ),
    (
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      title: 'Home',
      build: () => const HomeScreen(),
      badgeCount: null,
    ),
    (
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      title: 'Profile',
      build: () => const ProfileScreen(),
      badgeCount: null,
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      title: 'Settings',
      build: () => const SettingsScreen(),
      badgeCount: null,
    ),
  ];

  static const _homeIndex = 2;

  // Home is the middle tab and the default on launch.
  int _currentIndex = _homeIndex;

  // Tabs are only built the first time they're opened (then kept alive), so
  // launch only pays for the Home screen's network calls, not all five.
  final _built = <int>{_homeIndex};

  void _select(int i) {
    if (i == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = i;
      _built.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final online = context.select<WebSocketProvider, bool>(
      (w) => w.isConnected,
    );

    return PopScope(
      // Android back from another tab returns Home instead of closing the app.
      canPop: _currentIndex == _homeIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(_homeIndex);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_tabs[_currentIndex].title),
          actions: [
            IconButton(
              tooltip: 'All services',
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MoreScreen())),
            ),
            const SizedBox(width: 4),
          ],
        ),
        drawer: const AppDrawer(),
        body: Column(
          children: [
            _DelayedOfflineBanner(online: online),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    _built.contains(i)
                        ? _tabs[i].build()
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          tabs: _tabs,
          currentIndex: _currentIndex,
          onSelect: _select,
        ),
      ),
    );
  }
}

/// Only shows the banner if we've been offline for a couple of seconds, so a
/// normal reconnect on app resume doesn't flash it.
class _DelayedOfflineBanner extends StatefulWidget {
  final bool online;
  const _DelayedOfflineBanner({required this.online});

  @override
  State<_DelayedOfflineBanner> createState() => _DelayedOfflineBannerState();
}

class _DelayedOfflineBannerState extends State<_DelayedOfflineBanner> {
  bool _show = false;
  int _token = 0;

  @override
  void didUpdateWidget(covariant _DelayedOfflineBanner old) {
    super.didUpdateWidget(old);
    if (widget.online == old.online) return;
    final t = ++_token;
    if (widget.online) {
      setState(() => _show = false);
    } else {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted && t == _token && !widget.online) {
          setState(() => _show = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => OfflineBanner(visible: _show);
}

class _BottomBar extends StatelessWidget {
  final List<_Tab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _BottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = context.watch<UnreadProvider>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final selected = i == currentIndex;
              final count = tab.badgeCount?.call(unread) ?? 0;
              final color = selected
                  ? AppColors.primary
                  : scheme.onSurfaceVariant;

              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: count > 0 ? '${tab.title}, $count unread' : tab.title,
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    containedInkWell: true,
                    highlightShape: BoxShape.rectangle,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          height: 30,
                          width: selected ? 52 : 40,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          alignment: Alignment.center,
                          child: Badge(
                            isLabelVisible: count > 0,
                            label: Text(count > 9 ? '9+' : '$count'),
                            child: Icon(
                              selected ? tab.activeIcon : tab.icon,
                              size: 22,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: color,
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
