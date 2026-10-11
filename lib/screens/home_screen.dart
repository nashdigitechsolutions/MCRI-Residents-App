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
import '../utils/initials.dart';
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

const _accent = Color(0xFF3355FF);
const _red = Color(0xFFEF4444);
const _amber = Color(0xFFD97706);

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

class _HomeScreenState extends State<HomeScreen> {
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
  }

  String _cacheKey(int? userId) => 'mcri_profile_cache_${userId ?? 'anon'}';

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

  Future<void> _loadDashboard() async {
    final isAdmin = _isAdmin;
    final myId = context.read<AuthProvider>().user?.userId;
    setState(() => _loading = true);
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
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = context.watch<SettingsProvider>().prefs.theme == 'dark';
    final user = context.watch<AuthProvider>().user;
    final isAdmin = _isAdmin;
    final unreadCount = context.watch<UnreadProvider>().unreadNotifications;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // --- artistic gradient header ---
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      MediaQuery.of(context).padding.top + 16,
                      20,
                      24,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0A0A0A), Color(0xFF1A1A2E), _accent],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('EEEE, MMMM d')
                                        .format(DateTime.now())
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_greeting${user?.username != null ? ', ${user!.username}' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Admin dashboard',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                _headerIconButton(
                                  icon: isDark
                                      ? Icons.wb_sunny_outlined
                                      : Icons.dark_mode_outlined,
                                  active: isDark,
                                  onTap: () => _toggleDarkMode(!isDark),
                                ),
                                const SizedBox(width: 8),
                                _headerIconButton(
                                  icon: Icons.meeting_room_outlined,
                                  active: _isAvailable,
                                  disabled: _savingAvailability,
                                  onTap: () =>
                                      _toggleAvailability(!_isAvailable),
                                ),
                                const SizedBox(width: 8),
                                _notificationBellButton(unreadCount),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildStatStrip(isAdmin),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isAdmin && _openMaintenance.isNotEmpty) ...[
                          _buildAttentionBanner(colors),
                          const SizedBox(height: 20),
                        ],

                        if (_myDuties.isNotEmpty) ...[
                          _sectionHeader(
                            colors,
                            Icons.checklist_outlined,
                            'My duties',
                            onViewAll: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DutiesScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 76,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _myDuties.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final d = _myDuties[i];
                                return Container(
                                  width: 160,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: colors.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        d.title,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Due ${DateFormat.MMMd().format(d.assignedDate)}',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 22),
                        ],

                        _sectionHeader(
                          colors,
                          Icons.calendar_today_outlined,
                          'Upcoming events',
                          onViewAll: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const EventsScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_events.isEmpty)
                          _emptyCard(colors, 'Nothing scheduled right now.')
                        else
                          for (final e in _events)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          DateFormat.MMM()
                                              .format(e.startDate)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: _accent,
                                          ),
                                        ),
                                        Text(
                                          '${e.startDate.day}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: _accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: colors.onSurface,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (e.location != null)
                                          Text(
                                            e.location!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.onSurfaceVariant,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionHeader(
                              colors,
                              Icons.campaign_outlined,
                              'Latest announcements',
                            ),
                            if (isAdmin)
                              OutlinedButton.icon(
                                onPressed: _openNewAnnouncementSheet,
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text(
                                  'New',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: colors.outlineVariant,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_announcements.isEmpty)
                          _emptyCard(
                            colors,
                            isAdmin
                                ? 'No announcements yet.\nUse "New" above to post the first one.'
                                : 'No announcements yet.',
                          )
                        else
                          for (final a in _announcements)
                            _AnnouncementCard(
                              announcement: a,
                              isAdmin: isAdmin,
                              reactingKey: _reactingKey,
                              onReact: (key) => _handleReaction(a, key),
                              onWhoReacted: () => _openReactionsViewer(a),
                            ),

                        const SizedBox(height: 22),
                        _sectionHeader(
                          colors,
                          Icons.grid_view_rounded,
                          'Quick links',
                        ),
                        const SizedBox(height: 10),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.7,
                          children: isAdmin
                              ? [
                                  _quickLink(
                                    colors,
                                    Icons.shield_outlined,
                                    'Admin dashboard',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminDashboardScreen(),
                                      ),
                                    ),
                                  ),
                                  _quickLink(
                                    colors,
                                    Icons.people_outline,
                                    'Roles',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminRolesScreen(),
                                      ),
                                    ),
                                  ),
                                  _quickLink(
                                    colors,
                                    Icons.meeting_room_outlined,
                                    'Manage rooms',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RoomsScreen(),
                                      ),
                                    ),
                                  ),
                                  _quickLink(
                                    colors,
                                    Icons.checklist_outlined,
                                    'Manage polls',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const PollsScreen(),
                                      ),
                                    ),
                                  ),
                                ]
                              : [
                                  _quickLink(
                                    colors,
                                    Icons.checklist_outlined,
                                    'My duties',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const DutiesScreen(),
                                      ),
                                    ),
                                  ),
                                  _quickLink(
                                    colors,
                                    Icons.build_outlined,
                                    'Equipment',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const EquipmentScreen(),
                                      ),
                                    ),
                                  ),
                                  _quickLink(
                                    colors,
                                    Icons.ramen_dining_outlined,
                                    'Meal polls',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const PollsScreen(),
                                      ),
                                    ),
                                  ),
                                  _quickLink(
                                    colors,
                                    Icons.menu_book_outlined,
                                    'House rules',
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const HouseRulesScreen(),
                                      ),
                                    ),
                                  ),
                                ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    bool active = false,
    bool danger = false,
    bool disabled = false,
    required VoidCallback onTap,
  }) {
    final activeColor = danger ? _red : _accent;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Opacity(
          opacity: disabled ? 0.4 : 1,
          child: Icon(
            icon,
            size: 17,
            color: active ? activeColor : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _notificationBellButton(int unreadCount) {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 17,
              color: Colors.white70,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: _red,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF0A0A0A),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
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
    );
  }

  Widget _buildStatStrip(bool isAdmin) {
    final stats = isAdmin
        ? [
            (value: '${_openMaintenance.length}', label: 'Open repairs'),
            (value: '$_pendingEquipmentCount', label: 'Pending equip.'),
            (value: '${_events.length}', label: 'Events'),
            (value: '${_announcements.length}', label: 'Announce.'),
          ]
        : [
            (value: '${_myDuties.length}', label: 'My duties'),
            (value: '${_events.length}', label: 'Events'),
            (value: _isAvailable ? 'Yes' : 'No', label: 'Available'),
          ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    stats[i].value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats[i].label,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 9.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAttentionBanner(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 15, color: _amber),
              const SizedBox(width: 6),
              const Text(
                'Needs attention',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _amber,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminDashboardScreen(),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Go to Admin',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _accent,
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 12, color: _accent),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_openMaintenance.length} open maintenance request${_openMaintenance.length == 1 ? '' : 's'}${_pendingEquipmentCount > 0 ? ' and $_pendingEquipmentCount pending equipment request${_pendingEquipmentCount == 1 ? '' : 's'}' : ''} awaiting action.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    ColorScheme colors,
    IconData icon,
    String label, {
    VoidCallback? onViewAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
                Icon(Icons.arrow_forward, size: 12, color: _accent),
              ],
            ),
          ),
      ],
    );
  }

  Widget _emptyCard(ColorScheme colors, String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _quickLink(
    ColorScheme colors,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    const accent = Color(
      0xFF3355FF,
    ); // brand accent — stays fixed in both modes
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Text(
              'New announcement',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: _decoration(
                colors,
                hint: 'e.g. Water shut off Friday morning',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: _decoration(
                colors,
                hint: 'Give residents the details…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: _red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.surface,
                        ),
                      )
                    : Text(
                        'Post announcement',
                        style: TextStyle(
                          color: colors.surface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    ? const Center(child: CircularProgressIndicator())
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
