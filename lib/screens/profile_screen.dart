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

const _red = Color(0xFFEF4444);
const _green = Color(0xFF10B981);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        margin: const EdgeInsets.only(bottom: 24, left: 60, right: 60),
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
      builder: (_) => _ChangePasswordSheet(email: email),
    );
    if (ok == true) _notify('Password updated');
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

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- identity card ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFF3355FF),
                  child: Text(
                    initialsFor(displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_form.isAvailable) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, size: 6, color: _green),
                                  SizedBox(width: 4),
                                  Text(
                                    'Available',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: _green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_form.bio.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _form.bio,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _openEditSheet,
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: colors.onSurfaceVariant,
                  ),
                  tooltip: 'Edit profile',
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // --- stat strip ---
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: _form.cohort.isNotEmpty ? _form.cohort : '—',
                  label: 'Cohort',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  value: _form.yearOfStudy.isNotEmpty ? _form.yearOfStudy : '—',
                  label: 'Year',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  value: _form.isStudent ? 'Student' : 'Staff',
                  label: 'Status',
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // --- contact info ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Phone', value: _form.phone, colors: colors),
                const SizedBox(height: 10),
                _InfoRow(
                  label: 'Emergency contact',
                  value: _form.emergencyContactName,
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  label: 'Date of birth',
                  value: _form.dateOfBirth,
                  colors: colors,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // --- change password ---
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: colors.surface,
              child: ListTile(
                onTap: _openChangePasswordSheet,
                leading: Icon(
                  Icons.key_outlined,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
                title: Text(
                  'Change password',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.read<AuthProvider>().logout(),
              icon: const Icon(Icons.logout, color: _red, size: 18),
              label: const Text('Log out', style: TextStyle(color: _red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFECACA)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;

  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colors;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        Flexible(
          child: Text(
            value.isNotEmpty ? value : 'Not set',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.onSurface,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
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
                        borderRadius: BorderRadius.circular(14),
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
                        activeThumbColor: const Color(0xFF3355FF),
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
                        borderRadius: BorderRadius.circular(14),
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
                        activeThumbColor: const Color(0xFF3355FF),
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
                                  borderRadius: BorderRadius.circular(999),
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
        borderSide: const BorderSide(color: Color(0xFF3355FF)),
      ),
    );
  }
}

/// --- Change password sheet ---
class _ChangePasswordSheet extends StatefulWidget {
  final String? email;

  const _ChangePasswordSheet({this.email});

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
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
            borderRadius: BorderRadius.circular(20),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                      color: Color(0xFF6B7280),
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
