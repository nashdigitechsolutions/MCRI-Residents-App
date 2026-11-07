// ignore_for_file: unnecessary_underscores

import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/weekly_menu_entry.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/ui.dart';
import '../utils/whatsapp_share.dart';

const List<String> _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _todayName() {
  return _days[DateTime.now().weekday - 1];
}

WeeklyMenuEntry _emptyEntry(String day) {
  return WeeklyMenuEntry(
    menuId: 0,
    dayOfWeek: day,
    breakfast: '',
    lunch: '',
    dinner: '',
  );
}

List<WeeklyMenuEntry> _ordered(List<WeeklyMenuEntry> menu) {
  final byDay = {for (final e in menu) e.dayOfWeek: e};
  return _days.map((day) => byDay[day] ?? _emptyEntry(day)).toList();
}

class WeeklyMenuScreen extends StatefulWidget {
  const WeeklyMenuScreen({super.key});

  @override
  State<WeeklyMenuScreen> createState() => _WeeklyMenuScreenState();
}

class _WeeklyMenuScreenState extends State<WeeklyMenuScreen> {
  List<WeeklyMenuEntry> _menu = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchMenu();
  }

  Future<void> _fetchMenu({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/weekly-menu');
      final list = (data as List)
          .map((json) => WeeklyMenuEntry.fromJson(json as Map<String, dynamic>))
          .toList();
      setState(() {
        _menu = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _showSnack('Could not load the weekly menu', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? AppColors.dangerDark
            : null, // null = theme default
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openEditSheet() async {
    final ordered = _ordered(_menu);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditMenuSheet(currentMenu: ordered),
    );

    if (saved == true) {
      _showSnack('Weekly menu updated');
      _fetchMenu(showLoading: false);
    }
  }

  String _selectedDay = _todayName();
  bool _weekGrid = false;

  bool get _isAdmin => context.read<AuthProvider>().isAdmin;

  /// Which meal is "up next" for the time of day; late evening rolls over
  /// to tomorrow's breakfast.
  ({String day, String meal, String dish}) _upNext(List<WeeklyMenuEntry> week) {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    var dayIndex = now.weekday - 1;
    String meal;
    if (minutes < 10 * 60 + 30) {
      meal = 'Breakfast';
    } else if (minutes < 15 * 60) {
      meal = 'Lunch';
    } else if (minutes < 21 * 60) {
      meal = 'Dinner';
    } else {
      meal = 'Breakfast';
      dayIndex = (dayIndex + 1) % 7;
    }
    final e = week[dayIndex];
    final dish = switch (meal) {
      'Breakfast' => e.breakfast,
      'Lunch' => e.lunch,
      _ => e.dinner,
    };
    return (day: _days[dayIndex], meal: meal, dish: dish);
  }

  String _shareText(WeeklyMenuEntry e) {
    String line(String emoji, String label, String v) =>
        '$emoji *$label:* ${v.isEmpty ? '—' : v}';
    return [
      '🍽️ *MCRI menu — ${e.dayOfWeek}*',
      line('🍳', 'Breakfast', e.breakfast),
      line('🥗', 'Lunch', e.lunch),
      line('🍲', 'Dinner', e.dinner),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final week = _ordered(_menu);
    final hasAny = _menu.isNotEmpty;
    final selected = week.firstWhere((e) => e.dayOfWeek == _selectedDay);
    final next = _upNext(week);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly menu'),
        actions: [
          IconButton(
            tooltip: _weekGrid ? 'Day view' : 'Week at a glance',
            icon: Icon(
              _weekGrid
                  ? Icons.view_day_outlined
                  : Icons.calendar_view_week_rounded,
            ),
            onPressed: () => setState(() => _weekGrid = !_weekGrid),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openEditSheet,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Edit week'),
            )
          : null,
      body: _loading
          ? const AppLoadingView(message: 'Loading the menu…')
          : AppRefreshIndicator(
              onRefresh: () => _fetchMenu(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const PageHeading(
                    eyebrow: 'Dining',
                    title: 'What\'s cooking',
                    subtitle: 'This week\'s breakfast, lunch and dinner',
                  ),
                  const SizedBox(height: 16),
                  if (!hasAny)
                    EmptyState(
                      icon: Icons.restaurant_menu_rounded,
                      title: 'No menu yet',
                      message: _isAdmin
                          ? 'Tap "Edit week" to plan the meals.'
                          : 'Check back once the menu is posted.',
                    )
                  else ...[
                    _upNextCard(next),
                    const SizedBox(height: 18),
                    if (_weekGrid)
                      _weekTable(colors, week)
                    else ...[
                      _dayStrip(colors, week),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDay == _todayName()
                                  ? '$_selectedDay · today'
                                  : _selectedDay,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                shareToWhatsApp(_shareText(selected)),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final (icon, label, time, dish) in [
                        (
                          Icons.free_breakfast_outlined,
                          'Breakfast',
                          'Morning',
                          selected.breakfast,
                        ),
                        (
                          Icons.lunch_dining_outlined,
                          'Lunch',
                          'Midday',
                          selected.lunch,
                        ),
                        (
                          Icons.dinner_dining_outlined,
                          'Dinner',
                          'Evening',
                          selected.dinner,
                        ),
                      ])
                        _mealCard(
                          colors,
                          icon,
                          label,
                          time,
                          dish,
                          highlight:
                              _selectedDay == next.day && label == next.meal,
                        ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _upNextCard(({String day, String meal, String dish}) next) {
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
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              switch (next.meal) {
                'Breakfast' => Icons.free_breakfast_rounded,
                'Lunch' => Icons.lunch_dining_rounded,
                _ => Icons.dinner_dining_rounded,
              },
              color: AppColors.primaryBorder,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UP NEXT · ${next.meal.toUpperCase()}${next.day == _todayName() ? '' : ' · ${next.day.toUpperCase()}'}',
                  style: const TextStyle(
                    color: AppColors.primaryBorder,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  next.dish.isEmpty ? 'Not on the menu yet' : next.dish,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayStrip(ColorScheme colors, List<WeeklyMenuEntry> week) {
    return Row(
      children: [
        for (var i = 0; i < _days.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Builder(
              builder: (_) {
                final day = _days[i];
                final selected = day == _selectedDay;
                final today = day == _todayName();
                final e = week[i];
                final planned = [
                  e.breakfast,
                  e.lunch,
                  e.dinner,
                ].where((s) => s.isNotEmpty).length;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '$day, $planned of 3 meals planned',
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 64,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : colors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : (today
                                    ? AppColors.primary.withValues(alpha: 0.6)
                                    : colors.outlineVariant),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              day.substring(0, 3),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? Colors.white
                                    : colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var m = 0; m < 3; m++)
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1.5,
                                    ),
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: m < planned
                                          ? (selected
                                                ? Colors.white
                                                : AppColors.primary)
                                          : (selected
                                                ? Colors.white38
                                                : colors.outlineVariant),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _mealCard(
    ColorScheme colors,
    IconData icon,
    String label,
    String time,
    String dish, {
    bool highlight = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: highlight ? AppColors.primary : colors.outlineVariant,
          width: highlight ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: AppColors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· $time',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (highlight) ...[
                      const Spacer(),
                      const Text(
                        'UP NEXT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dish.isEmpty ? 'Not planned yet' : dish,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: dish.isEmpty
                        ? FontWeight.w400
                        : FontWeight.w700,
                    fontStyle: dish.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: dish.isEmpty
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Whole week in one glance (rows = days, three meals each).
  Widget _weekTable(ColorScheme colors, List<WeeklyMenuEntry> week) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < week.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.outlineVariant),
            InkWell(
              onTap: () => setState(() {
                _selectedDay = week[i].dayOfWeek;
                _weekGrid = false;
              }),
              child: Container(
                color: week[i].dayOfWeek == _todayName()
                    ? colors.primaryContainer
                    : null,
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        week[i].dayOfWeek.substring(0, 3),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: week[i].dayOfWeek == _todayName()
                              ? AppColors.primary
                              : colors.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (icon, dish) in [
                            (Icons.free_breakfast_outlined, week[i].breakfast),
                            (Icons.lunch_dining_outlined, week[i].lunch),
                            (Icons.dinner_dining_outlined, week[i].dinner),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  Icon(
                                    icon,
                                    size: 14,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      dish.isEmpty ? '—' : dish,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
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
}

class _EditMenuSheet extends StatefulWidget {
  final List<WeeklyMenuEntry> currentMenu;

  const _EditMenuSheet({required this.currentMenu});

  @override
  State<_EditMenuSheet> createState() => _EditMenuSheetState();
}

class _EditMenuSheetState extends State<_EditMenuSheet> {
  late final Map<String, TextEditingController> _lunchControllers;
  late final Map<String, TextEditingController> _dinnerControllers;
  late String _activeDay;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lunchControllers = {
      for (final e in widget.currentMenu)
        e.dayOfWeek: TextEditingController(text: e.lunch),
    };
    _dinnerControllers = {
      for (final e in widget.currentMenu)
        e.dayOfWeek: TextEditingController(text: e.dinner),
    };
    _activeDay = _todayName();
  }

  @override
  void dispose() {
    for (final c in _lunchControllers.values) {
      c.dispose();
    }
    for (final c in _dinnerControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isDayComplete(String day) {
    return _lunchControllers[day]!.text.trim().isNotEmpty &&
        _dinnerControllers[day]!.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    for (final day in _days) {
      if (!_isDayComplete(day)) {
        setState(() {
          _error = 'Lunch and dinner are required for $day';
          _activeDay = day;
        });
        return;
      }
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final body = _days
          .map(
            (day) => {
              'day_of_week': day,
              'lunch': _lunchControllers[day]!.text.trim(),
              'dinner': _dinnerControllers[day]!.text.trim(),
            },
          )
          .toList();

      await ApiService.post('/weekly-menu', body);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save the menu');
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
          maxHeight: MediaQuery.of(context).size.height * 0.85,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit weekly menu',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close, size: 20, color: colors.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final day = _days[index];
                  final selected = day == _activeDay;
                  final complete = _isDayComplete(day);
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(day.substring(0, 3)),
                        const SizedBox(width: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: complete
                                ? const Color(0xFF34D399)
                                : colors.outlineVariant,
                          ),
                        ),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _activeDay = day),
                    selectedColor: colors.onSurface,
                    backgroundColor: colors.surface,
                    labelStyle: TextStyle(
                      color: selected
                          ? colors.surface
                          : colors.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: selected
                          ? colors.onSurface
                          : colors.outlineVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField(
                      context,
                      'Lunch',
                      _lunchControllers[_activeDay]!,
                      'e.g. Grilled chicken & rice',
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      context,
                      'Dinner',
                      _dinnerControllers[_activeDay]!,
                      'e.g. Vegetable stir-fry',
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.dangerDark,
                  fontSize: 13,
                ),
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
                        'Save full week',
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

  Widget _buildField(
    BuildContext context,
    String label,
    TextEditingController controller,
    String hint,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: colors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
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
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
