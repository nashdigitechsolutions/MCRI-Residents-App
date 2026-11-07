import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mcri_residents_app/models/attendance_status.dart';
import 'package:provider/provider.dart';

import '../models/attendee.dart';
import '../models/event.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/google_calendar.dart';
import '../widgets/ui.dart';

const _red = AppColors.danger;
const _accent = AppColors.primary;

const _statusLabels = {
  'going': 'Going',
  'maybe': 'Maybe',
  'not_going': 'Not going',
  'invited': 'Invited',
};

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Event> _events = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/events');
      if (!mounted) return;
      setState(() {
        _events = (data as List)
            .map((j) => Event.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _notify('Could not load events', isError: true);
    }
  }

  void _notify(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Event> _eventsOn(DateTime day) =>
      _events.where((e) => _dateOnly(e.startDate) == _dateOnly(day)).toList();

  List<Event> get _upcoming {
    final now = DateTime.now();
    final list = _events.where((e) => e.endDate.isAfter(now)).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (_search.trim().isEmpty) return list;
    final q = _search.toLowerCase();
    return list
        .where(
          (e) =>
              e.title.toLowerCase().contains(q) ||
              (e.location ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  bool _canManage(Event e) => context.read<AuthProvider>().user?.roleId == 1;

  Future<void> _rsvp(Event event, String status) async {
    setState(() {
      _events = _events
          .map((e) => e.eventId == event.eventId ? _withStatus(e, status) : e)
          .toList();
    });
    try {
      await ApiService.post('/events/${event.eventId}/attendees', {
        'attendance_status': status,
      });
    } catch (e) {
      _notify('Could not save your response', isError: true);
      _loadEvents();
    }
  }

  Event _withStatus(Event e, String status) {
    return Event(
      eventId: e.eventId,
      title: e.title,
      description: e.description,
      location: e.location,
      startDate: e.startDate,
      endDate: e.endDate,
      myAttendanceStatus: AttendanceStatusJson.fromJson(status),
    );
  }

  Future<void> _deleteEvent(Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove event?'),
        content: Text(
          'Remove "${event.title}" from the calendar? This can\'t be undone.',
        ),
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
      await ApiService.delete('/events/${event.eventId}');
      setState(
        () =>
            _events = _events.where((e) => e.eventId != event.eventId).toList(),
      );
      _notify('Event removed');
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('Could not remove event', isError: true);
    }
  }

  void _openDayAgenda(DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayAgendaSheet(
        day: day,
        events: _eventsOn(day),
        onAdd: () {
          Navigator.of(context).pop();
          _openNewEventSheet(defaultDate: day);
        },
        onOpenEvent: (e) {
          Navigator.of(context).pop();
          _openEventDetail(e);
        },
        onLongPressEvent: (e) {
          Navigator.of(context).pop();
          _openActionSheet(e);
        },
      ),
    );
  }

  void _openEventDetail(Event event) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventDetailSheet(
        event: event,
        canManage: _canManage(event),
        onRsvp: (status) => _rsvp(event, status),
        onShowAttendees: () {
          Navigator.of(context).pop();
          _openAttendees(event);
        },
      ),
    );
  }

  void _openAttendees(Event event) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttendeesSheet(event: event),
    );
  }

  void _openActionSheet(Event event) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventActionSheet(
        event: event,
        canManage: _canManage(event),
        onView: () {
          Navigator.of(context).pop();
          _openEventDetail(event);
        },
        onDuplicate: () {
          Navigator.of(context).pop();
          _openNewEventSheet(
            defaultDate: event.startDate,
            duplicateFrom: event,
          );
        },
        onDelete: () {
          Navigator.of(context).pop();
          _deleteEvent(event);
        },
        onGoogleCalendar: () async {
          Navigator.of(context).pop();
          await addToGoogleCalendar(
            title: event.title,
            start: event.startDate,
            end: event.endDate,
            location: event.location,
            description: event.description,
          );
        },
      ),
    );
  }

  Future<void> _openNewEventSheet({
    required DateTime defaultDate,
    Event? duplicateFrom,
  }) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewEventSheet(
        defaultDate: defaultDate,
        duplicateFrom: duplicateFrom,
      ),
    );
    if (created == true) {
      _notify(duplicateFrom != null ? 'Event duplicated' : 'Event created');
      _loadEvents();
    }
  }

  // ── View state for the redesigned screen ──
  String _filter = 'upcoming'; // upcoming | going | past
  bool _calendar = false;

  List<Event> get _past {
    final now = DateTime.now();
    final q = _search.toLowerCase();
    return _events
        .where((e) => !e.endDate.isAfter(now))
        .where(
          (e) =>
              q.isEmpty ||
              e.title.toLowerCase().contains(q) ||
              (e.location ?? '').toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
  }

  List<Event> get _visible => switch (_filter) {
    'going' =>
      _upcoming
          .where((e) => e.myAttendanceStatus == AttendanceStatus.going)
          .toList(),
    'past' => _past,
    _ => _upcoming,
  };

  String _countdown(Event e) {
    final now = DateTime.now();
    if (!e.startDate.isAfter(now)) return 'Happening now';
    final days = _dateOnly(e.startDate).difference(_dateOnly(now)).inDays;
    final time = DateFormat.jm().format(e.startDate);
    if (days == 0) {
      final mins = e.startDate.difference(now).inMinutes;
      return mins < 60 ? 'Starts in $mins min' : 'Today · $time';
    }
    if (days == 1) return 'Tomorrow · $time';
    if (days < 7) return '${DateFormat.EEEE().format(e.startDate)} · $time';
    return 'In $days days · ${DateFormat.MMMd().format(e.startDate)}';
  }

  /// Splits a list into labelled groups: Today, This week, Later (or by month for past).
  List<(String, List<Event>)> _grouped(List<Event> list) {
    final today = _dateOnly(DateTime.now());
    final groups = <String, List<Event>>{};
    for (final e in list) {
      final d = _dateOnly(e.startDate);
      final diff = d.difference(today).inDays;
      final label = _filter == 'past'
          ? DateFormat.yMMMM().format(e.startDate)
          : diff <= 0
          ? 'Today'
          : diff < 7
          ? 'This week'
          : diff < 31
          ? 'This month'
          : 'Later';
      (groups[label] ??= []).add(e);
    }
    return groups.entries.map((g) => (g.key, g.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final upcoming = _upcoming;
    final next = _search.isEmpty && upcoming.isNotEmpty ? upcoming.first : null;
    final going = _events
        .where(
          (e) =>
              e.endDate.isAfter(DateTime.now()) &&
              e.myAttendanceStatus == AttendanceStatus.going,
        )
        .length;
    final list = _visible
        .where((e) => _filter != 'upcoming' || e != next)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          IconButton(
            tooltip: _calendar ? 'List view' : 'Calendar view',
            onPressed: () => setState(() => _calendar = !_calendar),
            icon: Icon(
              _calendar
                  ? Icons.view_agenda_outlined
                  : Icons.calendar_month_outlined,
            ),
          ),
          IconButton(
            tooltip: 'New event',
            onPressed: () => _openNewEventSheet(defaultDate: DateTime.now()),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingView(message: 'Loading events…')
          : AppRefreshIndicator(
              onRefresh: () => _loadEvents(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  PageHeading(
                    eyebrow: 'Community',
                    title: 'What\'s on',
                    subtitle: upcoming.isEmpty
                        ? 'Nothing planned yet'
                        : '${upcoming.length} upcoming · you\'re going to $going',
                  ),
                  const SizedBox(height: 16),
                  if (_calendar) ...[
                    _monthHeader(colors),
                    const SizedBox(height: 10),
                    _MonthGrid(
                      month: _month,
                      eventsOn: _eventsOn,
                      onSelectDay: _openDayAgenda,
                      onLongPressEvent: _openActionSheet,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap a day to see its events · long-press an event for options',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    if (next != null) ...[
                      _nextUpCard(next),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Search events or places…',
                        prefixIcon: Icon(
                          Icons.search,
                          size: 19,
                          color: colors.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: colors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: const BorderSide(color: _accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (key, label) in [
                          ('upcoming', 'Upcoming'),
                          ('going', 'I\'m going'),
                          ('past', 'Past'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _filter == key,
                            onSelected: (_) => setState(() => _filter = key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty)
                      EmptyState(
                        icon: _filter == 'going'
                            ? Icons.event_available_outlined
                            : Icons.event_busy_outlined,
                        title: _search.isNotEmpty
                            ? 'No matching events'
                            : switch (_filter) {
                                'going' => 'No RSVPs yet',
                                'past' => 'No past events',
                                _ =>
                                  next != null
                                      ? 'That\'s everything for now'
                                      : 'No upcoming events',
                              },
                        message: _filter == 'going'
                            ? 'Tap "Going" on an event and it shows up here.'
                            : 'Tap + to plan something for the house.',
                      )
                    else
                      for (final (label, events) in _grouped(list)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                          child: Text(
                            label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final e in events)
                          Opacity(
                            opacity: _filter == 'past' ? 0.7 : 1,
                            child: _UpcomingRow(
                              event: e,
                              onTap: () => _openEventDetail(e),
                              onMore: () => _openActionSheet(e),
                            ),
                          ),
                      ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _monthHeader(ColorScheme colors) {
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              DateFormat.yMMMM().format(_month),
              key: ValueKey(_month),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Previous month',
          onPressed: () =>
              setState(() => _month = DateTime(_month.year, _month.month - 1)),
          icon: Icon(Icons.chevron_left, color: colors.onSurfaceVariant),
        ),
        TextButton(
          onPressed: () => setState(
            () => _month = DateTime(DateTime.now().year, DateTime.now().month),
          ),
          child: const Text('Today'),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () =>
              setState(() => _month = DateTime(_month.year, _month.month + 1)),
          icon: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Featured card for the very next event, with a countdown and one-tap RSVP.
  Widget _nextUpCard(Event e) {
    final going = e.myAttendanceStatus == AttendanceStatus.going;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.ink, Color(0xFF2A160B), AppColors.primaryDeep],
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => _openEventDetail(e),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        _countdown(e).toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primaryBorder,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'NEXT UP',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        children: [
                          Text(
                            DateFormat.MMM().format(e.startDate).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            '${e.startDate.day}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _heroMeta(
                            Icons.schedule_rounded,
                            '${DateFormat.jm().format(e.startDate)} – ${DateFormat.jm().format(e.endDate)}',
                          ),
                          if ((e.location ?? '').isNotEmpty)
                            _heroMeta(Icons.place_outlined, e.location!),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: going ? null : () => _rsvp(e, 'going'),
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.14,
                          ),
                          disabledForegroundColor: Colors.white,
                        ),
                        icon: Icon(
                          going
                              ? Icons.check_circle_rounded
                              : Icons.event_available_rounded,
                          size: 18,
                        ),
                        label: Text(going ? 'You\'re going' : 'I\'m going'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => _openEventDetail(e),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text('Details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroMeta(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Colors.white60),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

/// --- Month grid ---
class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final List<Event> Function(DateTime) eventsOn;
  final void Function(DateTime) onSelectDay;
  final void Function(Event) onLongPressEvent;

  const _MonthGrid({
    required this.month,
    required this.eventsOn,
    required this.onSelectDay,
    required this.onLongPressEvent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    // Monday-first grid: firstOfMonth.weekday is 1=Mon..7=Sun already.
    final gridStart = firstOfMonth.subtract(
      Duration(days: firstOfMonth.weekday - 1),
    );
    final days = List.generate(42, (i) => gridStart.add(Duration(days: i)));
    final today = _dateOnly(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: colors.surfaceContainerHighest,
            child: Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map(
                    (d) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.85,
            ),
            itemCount: 42,
            itemBuilder: (context, i) {
              final day = days[i];
              final inMonth = day.month == month.month;
              final isToday = _dateOnly(day) == today;
              final dayEvents = eventsOn(day);

              return InkWell(
                onTap: () => onSelectDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // AnimatedContainer: a low-level animation primitive —
                      // change any of its properties (here, color) and Flutter
                      // interpolates smoothly between old and new automatically.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 22,
                        width: 22,
                        decoration: BoxDecoration(
                          color: isToday ? _accent : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isToday
                                ? Colors.white
                                : (inMonth
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant.withValues(
                                          alpha: 0.4,
                                        )),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (dayEvents.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: List.generate(
                              dayEvents.length > 3 ? 3 : dayEvents.length,
                              (_) => Container(
                                margin: const EdgeInsets.only(right: 2),
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: _accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// --- Upcoming list row ---
class _UpcomingRow extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _UpcomingRow({
    required this.event,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = event.myAttendanceStatus?.name;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat.MMM().format(event.startDate).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                    Text(
                      '${event.startDate.day}',
                      style: const TextStyle(
                        fontSize: 15,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${DateFormat.jm().format(event.startDate)}${event.location != null ? ' · ${event.location}' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (status != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabels[_enumToKey(event.myAttendanceStatus!)] ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                onPressed: onMore,
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _enumToKey(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.going:
      return 'going';
    case AttendanceStatus.maybe:
      return 'maybe';
    case AttendanceStatus.notGoing:
      return 'not_going';
    case AttendanceStatus.invited:
      return 'invited';
  }
}

/// --- Day agenda sheet ---
class _DayAgendaSheet extends StatelessWidget {
  final DateTime day;
  final List<Event> events;
  final VoidCallback onAdd;
  final void Function(Event) onOpenEvent;
  final void Function(Event) onLongPressEvent;

  const _DayAgendaSheet({
    required this.day,
    required this.events,
    required this.onAdd,
    required this.onOpenEvent,
    required this.onLongPressEvent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
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
              DateFormat('EEEE, MMMM d').format(day),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: events.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          'Nothing scheduled this day.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: events.length,
                      itemBuilder: (context, i) {
                        final e = events[i];
                        return InkWell(
                          onTap: () => onOpenEvent(e),
                          onLongPress: () => onLongPressEvent(e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.title,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        '${DateFormat.jm().format(e.startDate)}${e.location != null ? ' · ${e.location}' : ''}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add event on this day'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.outlineVariant),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// --- Event detail sheet (view + RSVP) ---
class _EventDetailSheet extends StatelessWidget {
  final Event event;
  final bool canManage;
  final void Function(String) onRsvp;
  final VoidCallback onShowAttendees;

  const _EventDetailSheet({
    required this.event,
    required this.canManage,
    required this.onRsvp,
    required this.onShowAttendees,
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
              Expanded(
                child: Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: colors.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${DateFormat('EEE, MMM d · h:mm a').format(event.startDate)} – ${DateFormat.jm().format(event.endDate)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (event.location != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  event.location!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              event.description!,
              style: TextStyle(
                fontSize: 13.5,
                color: colors.onSurface,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Your response',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in ['going', 'maybe', 'not_going']) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _RsvpButton(
                      label: _statusLabels[s]!,
                      active:
                          _enumToKey(
                            event.myAttendanceStatus ??
                                AttendanceStatus.invited,
                          ) ==
                          s,
                      onTap: () => onRsvp(s),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onShowAttendees,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 16, color: _accent),
                const SizedBox(width: 6),
                Text(
                  canManage ? "See who's responded" : 'See responses',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _accent,
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

class _RsvpButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RsvpButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? _accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(color: active ? _accent : colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? _accent : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// --- Attendees sheet ---
class _AttendeesSheet extends StatefulWidget {
  final Event event;
  const _AttendeesSheet({required this.event});

  @override
  State<_AttendeesSheet> createState() => _AttendeesSheetState();
}

class _AttendeesSheetState extends State<_AttendeesSheet> {
  List<Attendee>? _attendees;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get(
        '/events/${widget.event.eventId}/attendees',
      );
      setState(() {
        _attendees = (data as List)
            .map((j) => Attendee.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _attendees = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final attendees = _attendees ?? [];
    final byStatus = <String, List<Attendee>>{};
    for (final a in attendees) {
      byStatus.putIfAbsent(a.attendanceStatus, () => []).add(a);
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
              Text(
                'Responses',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              Text(
                widget.event.title,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const AppLoadingView()
                    : attendees.isEmpty
                    ? Center(
                        child: Text(
                          'No responses yet',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        children: [
                          for (final key in [
                            'going',
                            'maybe',
                            'not_going',
                            'invited',
                          ])
                            if (byStatus[key]?.isNotEmpty == true) ...[
                              Text(
                                '${_statusLabels[key]} (${byStatus[key]!.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final a in byStatus[key]!)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: _accent.withValues(
                                          alpha: 0.12,
                                        ),
                                        child: Text(
                                          a.displayName.isNotEmpty
                                              ? a.displayName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        a.displayName,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 14),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// --- Action sheet (long-press) ---
class _EventActionSheet extends StatelessWidget {
  final Event event;
  final bool canManage;
  final VoidCallback onView;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onGoogleCalendar;

  const _EventActionSheet({
    required this.event,
    required this.canManage,
    required this.onView,
    required this.onDuplicate,
    required this.onDelete,
    required this.onGoogleCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('EEE, MMM d · h:mm a').format(event.startDate),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: colors.onSurfaceVariant,
                ),
                title: const Text('View details'),
                onTap: onView,
              ),
              ListTile(
                leading: Icon(
                  Icons.event_available_outlined,
                  color: colors.onSurfaceVariant,
                ),
                title: const Text('Add to Google Calendar'),
                onTap: onGoogleCalendar,
              ),
              if (canManage) ...[
                ListTile(
                  leading: Icon(
                    Icons.copy_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                  title: const Text('Duplicate'),
                  onTap: onDuplicate,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: _red),
                  title: const Text(
                    'Remove from calendar',
                    style: TextStyle(color: _red),
                  ),
                  onTap: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// --- New / duplicate event sheet ---
class _NewEventSheet extends StatefulWidget {
  final DateTime defaultDate;
  final Event? duplicateFrom;

  const _NewEventSheet({required this.defaultDate, this.duplicateFrom});

  @override
  State<_NewEventSheet> createState() => _NewEventSheetState();
}

class _NewEventSheetState extends State<_NewEventSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;
  late DateTime _start;
  late DateTime _end;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final dup = widget.duplicateFrom;
    _titleController = TextEditingController(
      text: dup != null ? '${dup.title} (copy)' : '',
    );
    _locationController = TextEditingController(text: dup?.location ?? '');
    _descriptionController = TextEditingController(
      text: dup?.description ?? '',
    );
    _start = dup?.startDate ?? widget.defaultDate;
    _end = dup?.endDate ?? widget.defaultDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final current = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => isStart ? _start = picked : _end = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Give the event a title');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/events', {
        'title': _titleController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
        if (_locationController.text.trim().isNotEmpty)
          'location': _locationController.text.trim(),
        'start_date': _start.toUtc().toIso8601String(),
        'end_date': _end.toUtc().toIso8601String(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not create event');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d, h:mm a');

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
              widget.duplicateFrom != null ? 'Duplicate event' : 'New event',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: _decoration(
                        colors,
                        hint: 'Event title, e.g. House BBQ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationController,
                      decoration: _decoration(
                        colors,
                        hint: 'Location (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pick(true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                fmt.format(_start),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pick(false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                fmt.format(_end),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: _decoration(
                        colors,
                        hint: 'Details (optional)',
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
                                widget.duplicateFrom != null
                                    ? 'Create copy'
                                    : 'Create event',
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
