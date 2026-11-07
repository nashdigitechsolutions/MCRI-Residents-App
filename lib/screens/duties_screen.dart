import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/duty.dart';
import '../models/duty_status.dart';
import '../models/resident.dart';
import '../models/roster_entry.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/ui.dart';

const _red = AppColors.danger;
const _accent = AppColors.primary;
const _amber = AppColors.warning;
const _green = AppColors.success;
const _residentRoleId = 2;

const _days = [
  (num: 1, name: 'Monday', short: 'Mon'),
  (num: 2, name: 'Tuesday', short: 'Tue'),
  (num: 3, name: 'Wednesday', short: 'Wed'),
  (num: 4, name: 'Thursday', short: 'Thu'),
  (num: 5, name: 'Friday', short: 'Fri'),
  (num: 6, name: 'Saturday', short: 'Sat'),
  (num: 7, name: 'Sunday', short: 'Sun'),
];

enum _GenderTab { all, boys, girls }

class DutiesScreen extends StatefulWidget {
  const DutiesScreen({super.key});

  @override
  State<DutiesScreen> createState() => _DutiesScreenState();
}

class _DutiesScreenState extends State<DutiesScreen>
    with SingleTickerProviderStateMixin {
  List<Duty> _duties = [];
  List<Resident> _residents = [];
  List<Map<String, dynamic>> _directory = [];
  List<RosterEntry> _roster = [];
  _GenderTab _genderTab = _GenderTab.all;
  bool _loading = true;
  int? _busyDutyId;

  late final AnimationController _pulseController;

  bool get _isAdmin => context.read<AuthProvider>().user?.roleId == 1;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadAll();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Each source loads and fails independently — a broken roster route
  /// (e.g. not deployed yet) never blanks out duties, and vice versa.
  Future<void> _loadAll() async {
    if (!mounted) return;

    setState(() => _loading = true);

    // Read the admin status before any async operations.
    final isAdmin = _isAdmin;

    try {
      final data = await ApiService.get('/duties');

      if (!mounted) return;

      setState(
        () => _duties = (data as List)
            .map((j) => Duty.fromJson(j as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      if (!mounted) return;
      _notify('Could not load duties', isError: true);
    }

    if (!mounted) return;

    try {
      final data = await ApiService.get('/duty-roster');

      if (!mounted) return;

      setState(
        () => _roster = (data as List)
            .map((j) => RosterEntry.fromJson(j as Map<String, dynamic>))
            .toList(),
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      _notify(
        e.statusCode == 404
            ? "Duty roster route not found — check it's registered on the backend"
            : 'Could not load the duty roster',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      _notify('Could not load the duty roster', isError: true);
    }

    if (!mounted) return;

    if (isAdmin) {
      try {
        final data = await ApiService.get('/residents');

        if (!mounted) return;

        setState(
          () => _residents = (data as List)
              .map((j) => Resident.fromJson(j as Map<String, dynamic>))
              .toList(),
        );
      } catch (e) {
        if (!mounted) return;
        // Non-fatal — room column just shows blank.
      }

      if (!mounted) return;

      try {
        final data = await ApiService.get('/users');

        if (!mounted) return;

        setState(
          () => _directory = (data as List).cast<Map<String, dynamic>>(),
        );
      } catch (e) {
        if (!mounted) return;
        _notify('Could not load the user directory', isError: true);
      }
    }

    if (!mounted) return;

    setState(() => _loading = false);
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Map<String, dynamic>> get _residentOptions => _directory.where((u) {
    final roleId = u['role_id'] is String
        ? int.parse(u['role_id'] as String)
        : u['role_id'] as int?;
    return roleId == _residentRoleId;
  }).toList();

  String _displayNameFor(int userId) {
    final myId = context.read<AuthProvider>().user?.userId;
    if (userId == myId) return 'You';
    final fromDirectory = _directory
        .where(
          (d) =>
              (d['user_id'] is String
                  ? int.parse(d['user_id'])
                  : d['user_id']) ==
              userId,
        )
        .firstOrNull;
    if (fromDirectory != null) {
      final full =
          '${fromDirectory['first_name'] ?? ''} ${fromDirectory['last_name'] ?? ''}'
              .trim();
      return full.isNotEmpty
          ? full
          : (fromDirectory['username'] as String? ?? 'User $userId');
    }
    final fromResidents = _residents
        .where((r) => r.userId == userId)
        .firstOrNull;
    if (fromResidents != null) return fromResidents.displayName;
    return 'User $userId';
  }

  Future<void> _updateStatus(Duty duty, DutyStatus status) async {
    setState(() {
      _busyDutyId = duty.dutyId;
      _duties = _duties
          .map((d) => d.dutyId == duty.dutyId ? d.copyWith(status: status) : d)
          .toList();
    });
    try {
      await ApiService.patch('/duties/${duty.dutyId}', {
        'status': _statusToApi(status),
      });
    } catch (e) {
      _notify('Could not update duty', isError: true);
      _loadAll();
    } finally {
      setState(() => _busyDutyId = null);
    }
  }

  String _statusToApi(DutyStatus s) {
    switch (s) {
      case DutyStatus.pending:
        return 'pending';
      case DutyStatus.inProgress:
        return 'in_progress';
      case DutyStatus.completed:
        return 'completed';
      case DutyStatus.missed:
        return 'missed';
    }
  }

  Future<void> _removeFromRoster(RosterEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from roster?'),
        content: Text('Remove ${entry.displayName} from ${entry.dayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.delete('/duty-roster/${entry.rosterId}');
      setState(
        () => _roster = _roster
            .where((r) => r.rosterId != entry.rosterId)
            .toList(),
      );
      _notify('Removed from roster');
    } catch (e) {
      _notify('Could not remove', isError: true);
    }
  }

  List<Duty> get _myDuties {
    final myId = context.read<AuthProvider>().user?.userId;
    return _duties.where((d) => d.assignedTo == myId).toList();
  }

  List<Duty> get _myUpcoming =>
      _myDuties.where((d) => d.status != DutyStatus.completed).toList();
  List<Duty> get _myDone =>
      _myDuties.where((d) => d.status == DutyStatus.completed).toList();

  int get _todayDayOfWeek =>
      DateTime.now().weekday; // 1=Monday..7=Sunday, matches backend

  List<RosterEntry> get _filteredRoster {
    if (_genderTab == _GenderTab.all) return _roster;
    return _roster.where((r) {
      final g = (r.gender ?? '').trim().toLowerCase();
      return _genderTab == _GenderTab.boys
          ? g.startsWith('m')
          : g.startsWith('f');
    }).toList();
  }

  List<RosterEntry> _rosterForDay(int dayNum) =>
      _filteredRoster.where((r) => r.dayOfWeek == dayNum).toList();

  /// The "live popup" — shows exactly who's on duty for a given day, with a
  /// pulsing "LIVE" indicator in the sheet header when that day is today.
  void _openDaySheet(int dayNum, String dayName) {
    final isToday = dayNum == _todayDayOfWeek;
    final people = _rosterForDay(dayNum);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayRosterSheet(
        dayName: dayName,
        isToday: isToday,
        people: people,
        isAdmin: _isAdmin,
        pulseController: _pulseController,
        onRemove: _removeFromRoster,
      ),
    );
  }

  Future<void> _openAssignSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignDutySheet(residents: _residentOptions),
    );
    if (created == true) {
      _notify('Duty assigned');
      _loadAll();
    }
  }

  Future<void> _openAddRosterSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddToRosterSheet(residents: _residentOptions),
    );
    if (added == true) {
      _notify('Added to roster');
      _loadAll();
    }
  }

  // ───────────────────────────── redesign ─────────────────────────────

  int _selectedDay = DateTime.now().weekday;

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isOverdue(Duty d) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return d.status != DutyStatus.completed &&
        DateTime(
          d.assignedDate.year,
          d.assignedDate.month,
          d.assignedDate.day,
        ).isBefore(today);
  }

  static ({String label, Color color, IconData icon}) _meta(DutyStatus s) =>
      switch (s) {
        DutyStatus.pending => (
          label: 'To do',
          color: _amber,
          icon: Icons.radio_button_unchecked_rounded,
        ),
        DutyStatus.inProgress => (
          label: 'In progress',
          color: _accent,
          icon: Icons.timelapse_rounded,
        ),
        DutyStatus.completed => (
          label: 'Done',
          color: _green,
          icon: Icons.check_circle_rounded,
        ),
        DutyStatus.missed => (
          label: 'Missed',
          color: _red,
          icon: Icons.cancel_rounded,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final upcoming = _myUpcoming
      ..sort((a, b) => a.assignedDate.compareTo(b.assignedDate));
    final done = _myDone
      ..sort((a, b) => b.assignedDate.compareTo(a.assignedDate));
    final todayPeople = _roster
        .where((r) => r.dayOfWeek == _todayDayOfWeek)
        .toList();
    final myToday = upcoming.where((d) => _isToday(d.assignedDate)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duties'),
        actions: _isAdmin
            ? [
                IconButton(
                  onPressed: _openAddRosterSheet,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  tooltip: 'Add to roster',
                ),
              ]
            : null,
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openAssignSheet,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Assign duty'),
            )
          : null,
      body: _loading
          ? const AppLoadingView(message: 'Loading duties…')
          : AppRefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const PageHeading(
                    eyebrow: 'Residence',
                    title: 'Duties',
                    subtitle: 'Your chores and this week\'s roster',
                  ),
                  const SizedBox(height: 16),
                  _todayCard(colors, todayPeople, myToday),
                  const SizedBox(height: 14),
                  _statsRow(colors, upcoming, done),
                  const SizedBox(height: 22),

                  // ── My duties ─────────────────────────────────────
                  const SectionHeader('My duties'),
                  if (upcoming.isEmpty)
                    _emptyCard(
                      colors,
                      Icons.celebration_outlined,
                      done.isEmpty
                          ? 'No duties assigned to you'
                          : 'All caught up — nice work!',
                    )
                  else
                    for (final d in upcoming) _dutyCard(colors, d, mine: true),
                  if (done.isNotEmpty)
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(
                          'Completed (${done.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        children: [
                          for (final d in done.take(20))
                            _dutyCard(colors, d, mine: true),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),

                  // ── Weekly roster ─────────────────────────────────
                  SectionHeader(
                    'Weekly roster',
                    actionLabel: _isAdmin ? 'Add person' : null,
                    onAction: _isAdmin ? _openAddRosterSheet : null,
                  ),
                  _genderFilter(colors),
                  const SizedBox(height: 10),
                  _weekStrip(colors),
                  const SizedBox(height: 10),
                  _dayPeople(colors),

                  // ── Admin: everything assigned ────────────────────
                  if (_isAdmin) ...[
                    const SizedBox(height: 24),
                    SectionHeader('All assigned duties · ${_duties.length}'),
                    if (_duties.isEmpty)
                      _emptyCard(
                        colors,
                        Icons.assignment_outlined,
                        'Nothing assigned yet — tap "Assign duty".',
                      )
                    else
                      for (final status in [
                        DutyStatus.inProgress,
                        DutyStatus.pending,
                        DutyStatus.missed,
                        DutyStatus.completed,
                      ])
                        ..._adminGroup(colors, status),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _todayCard(
    ColorScheme colors,
    List<RosterEntry> people,
    List<Duty> myToday,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ink, Color(0xFF2A160B), AppColors.primaryDeep],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FadeTransition(
                opacity: Tween(begin: 0.35, end: 1.0).animate(_pulseController),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'TODAY · ${DateFormat('EEEE d MMM').format(DateTime.now()).toUpperCase()}',
                style: const TextStyle(
                  color: AppColors.primaryBorder,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            myToday.isNotEmpty
                ? 'You\'re on duty today'
                : people.isEmpty
                ? 'No one on the roster today'
                : '${people.length} on duty today',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (myToday.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              myToday.map((d) => d.title).join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          if (people.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in people.take(8))
                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            p.displayName.isEmpty
                                ? '?'
                                : p.displayName[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.displayName.split(' ').first,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (people.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${people.length - 8} more',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (myToday.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (myToday.first.status == DutyStatus.pending)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: _busyDutyId == null
                          ? () => _updateStatus(
                              myToday.first,
                              DutyStatus.inProgress,
                            )
                          : null,
                      child: const Text('Start'),
                    ),
                  ),
                if (myToday.first.status == DutyStatus.pending)
                  const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busyDutyId == null
                        ? () =>
                              _updateStatus(myToday.first, DutyStatus.completed)
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Mark done'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statsRow(ColorScheme colors, List<Duty> upcoming, List<Duty> done) {
    final inProgress = upcoming
        .where((d) => d.status == DutyStatus.inProgress)
        .length;
    final overdue = upcoming.where(_isOverdue).length;
    final tiles = [
      (upcoming.length - inProgress, 'To do', _amber),
      (inProgress, 'In progress', _accent),
      (done.length, 'Done', _green),
      if (overdue > 0) (overdue, 'Overdue', _red),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  Text(
                    '${tiles[i].$1}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: tiles[i].$3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tiles[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dutyCard(
    ColorScheme colors,
    Duty d, {
    required bool mine,
    bool showAssignee = false,
  }) {
    final m = _meta(d.status);
    final overdue = _isOverdue(d);
    final today = _isToday(d.assignedDate);
    final busy = _busyDutyId == d.dutyId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: today ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: overdue
              ? _red.withValues(alpha: 0.5)
              : (today ? _accent : colors.outlineVariant),
          width: today || overdue ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date block
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: today ? _accent : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('MMM').format(d.assignedDate).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: today ? Colors.white : colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${d.assignedDate.day}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: today ? Colors.white : colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if ((d.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        d.description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: m.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(m.icon, size: 11, color: m.color),
                              const SizedBox(width: 4),
                              Text(
                                m.label,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: m.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (overdue)
                          const Text(
                            'Overdue',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _red,
                            ),
                          ),
                        if (today && !overdue)
                          const Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _accent,
                            ),
                          ),
                        if (showAssignee)
                          Text(
                            '· ${_displayNameFor(d.assignedTo)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (mine && d.status != DutyStatus.completed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (d.status == DutyStatus.pending)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _updateStatus(d, DutyStatus.inProgress),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Start'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ),
                if (d.status == DutyStatus.pending) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _updateStatus(d, DutyStatus.completed),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Mark done'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _genderFilter(ColorScheme colors) {
    return Wrap(
      spacing: 8,
      children: [
        for (final (tab, label) in [
          (_GenderTab.all, 'Everyone'),
          (_GenderTab.boys, 'Boys'),
          (_GenderTab.girls, 'Girls'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: _genderTab == tab,
            onSelected: (_) => setState(() => _genderTab = tab),
          ),
      ],
    );
  }

  /// All seven days always fit across the screen (no scrolling), so today
  /// is never hidden off the edge.
  Widget _weekStrip(ColorScheme colors) {
    return Row(
      children: [
        for (var i = 0; i < _days.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: _dayChip(colors, _days[i])),
        ],
      ],
    );
  }

  Widget _dayChip(
    ColorScheme colors,
    ({int num, String name, String short}) d,
  ) {
    final selected = d.num == _selectedDay;
    final isToday = d.num == _todayDayOfWeek;
    final count = _rosterForDay(d.num).length;
    return Semantics(
      button: true,
      selected: selected,
      label: '${d.name}, $count on duty',
      child: GestureDetector(
        onTap: () => setState(() => _selectedDay = d.num),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 68,
          decoration: BoxDecoration(
            color: selected ? _accent : colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? _accent
                  : (isToday
                        ? _accent.withValues(alpha: 0.6)
                        : colors.outlineVariant),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.short,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : colors.onSurface,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isToday
                        ? (selected ? Colors.white : _accent)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayPeople(ColorScheme colors) {
    final day = _days.firstWhere((d) => d.num == _selectedDay);
    final people = _rosterForDay(day.num);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${day.name}${day.num == _todayDayOfWeek ? ' · today' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _openDaySheet(day.num, day.name),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                'No one rostered for ${day.name}.',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            )
          else
            for (final p in people)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    p.displayName.isEmpty
                        ? '?'
                        : p.displayName[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(
                  p.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: (p.gender ?? '').isEmpty ? null : Text(p.gender!),
                trailing: _isAdmin
                    ? IconButton(
                        tooltip: 'Remove from roster',
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          color: _red,
                          size: 20,
                        ),
                        onPressed: () => _removeFromRoster(p),
                      )
                    : null,
              ),
        ],
      ),
    );
  }

  List<Widget> _adminGroup(ColorScheme colors, DutyStatus status) {
    final list = _duties.where((d) => d.status == status).toList()
      ..sort((a, b) => a.assignedDate.compareTo(b.assignedDate));
    if (list.isEmpty) return const [];
    final m = _meta(status);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          '${m.label.toUpperCase()} · ${list.length}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: m.color,
          ),
        ),
      ),
      for (final d in list.take(status == DutyStatus.completed ? 10 : 50))
        _dutyCard(colors, d, mine: false, showAssignee: true),
    ];
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

class _DayRosterSheet extends StatelessWidget {
  final String dayName;
  final bool isToday;
  final List<RosterEntry> people;
  final bool isAdmin;
  final AnimationController pulseController;
  final void Function(RosterEntry) onRemove;

  const _DayRosterSheet({
    required this.dayName,
    required this.isToday,
    required this.people,
    required this.isAdmin,
    required this.pulseController,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
          Row(
            children: [
              Text(
                dayName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: pulseController,
                  builder: (context, child) => Opacity(
                    opacity: 0.6 + (pulseController.value * 0.4),
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: colors.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No one on the roster for this day.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final p in people)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: _accent,
                      child: Text(
                        p.displayName.isNotEmpty
                            ? p.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.displayName,
                        style: TextStyle(fontSize: 14, color: colors.onSurface),
                      ),
                    ),
                    if (isAdmin)
                      IconButton(
                        onPressed: () => onRemove(p),
                        icon: const Icon(Icons.close, size: 16, color: _red),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// --- Assign duty sheet ---
class _AssignDutySheet extends StatefulWidget {
  final List<Map<String, dynamic>> residents;
  const _AssignDutySheet({required this.residents});

  @override
  State<_AssignDutySheet> createState() => _AssignDutySheetState();
}

class _AssignDutySheetState extends State<_AssignDutySheet> {
  final Set<int> _selected = {};
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _assignedDate = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _name(Map<String, dynamic> u) {
    final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return full.isNotEmpty ? full : (u['username'] as String? ?? 'User');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _assignedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _assignedDate = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_selected.isEmpty) {
      setState(() => _error = 'Pick at least one resident');
      return;
    }
    if (_titleController.text.trim().length < 2) {
      setState(() => _error = 'Give the duty a title');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/duties', {
        'title': _titleController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
        'assigned_to_ids': _selected.toList(),
        'assigned_date': DateFormat('yyyy-MM-dd').format(_assignedDate),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not assign the duty');
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              'Assign a duty',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assign to (tap to select — more than one allowed)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.residents.isEmpty
                          ? [
                              Text(
                                'No residents found',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ]
                          : widget.residents.map((r) {
                              final id = r['user_id'] is String
                                  ? int.parse(r['user_id'])
                                  : r['user_id'] as int;
                              final selected = _selected.contains(id);
                              return GestureDetector(
                                onTap: () => setState(
                                  () => selected
                                      ? _selected.remove(id)
                                      : _selected.add(id),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _accent.withValues(alpha: 0.1)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: selected
                                          ? _accent.withValues(alpha: 0.4)
                                          : colors.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _name(r),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? _accent
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleController,
                      decoration: _decoration(
                        colors,
                        hint: 'e.g. Kitchen cleanup',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 2,
                      decoration: _decoration(
                        colors,
                        hint: 'Description (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Due ${DateFormat.yMMMd().format(_assignedDate)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: _red, fontSize: 13),
                      ),
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
                            borderRadius: BorderRadius.circular(
                              AppRadius.sm + 2,
                            ),
                          ),
                        ),
                        child: _submitting
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: AppLoader(
                                  strokeWidth: 2,
                                  color: colors.surface,
                                ),
                              )
                            : Text(
                                'Assign duty${_selected.length > 1 ? ' to ${_selected.length} people' : ''}',
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

/// --- Add to roster sheet ---
class _AddToRosterSheet extends StatefulWidget {
  final List<Map<String, dynamic>> residents;
  const _AddToRosterSheet({required this.residents});

  @override
  State<_AddToRosterSheet> createState() => _AddToRosterSheetState();
}

class _AddToRosterSheetState extends State<_AddToRosterSheet> {
  int? _selectedUserId;
  int _day = 1;
  bool _submitting = false;
  String? _error;

  String _name(Map<String, dynamic> u) {
    final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return full.isNotEmpty ? full : (u['username'] as String? ?? 'User');
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_selectedUserId == null) {
      setState(() => _error = 'Pick a resident');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/duty-roster', {
        'user_id': _selectedUserId,
        'day_of_week': _day,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not add to roster');
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              'Add to roster',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Resident',
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _selectedUserId,
              decoration: _decoration(colors),
              hint: Text(
                widget.residents.isEmpty
                    ? 'No residents found'
                    : 'Select a resident',
              ),
              items: widget.residents.map((r) {
                final id = r['user_id'] is String
                    ? int.parse(r['user_id'])
                    : r['user_id'] as int;
                return DropdownMenuItem(value: id, child: Text(_name(r)));
              }).toList(),
              onChanged: (v) => setState(() => _selectedUserId = v),
            ),
            const SizedBox(height: 12),
            Text(
              'Day',
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _day,
              decoration: _decoration(colors),
              items: _days
                  .map(
                    (d) => DropdownMenuItem(value: d.num, child: Text(d.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _day = v ?? 1),
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
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: AppLoader(strokeWidth: 2, color: colors.surface),
                      )
                    : Text(
                        'Add',
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
