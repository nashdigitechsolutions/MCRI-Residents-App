// ignore_for_file: unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/weekly_menu_entry.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

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
            ? const Color(0xFFDC2626)
            : null, // null = theme default
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        margin: const EdgeInsets.only(bottom: 24, left: 60, right: 60),
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

  @override
  Widget build(BuildContext context) {
    final isStaff = context.watch<AuthProvider>().user?.roleId == 1;
    final ordered = _ordered(_menu);
    final today = _todayName();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly menu'),
        actions: [
          if (isStaff)
            TextButton.icon(
              onPressed: _openEditSheet,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit menu'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchMenu(showLoading: false),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: ordered.length,
                itemBuilder: (context, index) {
                  final entry = ordered[index];
                  final isToday = entry.dayOfWeek == today;
                  final isEmpty = entry.lunch.isEmpty && entry.dinner.isEmpty;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isToday
                          ? const Color(0xFF3355FF).withOpacity(0.08)
                          : colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isToday
                            ? const Color(0xFF3355FF).withOpacity(0.3)
                            : colors.outlineVariant,
                        width: isToday ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.dayOfWeek,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                            if (isToday)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3355FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'TODAY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (isEmpty)
                          Text(
                            'No menu set for this day yet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else ...[
                          _MealRow(
                            icon: Icons.ramen_dining_outlined,
                            label: 'Lunch',
                            value: entry.lunch,
                          ),
                          const SizedBox(height: 8),
                          _MealRow(
                            icon: Icons.nightlight_outlined,
                            label: 'Dinner',
                            value: entry.dinner,
                          ),
                        ],
                        // Breakfast intentionally not shown — not offered currently.
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MealRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontSize: 13.5, color: colors.onSurface),
              ),
            ],
          ),
        ),
      ],
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
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
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
              borderSide: const BorderSide(color: Color(0xFF3355FF)),
            ),
          ),
        ),
      ],
    );
  }
}
