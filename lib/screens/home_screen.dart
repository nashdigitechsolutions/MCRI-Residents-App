import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../models/duty.dart';
import '../models/duty_status.dart';
import '../models/event.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/live_refresh.dart';
import '../utils/initials.dart';
import '../navigation/app_navigator.dart';
import '../widgets/ui.dart';
import 'wifi_payments_screen.dart';
import 'duties_screen.dart';
import 'events_screen.dart';
import 'equipment_screen.dart';
import 'polls_screen.dart';
import 'house_rules_screen.dart';
import 'rooms_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/admin_roles_screen.dart';
import 'notifications_screen.dart';
import '../providers/unread_provider.dart';

const _accent = AppColors.primary;
const _red = AppColors.danger;

const _reactions = [
  (emoji: '👍', key: 'like', label: 'Like'),
  (emoji: '❤️', key: 'love', label: 'Love'),
  (emoji: '😂', key: 'laugh', label: 'Funny'),
  (emoji: '😮', key: 'wow', label: 'Surprised'),
  (emoji: '😢', key: 'sad', label: 'Sad'),
  (emoji: '🎉', key: 'celebrate', label: 'Celebrate'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with LiveRefresh {
  List<Announcement> _announcements = [];
  List<Event> _events = [];
  List<Duty> _myDuties = [];
  List<Map<String, dynamic>> _openMaintenance = [];
  int _pendingEquipmentCount = 0;
  bool _loading = true;
  String? _reactingKey;
  bool _isAvailable = true;
  bool _savingAvailability = false;

  bool get _isAdmin => context.read<AuthProvider>().user?.roleId == 1;

  @override
  void initState() {
    super.initState();
    _loadAvailabilityCache();
    _loadDashboard();
    _loadUsername();
    // Admin stats (pending equipment requests) stay current live.
    if (_isAdmin) {
      listenLive(
        ['equipment_updated'],
        () => _loadDashboard(showLoading: false),
        debounce: const Duration(seconds: 1),
      );
    }
  }

  String _cacheKey(int? userId) => 'mcri_profile_cache_${userId ?? 'anon'}';
  String? _username;

  Future<void> _loadUsername() async {
    try {
      final data = await ApiService.get('/profile');

      final profile = data as Map<String, dynamic>;
      final username = profile['username']?.toString().trim();

      if (!mounted) return;

      if (username != null && username.isNotEmpty) {
        setState(() {
          _username = username;
        });
      }
    } catch (e) {
      debugPrint('Could not load username: $e');
    }
  }

  Future<void> _loadAvailabilityCache() async {
    final userId = context.read<AuthProvider>().user?.userId;
    final cached = await StorageService.getItem(_cacheKey(userId));
    if (cached != null) {
      try {
        final parsed = jsonDecode(cached) as Map<String, dynamic>;
        if (parsed['is_available'] is bool) {
          setState(() => _isAvailable = parsed['is_available'] as bool);
        }
      } catch (e) {
        // ignore corrupt cache
      }
    }
  }

  Future<void> _loadDashboard({bool showLoading = true}) async {
    final isAdmin = _isAdmin;
    final myId = context.read<AuthProvider>().user?.userId;
    if (showLoading) setState(() => _loading = true);
    try {
      final futures = <Future<dynamic>>[
        ApiService.get('/announcements').catchError((_) => []),
        ApiService.get('/events').catchError((_) => []),
        ApiService.get('/duties').catchError((_) => []),
        ApiService.get('/maintenance-requests').catchError((_) => []),
        if (isAdmin)
          ApiService.get('/equipment-requests').catchError((_) => []),
      ];
      final results = await Future.wait(futures);

      final allAnnouncements = (results[0] as List)
          .map((j) => Announcement.fromJson(j as Map<String, dynamic>))
          .toList();
      final allEvents = (results[1] as List)
          .map((j) => Event.fromJson(j as Map<String, dynamic>))
          .toList();
      final allDuties = (results[2] as List)
          .map((j) => Duty.fromJson(j as Map<String, dynamic>))
          .toList();
      final allMaintenance = (results[3] as List).cast<Map<String, dynamic>>();

      setState(() {
        _announcements = allAnnouncements.take(3).toList();
        _events = allEvents
            .where((e) => e.endDate.isAfter(DateTime.now()))
            .take(3)
            .toList();
        _myDuties = allDuties
            .where(
              (d) => d.assignedTo == myId && d.status != DutyStatus.completed,
            )
            .take(3)
            .toList();
        _openMaintenance = isAdmin
            ? allMaintenance.where((m) => m['status'] == 'open').toList()
            : [];
        if (isAdmin && results.length > 4) {
          final equip = (results[4] as List).cast<Map<String, dynamic>>();
          _pendingEquipmentCount = equip
              .where((r) => r['status'] == 'pending')
              .length;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Future<void> _toggleAvailability(bool next) async {
    final previous = _isAvailable;
    setState(() {
      _isAvailable = next;
      _savingAvailability = true;
    });
    final user = context.read<AuthProvider>().user;
    try {
      await ApiService.patch('/set-profile', {
        'user_id': user?.userId,
        'is_available': next,
      });
      final key = _cacheKey(user?.userId);
      final existingRaw = await StorageService.getItem(key);
      final existing = existingRaw != null
          ? (jsonDecode(existingRaw) as Map<String, dynamic>)
          : <String, dynamic>{};
      existing['is_available'] = next;
      await StorageService.setItem(key, jsonEncode(existing));
    } catch (e) {
      setState(() => _isAvailable = previous);
      _notify('Could not update availability', isError: true);
    } finally {
      setState(() => _savingAvailability = false);
    }
  }

  void _toggleDarkMode(bool dark) {
    context.read<SettingsProvider>().update(
      (p) => p.copyWith(theme: dark ? 'dark' : 'light'),
    );
  }

  Future<void> _handleReaction(
    Announcement announcement,
    String reactionKey,
  ) async {
    final requestKey = '${announcement.announcementId}-$reactionKey';
    setState(() => _reactingKey = requestKey);

    final togglingOff = announcement.userReaction == reactionKey;
    setState(() {
      _announcements = _announcements
          .map(
            (a) => a.announcementId == announcement.announcementId
                ? a.copyWith(userReaction: togglingOff ? null : reactionKey)
                : a,
          )
          .toList();
    });

    try {
      await ApiService.post('/announcements/react', {
        'announcement_id': announcement.announcementId,
        'reaction': togglingOff ? null : reactionKey,
      });
    } catch (e) {
      _notify('Reaction failed', isError: true);
      _loadDashboard();
    } finally {
      setState(() => _reactingKey = null);
    }
  }

  Future<void> _openNewAnnouncementSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewAnnouncementSheet(),
    );
    if (created == true) {
      _notify('Announcement posted');
      _loadDashboard();
    }
  }

  void _openReactionsViewer(Announcement announcement) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReactionsViewerSheet(announcement: announcement),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;

    final username =
        (_username ?? context.read<AuthProvider>().user?.username ?? '').trim();

    final name = username.isNotEmpty ? ', ${username.split(' ').first}' : '';

    if (hour < 12) return 'Good morning$name';
    if (hour < 18) return 'Good afternoon$name';
    return 'Good evening$name';
  }

  void _go(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = context.watch<SettingsProvider>().prefs.theme == 'dark';
    context.watch<AuthProvider>().user;
    final isAdmin = _isAdmin;
    final unread = context.watch<UnreadProvider>();

    final nextDuty =
        (_myDuties.toList()
              ..sort((a, b) => a.assignedDate.compareTo(b.assignedDate)))
            .firstOrNull;

    return Scaffold(
      body: _loading
          ? const AppLoadingView(message: 'Getting your residence ready…')
          : AppRefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _hero(colors, isDark, isAdmin, unread),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isAdmin &&
                            (_openMaintenance.isNotEmpty ||
                                _pendingEquipmentCount > 0)) ...[
                          _attentionCard(colors),
                          const SizedBox(height: 18),
                        ],

                        if (nextDuty != null) ...[
                          SectionHeader(
                            'Your next duty',
                            actionLabel: 'All duties',
                            onAction: () => _go(const DutiesScreen()),
                          ),
                          _nextDutyCard(colors, nextDuty),
                          const SizedBox(height: 22),
                        ],

                        SectionHeader(
                          'Upcoming events',
                          actionLabel: 'Calendar',
                          onAction: () => _go(const EventsScreen()),
                        ),
                        if (_events.isEmpty)
                          _emptyCard(
                            colors,
                            Icons.event_available_outlined,
                            'Nothing scheduled right now.',
                          )
                        else
                          _eventsCard(colors),
                        const SizedBox(height: 22),

                        Row(
                          children: [
                            const Expanded(
                              child: SectionHeader('Announcements'),
                            ),
                            if (isAdmin)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: FilledButton.icon(
                                  onPressed: _openNewAnnouncementSheet,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Create'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_announcements.isEmpty)
                          _emptyCard(
                            colors,
                            Icons.campaign_outlined,
                            isAdmin
                                ? 'No announcements yet — create one to keep everyone in the loop.'
                                : 'No announcements yet.',
                          )
                        else
                          for (final a in _announcements)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _AnnouncementCard(
                                announcement: a,
                                isAdmin: isAdmin,
                                reactingKey: _reactingKey,
                                onReact: (key) => _handleReaction(a, key),
                                onWhoReacted: () => _openReactionsViewer(a),
                              ),
                            ),
                        const SizedBox(height: 22),

                        const SectionHeader('Quick links'),
                        OptionGrid(
                          children: isAdmin
                              ? [
                                  OptionCard(
                                    icon: Icons.shield_outlined,
                                    title: 'Admin dashboard',
                                    subtitle: 'Residents & requests',
                                    onTap: () =>
                                        _go(const AdminDashboardScreen()),
                                  ),
                                  OptionCard(
                                    icon: Icons.people_alt_outlined,
                                    title: 'Roles',
                                    subtitle: 'Access & permissions',
                                    onTap: () => _go(const AdminRolesScreen()),
                                  ),
                                  OptionCard(
                                    icon: Icons.meeting_room_outlined,
                                    title: 'Rooms',
                                    subtitle: 'Allocation & occupancy',
                                    onTap: () => _go(const RoomsScreen()),
                                  ),
                                  OptionCard(
                                    icon: Icons.build_outlined,
                                    title: 'Equipment',
                                    subtitle: 'Buying & repairs',
                                    badge: _pendingEquipmentCount,
                                    onTap: () => _go(const EquipmentScreen()),
                                  ),
                                ]
                              : [
                                  OptionCard(
                                    icon: Icons.checklist_rounded,
                                    title: 'My duties',
                                    subtitle: 'Chores & roster',
                                    badge: _myDuties.length,
                                    onTap: () => _go(const DutiesScreen()),
                                  ),
                                  OptionCard(
                                    icon: Icons.build_outlined,
                                    title: 'Equipment',
                                    subtitle: 'Request or report',
                                    onTap: () => _go(const EquipmentScreen()),
                                  ),
                                  OptionCard(
                                    icon: Icons.ramen_dining_outlined,
                                    title: 'Meal polls',
                                    subtitle: 'Vote for meals',
                                    onTap: () => _go(const PollsScreen()),
                                  ),
                                  OptionCard(
                                    icon: Icons.menu_book_outlined,
                                    title: 'House rules',
                                    subtitle: 'Guidelines',
                                    onTap: () => _go(const HouseRulesScreen()),
                                  ),
                                ],
                        ),
                        const SizedBox(height: 14),
                        const WifiPromoCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _hero(
    ColorScheme colors,
    bool isDark,
    bool isAdmin,
    UnreadProvider unread,
  ) {
    final tiles = isAdmin
        ? [
            (
              Icons.build_circle_outlined,
              '${_openMaintenance.length}',
              'Open repairs',
              () => _go(const AdminDashboardScreen()),
            ),
            (
              Icons.shopping_cart_outlined,
              '$_pendingEquipmentCount',
              'Equipment',
              () => _go(const EquipmentScreen(initialTab: 'requests')),
            ),
            (
              Icons.chat_bubble_outline_rounded,
              '${unread.unreadConversations}',
              'Unread chats',
              () => shellTab.value = ShellTab.messages,
            ),
            (
              Icons.event_outlined,
              '${_events.length}',
              'Events',
              () => _go(const EventsScreen()),
            ),
          ]
        : [
            (
              Icons.chat_bubble_outline_rounded,
              '${unread.unreadConversations}',
              'Unread chats',
              () => shellTab.value = ShellTab.messages,
            ),
            (
              Icons.notifications_none_rounded,
              '${unread.unreadNotifications}',
              'Alerts',
              () => _go(const NotificationsScreen()),
            ),
            (
              Icons.checklist_rounded,
              '${_myDuties.length}',
              'Duties',
              () => _go(const DutiesScreen()),
            ),
            (
              Icons.event_outlined,
              '${_events.length}',
              'Events',
              () => _go(const EventsScreen()),
            ),
          ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ink, Color(0xFF2A160B), AppColors.primaryDeep],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMMM')
                      .format(DateTime.now())
                      .toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryBorder,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              _glassIcon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                isDark ? 'Light mode' : 'Dark mode',
                () => _toggleDarkMode(!isDark),
              ),
              const SizedBox(width: 8),
              _glassIcon(
                Icons.notifications_none_rounded,
                'Notifications',
                () => _go(const NotificationsScreen()),
                badge: unread.unreadNotifications,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$_greeting 👋',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isAdmin
                ? 'Here\'s what needs your attention today.'
                : 'Everything happening in your residence.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Material(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _savingAvailability
                      ? null
                      : () => _toggleAvailability(!_isAvailable),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _savingAvailability
                            ? const SizedBox(
                                width: 10,
                                height: 10,
                                child: AppLoader(color: Colors.white),
                              )
                            : Icon(
                                Icons.circle,
                                size: 9,
                                color: _isAvailable
                                    ? AppColors.success
                                    : AppColors.subtle,
                              ),
                        const SizedBox(width: 7),
                        Text(
                          _isAvailable ? 'Around the house' : 'Away',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 13,
                        color: AppColors.primaryBorder,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Admin',
                        style: TextStyle(
                          color: AppColors.primaryBorder,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: tiles[i].$4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 6,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              tiles[i].$1,
                              size: 17,
                              color: AppColors.primaryBorder,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tiles[i].$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              tiles[i].$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _glassIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    int badge = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 9 ? '9+' : '$badge'),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _attentionCard(ColorScheme colors) {
    final parts = [
      if (_openMaintenance.isNotEmpty)
        '${_openMaintenance.length} open repair${_openMaintenance.length == 1 ? '' : 's'}',
      if (_pendingEquipmentCount > 0)
        '$_pendingEquipmentCount equipment request${_pendingEquipmentCount == 1 ? '' : 's'}',
    ];
    return Material(
      color: AppColors.warning.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _go(const AdminDashboardScreen()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.priority_high_rounded, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Needs attention',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${parts.join(' · ')} awaiting action.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateBlock(ColorScheme colors, DateTime d, {bool strong = false}) =>
      Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: strong ? _accent : colors.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Text(
              DateFormat('MMM').format(d).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: strong ? Colors.white : _accent,
              ),
            ),
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: strong ? Colors.white : _accent,
              ),
            ),
          ],
        ),
      );

  Widget _nextDutyCard(ColorScheme colors, Duty d) {
    final now = DateTime.now();
    final isToday =
        d.assignedDate.year == now.year &&
        d.assignedDate.month == now.month &&
        d.assignedDate.day == now.day;
    return Material(
      color: isToday ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: isToday ? _accent : colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _go(const DutiesScreen()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _dateBlock(colors, d.assignedDate, strong: isToday),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isToday
                          ? 'Today'
                          : DateFormat('EEEE').format(d.assignedDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: isToday ? _accent : colors.onSurfaceVariant,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_myDuties.length > 1)
                Text(
                  '+${_myDuties.length - 1} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventsCard(ColorScheme colors) {
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _events.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 76, color: colors.outlineVariant),
            InkWell(
              onTap: () => _go(const EventsScreen()),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _dateBlock(colors, _events[i].startDate),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _events[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              DateFormat('EEE · HH:mm')
                                  .format(_events[i].startDate),
                              if (_events[i].location != null)
                                _events[i].location!,
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCard(ColorScheme colors, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, color: _accent, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool isAdmin;
  final String? reactingKey;
  final void Function(String reactionKey) onReact;
  final VoidCallback onWhoReacted;

  const _AnnouncementCard({
    required this.announcement,
    required this.isAdmin,
    required this.reactingKey,
    required this.onReact,
    required this.onWhoReacted,
  });

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const accent = AppColors.primary; // brand accent
    final bubbleBg = colors.surfaceContainerHighest;
    final titleColor = colors.onSurface;
    final bodyColor = colors.onSurface.withValues(alpha: 0.85);
    final metaColor = colors.onSurfaceVariant;
    final reactionBg = colors.surfaceContainerHigh;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar column — like WhatsApp sender icon
          Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent,
                child: Text(
                  initialsFor(announcement.creatorName ?? 'Admin'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          // Bubble column
          Expanded(
            child: Material(
              color: bubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sender name + time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          announcement.creatorName ?? 'Management',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        Text(
                          _relative(announcement.createdAt),
                          style: TextStyle(fontSize: 10, color: metaColor),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Title
                    Text(
                      announcement.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Message body
                    Text(
                      announcement.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: bodyColor,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Reactions strip
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _reactions.map((r) {
                        final isActive = announcement.userReaction == r.key;
                        final isBusy =
                            reactingKey ==
                            '${announcement.announcementId}-${r.key}';
                        return GestureDetector(
                          onTap: isBusy ? null : () => onReact(r.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isActive ? accent : reactionBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              r.emoji,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    // Admin: who reacted
                    if (isAdmin) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: onWhoReacted,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bar_chart_rounded,
                              size: 13,
                              color: accent,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'See who reacted',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// --- New announcement sheet ---
class _NewAnnouncementSheet extends StatefulWidget {
  const _NewAnnouncementSheet();

  @override
  State<_NewAnnouncementSheet> createState() => _NewAnnouncementSheetState();
}

class _NewAnnouncementSheetState extends State<_NewAnnouncementSheet> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Give the announcement a title');
      return;
    }
    if (_messageController.text.trim().isEmpty) {
      setState(() => _error = 'Write a message');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/announcements', {
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not post announcement');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),

      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.campaign_rounded,
                      color: _accent,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New announcement',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share an update with residents.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // Title field
              Text(
                'TITLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    _decoration(
                      colors,
                      hint: 'e.g. Water shut off Friday morning',
                    ).copyWith(
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 17,
                      ),
                    ),
              ),

              const SizedBox(height: 20),

              // Message field
              Text(
                'MESSAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                maxLines: 4,
                minLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    _decoration(
                      colors,
                      hint: 'Give residents the details...',
                    ).copyWith(
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      alignLabelWithHint: true,
                      contentPadding: const EdgeInsets.all(16),
                    ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: _red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: AppLoader(strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, size: 18),
                            SizedBox(width: 10),
                            Text(
                              'Post announcement',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(ColorScheme colors, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent),
      ),
    );
  }
}

/// --- Reactions viewer sheet ---
class _ReactionsViewerSheet extends StatefulWidget {
  final Announcement announcement;
  const _ReactionsViewerSheet({required this.announcement});

  @override
  State<_ReactionsViewerSheet> createState() => _ReactionsViewerSheetState();
}

class _ReactionsViewerSheetState extends State<_ReactionsViewerSheet> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;
  String? _error;
  String _activeTab = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get(
        '/announcements/${widget.announcement.announcementId}/reactions',
      );
      setState(() {
        _rows = (data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load reactions';
        _loading = false;
      });
    }
  }

  String _nameFor(Map<String, dynamic> r) {
    final full = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    if (r['username'] != null) return r['username'] as String;
    return 'User #${r['user_id']}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = _rows ?? [];
    final tabCounts = <String, int>{};
    for (final r in rows) {
      final key = r['reaction'] as String;
      tabCounts[key] = (tabCounts[key] ?? 0) + 1;
    }

    var visible = rows;
    if (_activeTab != 'all') {
      visible = visible.where((r) => r['reaction'] == _activeTab).toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      visible = visible
          .where((r) => _nameFor(r).toLowerCase().contains(q))
          .toList();
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reactions${!_loading && rows.isNotEmpty ? ' (${rows.length})' : ''}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          widget.announcement.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.onSurface),
                  ),
                ],
              ),
              if (!_loading && rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _tabChip(colors, 'All ${rows.length}', 'all'),
                      for (final entry in tabCounts.entries) ...[
                        const SizedBox(width: 6),
                        _tabChip(
                          colors,
                          '${_reactions.firstWhere((r) => r.key == entry.key, orElse: () => (emoji: entry.key, key: entry.key, label: entry.key)).emoji} ${entry.value}',
                          entry.key,
                        ),
                      ],
                    ],
                  ),
                ),
                if (rows.length > 8) ...[
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name…',
                      isDense: true,
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const AppLoadingView()
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _red),
                        ),
                      )
                    : rows.isEmpty
                    ? Center(
                        child: Text(
                          'No reactions yet',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      )
                    : visible.isEmpty
                    ? Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final r = visible[i];
                          final name = _nameFor(r);
                          final emoji = _reactions
                              .firstWhere(
                                (x) => x.key == r['reaction'],
                                orElse: () => (
                                  emoji: r['reaction'] as String,
                                  key: '',
                                  label: '',
                                ),
                              )
                              .emoji;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: _accent,
                                  child: Text(
                                    initialsFor(name),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: colors.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tabChip(ColorScheme colors, String label, String key) {
    final selected = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.onSurface : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? colors.surface : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
