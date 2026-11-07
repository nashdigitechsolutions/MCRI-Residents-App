import 'package:intl/intl.dart';

import '../widgets/ui.dart';
import '../navigation/app_navigator.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:mcri_residents_app/widgets/app_loader.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mcri_residents_app/utils/validators.dart';
import 'package:provider/provider.dart';

import '../services/biometric_store.dart';
import '../widgets/input_style.dart';
import '../widgets/password_field.dart';

import '../models/profile_fields.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/initials.dart';

const _red = AppColors.danger;
const _currentYear = 2026; // update yearly, or compute via DateTime.now().year
const _minYear = 1900;
const _maxYear = 2100;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileFields _form = ProfileFields();

  @override
  void initState() {
    super.initState();
    _loadCache();
    _loadFromServer();
  }

  Future<void> _loadFromServer() async {
    try {
      final data = await ApiService.get('/profile');
      final fetched = ProfileFields.fromJson(data as Map<String, dynamic>);
      setState(() => _form = fetched);
      await _saveCache(fetched);
    } catch (e) {
      // Server fetch failed (or this user has no saved profile yet) —
      // whatever was in the local cache from _loadCache() stands as-is.
    }
  }

  String _cacheKey(int? userId) => 'mcri_profile_cache_${userId ?? 'anon'}';

  Future<void> _loadCache() async {
    final userId = context.read<AuthProvider>().user?.userId;
    final cached = await StorageService.getItem(_cacheKey(userId));
    if (cached != null) {
      try {
        setState(
          () => _form = ProfileFields.fromJson(
            jsonDecode(cached) as Map<String, dynamic>,
          ),
        );
      } catch (e) {
        // ignore corrupt cache
      }
    }
  }

  Future<void> _saveCache(ProfileFields form) async {
    final userId = context.read<AuthProvider>().user?.userId;
    await StorageService.setItem(_cacheKey(userId), jsonEncode(form.toJson()));
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

  Future<void> _openEditSheet() async {
    final user = context.read<AuthProvider>().user;
    final saved = await showModalBottomSheet<ProfileFields>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EditProfileSheet(initial: _form.copy(), userId: user?.userId),
    );

    if (saved != null) {
      setState(() => _form = saved);
      await _saveCache(saved);
      _notify('Profile updated');
    }
  }

  Future<void> _openChangePasswordSheet() async {
    final email = context.read<AuthProvider>().user?.email;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangePasswordSheet(email: email),
    );
    if (ok == true) _notify('Password updated');
  }

  bool _savingAvailability = false;

  Future<void> _setAvailable(bool next) async {
    final previous = _form;
    setState(() {
      _form = _form.copy()..isAvailable = next;
      _savingAvailability = true;
    });
    try {
      await ApiService.patch('/set-profile', {
        'user_id': context.read<AuthProvider>().user?.userId,
        'is_available': next,
      });
      await _saveCache(_form);
    } catch (_) {
      if (mounted) {
        setState(() => _form = previous);
        _notify('Could not update availability', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingAvailability = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerDark,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<AuthProvider>().logout();
  }

  /// Share of the profile filled in, for the "profile strength" meter.
  ({int done, int total, String? next}) get _completeness {
    final checks = <(bool, String)>[
      (
        _form.firstName.isNotEmpty && _form.lastName.isNotEmpty,
        'your full name',
      ),
      (_form.phone.isNotEmpty, 'a phone number'),
      (_form.bio.isNotEmpty, 'a short bio'),
      (_form.dateOfBirth.isNotEmpty, 'your date of birth'),
      (_form.gender.isNotEmpty, 'your gender'),
      (
        _form.emergencyContactName.isNotEmpty &&
            _form.emergencyContactPhone.isNotEmpty,
        'an emergency contact',
      ),
      (!_form.isStudent || _form.cohort.isNotEmpty, 'your cohort'),
    ];
    final missing = checks.where((c) => !c.$1).map((c) => c.$2);
    return (
      done: checks.length - missing.length,
      total: checks.length,
      next: missing.firstOrNull,
    );
  }

  static String _roleLabel(int? roleId) => switch (roleId) {
    1 => 'Admin',
    2 => 'Resident',
    4 => 'Caretaker',
    _ => 'Member',
  };

  String _prettyDate(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? raw : DateFormat('d MMMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final fullName = [
      _form.firstName,
      _form.lastName,
    ].where((s) => s.isNotEmpty).join(' ');
    final displayName = fullName.isNotEmpty
        ? fullName
        : (user?.username ?? 'Resident');
    final c = _completeness;

    Widget section(String title, List<_Line> lines) {
      final shown = lines.where((l) => l.value.isNotEmpty).toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Eyebrow(title),
            ),
            Material(
              color: colors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: shown.isEmpty
                  ? ListTile(
                      leading: Icon(
                        Icons.add_circle_outline_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                      title: Text(
                        'Add details',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      onTap: _openEditSheet,
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 56,
                              color: colors.outlineVariant,
                            ),
                          ListTile(
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Icon(
                                shown[i].icon,
                                size: 17,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              shown[i].label,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            subtitle: Text(
                              shown[i].value,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                                height: 1.3,
                              ),
                            ),
                            trailing: shown[i].uri == null
                                ? null
                                : Icon(
                                    Icons.call_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                            onTap: shown[i].uri == null
                                ? null
                                : () => launchUrl(shown[i].uri!),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFromServer,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Hero ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.ink,
                    Color(0xFF2A160B),
                    AppColors.primaryDeep,
                  ],
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryBorder,
                              AppColors.primary,
                            ],
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: AppColors.ink,
                          child: Text(
                            initialsFor(displayName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _form.isAvailable
                                ? AppColors.success
                                : AppColors.subtle,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.ink, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if ((user?.username ?? '').isNotEmpty)
                        Text(
                          '@${user!.username}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _roleLabel(user?.roleId),
                          style: const TextStyle(
                            color: AppColors.primaryBorder,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((user?.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user!.email,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openEditSheet,
                          icon: const Icon(Icons.edit_rounded, size: 17),
                          label: const Text('Edit profile'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppRadius.sm + 2,
                            ),
                            onTap: _savingAvailability
                                ? null
                                : () => _setAvailable(!_form.isAvailable),
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm + 2,
                                ),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _savingAvailability
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: AppLoader(color: Colors.white),
                                        )
                                      : Icon(
                                          Icons.circle,
                                          size: 10,
                                          color: _form.isAvailable
                                              ? AppColors.success
                                              : AppColors.subtle,
                                        ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _form.isAvailable
                                          ? 'Around the house'
                                          : 'Away',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Profile strength ─────────────────────────────
                  if (c.done < c.total)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Profile ${((c.done / c.total) * 100).round()}% complete',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _openEditSheet,
                                child: const Text('Complete'),
                              ),
                            ],
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: c.done / c.total,
                              minHeight: 6,
                              backgroundColor: colors.surface,
                              color: AppColors.primary,
                            ),
                          ),
                          if (c.next != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Next: add ${c.next}.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // ── At a glance ─────────────────────────────────
                  Row(
                    children: [
                      for (final (label, value, icon) in [
                        (
                          'Status',
                          _form.isStudent ? 'Student' : 'Staff',
                          Icons.school_outlined,
                        ),
                        (
                          'Year',
                          _form.yearOfStudy.isNotEmpty
                              ? _form.yearOfStudy
                              : '—',
                          Icons.timeline_rounded,
                        ),
                        (
                          'Cohort',
                          _form.cohort.isNotEmpty ? _form.cohort : '—',
                          Icons.groups_outlined,
                        ),
                      ]) ...[
                        if (label != 'Status') const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: Column(
                              children: [
                                Icon(icon, size: 18, color: AppColors.primary),
                                const SizedBox(height: 6),
                                Text(
                                  value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  label,
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
                  ),
                  const SizedBox(height: 18),

                  section('About', [
                    _Line(Icons.format_quote_rounded, 'Bio', _form.bio),
                  ]),
                  section('Contact', [
                    _Line(
                      Icons.phone_outlined,
                      'Phone',
                      _form.phone,
                      _form.phone.isEmpty
                          ? null
                          : Uri(scheme: 'tel', path: _form.phone),
                    ),
                    _Line(
                      Icons.mail_outline_rounded,
                      'Email',
                      user?.email ?? '',
                    ),
                  ]),
                  section('Personal', [
                    _Line(
                      Icons.badge_outlined,
                      'Full name',
                      [
                        _form.firstName,
                        _form.middleName,
                        _form.lastName,
                      ].where((s) => s.isNotEmpty).join(' '),
                    ),
                    _Line(
                      Icons.cake_outlined,
                      'Date of birth',
                      _form.dateOfBirth.isEmpty
                          ? ''
                          : _prettyDate(_form.dateOfBirth),
                    ),
                    _Line(Icons.wc_outlined, 'Gender', _form.gender),
                  ]),
                  section('Emergency contact', [
                    _Line(
                      Icons.contact_emergency_outlined,
                      'Name',
                      _form.emergencyContactName,
                    ),
                    _Line(
                      Icons.phone_in_talk_outlined,
                      'Phone',
                      _form.emergencyContactPhone,
                      _form.emergencyContactPhone.isEmpty
                          ? null
                          : Uri(
                              scheme: 'tel',
                              path: _form.emergencyContactPhone,
                            ),
                    ),
                  ]),

                  // ── Account ─────────────────────────────────────
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Eyebrow('Account'),
                  ),
                  Material(
                    color: colors.surface,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.lock_outline_rounded,
                            color: AppColors.primary,
                          ),
                          title: const Text(
                            'Change password',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _openChangePasswordSheet,
                        ),
                        Divider(
                          height: 1,
                          indent: 56,
                          color: colors.outlineVariant,
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.settings_outlined,
                            color: AppColors.primary,
                          ),
                          title: const Text(
                            'Settings',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => shellTab.value = ShellTab.settings,
                        ),
                        Divider(
                          height: 1,
                          indent: 56,
                          color: colors.outlineVariant,
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.logout_rounded,
                            color: AppColors.dangerDark,
                          ),
                          title: Text(
                            auth.isImpersonating
                                ? 'Return to admin'
                                : 'Log out',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.dangerDark,
                            ),
                          ),
                          onTap: auth.isImpersonating
                              ? () => context
                                    .read<AuthProvider>()
                                    .endImpersonation()
                              : _confirmLogout,
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
    );
  }
}

/// One labelled detail on the profile (tappable when [uri] is set).
class _Line {
  final IconData icon;
  final String label;
  final String value;
  final Uri? uri;
  const _Line(this.icon, this.label, this.value, [this.uri]);
}

/// --- Edit profile sheet ---
class _EditProfileSheet extends StatefulWidget {
  final ProfileFields initial;
  final int? userId;

  const _EditProfileSheet({required this.initial, required this.userId});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late ProfileFields _form;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _bio;
  late final TextEditingController _phone;
  late final TextEditingController _cohort;
  late final TextEditingController _year;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;

  bool _submitting = false;
  String? _error;

  bool get _yearInvalid {
    if (_form.yearOfStudy.isEmpty) return false;
    final y = int.tryParse(_form.yearOfStudy);
    return y == null || y < _minYear || y > _maxYear;
  }

  @override
  void initState() {
    super.initState();
    _form = widget.initial;
    _firstName = TextEditingController(text: _form.firstName);
    _lastName = TextEditingController(text: _form.lastName);
    _bio = TextEditingController(text: _form.bio);
    _phone = TextEditingController(text: _form.phone);
    _cohort = TextEditingController(text: _form.cohort);
    _year = TextEditingController(text: _form.yearOfStudy);
    _emergencyName = TextEditingController(text: _form.emergencyContactName);
    _emergencyPhone = TextEditingController(text: _form.emergencyContactPhone);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _bio.dispose();
    _phone.dispose();
    _cohort.dispose();
    _year.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_form.dateOfBirth) ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(
        () => _form.dateOfBirth =
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    _form
      ..firstName = _firstName.text.trim()
      ..lastName = _lastName.text.trim()
      ..bio = _bio.text.trim()
      ..phone = _phone.text.trim()
      ..cohort = _cohort.text.replaceAll(RegExp(r'[^\d]'), '')
      ..yearOfStudy = _year.text.replaceAll(RegExp(r'[^\d]'), '')
      ..emergencyContactName = _emergencyName.text.trim()
      ..emergencyContactPhone = _emergencyPhone.text.trim();

    if (_yearInvalid) {
      setState(() => _error = 'Year must be between $_minYear and $_maxYear');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.patch('/set-profile', {
        'user_id': widget.userId,
        ..._form.toJson(),
      });
      if (mounted) Navigator.of(context).pop(_form);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save profile');
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit profile',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, size: 20, color: colors.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            colors,
                            'First name',
                            _firstName,
                            hint: 'Adam',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            colors,
                            'Last name',
                            _lastName,
                            hint: 'Blacks',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel(colors, 'Bio'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bio,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: _decoration(
                        colors,
                        hint: 'A sentence or two about yourself…',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            colors,
                            'Phone',
                            _phone,
                            hint: '+263 77 123 4567',
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _form.gender.isEmpty
                                ? null
                                : _form.gender,
                            decoration: _decoration(colors, label: 'Gender'),
                            hint: const Text('Select…'),
                            items: genderOptions
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g['value'],
                                    child: Text(g['label']!),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _form.gender = v ?? ''),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDate,
                            child: AbsorbPointer(
                              child: _field(
                                colors,
                                'Date of birth',
                                TextEditingController(text: _form.dateOfBirth),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            colors,
                            'Cohort',
                            _cohort,
                            hint: 'e.g. 12',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(
                      colors,
                      'Year of study',
                      _year,
                      hint: '$_currentYear',
                      keyboardType: TextInputType.number,
                      error: _yearInvalid
                          ? 'Enter a year between $_minYear and $_maxYear'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            colors,
                            'Emergency contact name',
                            _emergencyName,
                            hint: 'Jane Blacks',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            colors,
                            'Emergency contact phone',
                            _emergencyPhone,
                            hint: '+263 77 987 6543',
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Student',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          'Shown on your profile as your status',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        value: _form.isStudent,
                        onChanged: (v) => setState(() => _form.isStudent = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Available to chat',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          "Show others you're around",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        value: _form.isAvailable,
                        onChanged: (v) => setState(() => _form.isAvailable = v),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: _red, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
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
                                      'Save changes',
                                      style: TextStyle(
                                        color: colors.surface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: colors.outlineVariant),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm + 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Widget _fieldLabel(ColorScheme colors, String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: colors.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _field(
    ColorScheme colors,
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(colors, label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: _decoration(colors, hint: hint),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(color: _red, fontSize: 11)),
        ],
      ],
    );
  }

  InputDecoration _decoration(
    ColorScheme colors, {
    String? hint,
    String? label,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
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
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}

/// --- Change password sheet ---
class ChangePasswordSheet extends StatefulWidget {
  final String? email;

  const ChangePasswordSheet({super.key, this.email});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  late final TextEditingController _emailController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.email ?? '');
  }

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Keeps biometric sign-in working after a password change.
  /// - Already enabled for this account: silently store the new password.
  /// - Not enabled: offer to turn it on (unless the user said never).
  Future<void> _syncBiometric(String email, String newPassword) async {
    try {
      if (await BiometricStore.isEnabled()) {
        final saved = await BiometricStore.savedEmail();
        if (saved?.toLowerCase() == email.toLowerCase()) {
          await BiometricStore.save(email, newPassword);
        }
        return; // enabled for another account: leave it alone
      }

      if (!await BiometricStore.isAvailable()) return;
      if (await BiometricStore.isDeclined()) return;
      if (!mounted) return;

      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          title: const Text(
            'Use biometrics next time?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Sign in faster with your fingerprint or face. Your details are '
            'stored encrypted on this device only.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'never'),
              child: const Text("Don't ask again"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'no'),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'yes'),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (choice == 'never') await BiometricStore.setDeclined();
      if (choice != 'yes') return;

      if (await BiometricStore.confirm('Confirm to enable biometric sign-in')) {
        await BiometricStore.save(email, newPassword);
      }
    } catch (e) {
      debugPrint('[bio] profile sync failed: $e');
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final oldPassword = _oldController.text;
    final newPassword = _newController.text;

    if (oldPassword.isEmpty) {
      setState(() => _error = 'Enter your current password');
      return;
    }

    // 8-72 characters, same rule the API enforces.
    final problem = Validators.newPassword(newPassword);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    if (newPassword == oldPassword) {
      setState(() => _error = 'New password must differ from your current one');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/change-password', {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      });

      // 1) Biometrics first, so the OS prompt and our dialog never collide.
      final email = widget.email;
      if (email != null && email.isNotEmpty) {
        await _syncBiometric(email, newPassword);
      }

      // 2) Then ask Samsung Pass / Google / Keychain to save the new password.
      //    Fields must still be mounted here, so this comes before the pop.
      TextInput.finishAutofillContext(shouldSave: true);

      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      // friendlyError turns raw zod/validation JSON into one readable line.
      if (mounted) setState(() => _error = friendlyError(e.message));
    } catch (_) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) setState(() => _error = 'Could not update password');
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
        child: SingleChildScrollView(
          child: AutofillGroup(
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
                  'Change password',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 16),

                // Read-only account field. Password managers need a username
                // in the form to know which saved login to update.
                if (widget.email != null && widget.email!.isNotEmpty) ...[
                  TextField(
                    controller: _emailController,
                    readOnly: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: AppColors.muted,
                    ),
                    decoration: appFieldDecoration(
                      hint: 'Email',
                      focused: false,
                      icon: Icons.mail_outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                AppPasswordField(
                  controller: _oldController,
                  hint: 'Current password',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: 12),
                AppPasswordField(
                  controller: _newController,
                  hint: 'New password',
                  showStrength: true,
                  showRequirements: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: _red, fontSize: 13),
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
                            child: AppLoader(
                              strokeWidth: 2,
                              color: colors.surface,
                            ),
                          )
                        : Text(
                            'Update password',
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
      ),
    );
  }
}
