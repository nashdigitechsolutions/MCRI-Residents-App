import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/duty.dart';
import '../models/duty_status.dart';
import '../models/resident.dart';
import '../models/roster_entry.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

const _red = Color(0xFFEF4444);
const _accent = Color(0xFF3355FF);
const _amber = Color(0xFFD97706);
const _green = Color(0xFF10B981);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        margin: const EdgeInsets.only(bottom: 24, left: 60, right: 60),
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

  bool get _hasDutyDueToday {
    final today = DateTime.now();
    return _myUpcoming.any(
      (d) =>
          d.assignedDate.year == today.year &&
          d.assignedDate.month == today.month &&
          d.assignedDate.day == today.day,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
                IconButton(
                  onPressed: _openAssignSheet,
                  icon: const Icon(Icons.add),
                  tooltip: 'Assign duty',
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_hasDutyDueToday) _buildTodayBanner(colors),
                  if (_hasDutyDueToday) const SizedBox(height: 14),

                  _sectionLabel(colors, Icons.checklist_outlined, 'My duties'),
                  const SizedBox(height: 10),
                  if (_myUpcoming.isEmpty)
                    _emptyCard(colors, 'No duties assigned to you')
                  else
                    for (final duty in _myUpcoming)
                      _MyDutyCard(
                        duty: duty,
                        busy: _busyDutyId == duty.dutyId,
                        onStart: () =>
                            _updateStatus(duty, DutyStatus.inProgress),
                        onComplete: () =>
                            _updateStatus(duty, DutyStatus.completed),
                      ),
                  if (_myDone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Completed (${_myDone.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionLabel(
                        colors,
                        Icons.calendar_today_outlined,
                        'Weekly duty roster',
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: [
                            _genderChip(colors, 'All', _GenderTab.all),
                            _genderChip(colors, 'Boys', _GenderTab.boys),
                            _genderChip(colors, 'Girls', _GenderTab.girls),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.15,
                        ),
                    itemCount: _days.length,
                    itemBuilder: (context, i) {
                      final d = _days[i];
                      final isToday = d.num == _todayDayOfWeek;
                      final people = _rosterForDay(d.num);
                      return _DayCard(
                        day: d.short,
                        dayName: d.name,
                        people: people,
                        isToday: isToday,
                        pulseController: _pulseController,
                        onTap: () => _openDaySheet(d.num, d.name),
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  _sectionLabel(
                    colors,
                    Icons.groups_outlined,
                    'Assigned duties',
                  ),
                  if (!_isAdmin) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Showing your own assignments only — the full list is visible to admins.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (_duties.isEmpty)
                    _emptyCard(colors, 'No duties assigned yet.')
                  else
                    for (final duty in _duties)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: _accent,
                              child: Text(
                                _displayNameFor(duty.assignedTo).isNotEmpty
                                    ? _displayNameFor(
                                        duty.assignedTo,
                                      )[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    duty.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  Text(
                                    '${_displayNameFor(duty.assignedTo)} · ${DateFormat.MMMd().format(duty.assignedDate)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _statusPill(duty.status),
                          ],
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(ColorScheme colors, IconData icon, String label) {
    return Row(
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
    );
  }

  Widget _emptyCard(ColorScheme colors, String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.checklist_outlined,
            size: 26,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _genderChip(ColorScheme colors, String label, _GenderTab tab) {
    final selected = _genderTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _genderTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _statusPill(DutyStatus status) {
    final map = {
      DutyStatus.pending: (label: 'Pending', color: Colors.grey),
      DutyStatus.inProgress: (label: 'In progress', color: _amber),
      DutyStatus.completed: (label: 'Completed', color: _green),
      DutyStatus.missed: (label: 'Missed', color: _red),
    };
    final meta = map[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: meta.color,
        ),
      ),
    );
  }

  Widget _buildTodayBanner(ColorScheme colors) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = 0.08 + (_pulseController.value * 0.08);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: glow),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You have a duty due today',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MyDutyCard extends StatelessWidget {
  final Duty duty;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  const _MyDutyCard({
    required this.duty,
    required this.busy,
    required this.onStart,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final overdue =
        duty.assignedDate.isBefore(
          DateTime(today.year, today.month, today.day),
        ) &&
        duty.status != DutyStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
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
                      duty.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (duty.description != null)
                      Text(
                        duty.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      'Due ${DateFormat('EEE, MMM d').format(duty.assignedDate)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                        color: overdue ? _red : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPillFor(duty.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (duty.status == DutyStatus.pending) ...[
                OutlinedButton(
                  onPressed: busy ? null : onStart,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.outlineVariant),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Start', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
              ],
              if (duty.status != DutyStatus.completed)
                ElevatedButton.icon(
                  onPressed: busy ? null : onComplete,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Done', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.onSurface,
                    foregroundColor: colors.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPillFor(DutyStatus status) {
    final map = {
      DutyStatus.pending: (label: 'Pending', color: Colors.grey),
      DutyStatus.inProgress: (label: 'In progress', color: _amber),
      DutyStatus.completed: (label: 'Completed', color: _green),
      DutyStatus.missed: (label: 'Missed', color: _red),
    };
    final meta = map[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: meta.color,
        ),
      ),
    );
  }
}

/// A roster day tile — pulses a "LIVE" badge if it's today's day.
class _DayCard extends StatelessWidget {
  final String day;
  final String dayName;
  final List<RosterEntry> people;
  final bool isToday;
  final AnimationController pulseController;
  final VoidCallback onTap;

  const _DayCard({
    required this.day,
    required this.dayName,
    required this.people,
    required this.isToday,
    required this.pulseController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isToday ? _accent.withValues(alpha: 0.06) : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isToday
                ? _accent.withValues(alpha: 0.35)
                : colors.outlineVariant,
            width: isToday ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  day.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isToday ? _accent : colors.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 6),
                  AnimatedBuilder(
                    animation: pulseController,
                    builder: (context, child) {
                      final scale = 0.85 + (pulseController.value * 0.3);
                      return Opacity(
                        opacity: 0.5 + (pulseController.value * 0.5),
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (people.isEmpty)
              Text(
                'No one assigned',
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              ...people
                  .take(3)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: _accent,
                            child: Text(
                              p.displayName.isNotEmpty
                                  ? p.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              p.displayName,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            if (people.length > 3)
              Text(
                '+${people.length - 3} more',
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "live popup" sheet — who's on duty for a given day.
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
