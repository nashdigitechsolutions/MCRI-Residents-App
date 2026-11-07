import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/initials.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/ui.dart';
import '../conversation_detail_screen.dart';

/// Admin: every resident/staff profile, with "Log in as…".
class AdminProfilesScreen extends StatefulWidget {
  const AdminProfilesScreen({super.key});

  @override
  State<AdminProfilesScreen> createState() => _AdminProfilesScreenState();
}

enum _RoleFilter { all, residents, staff, admins }

class _AdminProfilesScreenState extends State<AdminProfilesScreen> {
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _RoleFilter _filter = _RoleFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _people.isEmpty;
      _error = null;
    });
    try {
      final data = await ApiService.get('/admin/profiles');
      if (!mounted) return;
      setState(() {
        _people = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  static String nameOf(Map<String, dynamic> p) {
    final full = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    return full.isNotEmpty ? full : (p['username'] as String? ?? 'Unknown');
  }

  static int? _int(dynamic v) => v is int ? v : int.tryParse('$v');

  bool _matchesFilter(Map<String, dynamic> p) {
    final role = _int(p['role_id']);
    return switch (_filter) {
      _RoleFilter.all => true,
      _RoleFilter.residents => role == 2,
      _RoleFilter.admins => role == 1,
      _RoleFilter.staff => role != 1 && role != 2,
    };
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _people.where((p) {
      if (!_matchesFilter(p)) return false;
      if (q.isEmpty) return true;
      return [
        nameOf(p),
        p['username'],
        p['email'],
        p['room_number'],
        p['role_name'],
        p['phone'],
      ].whereType<Object>().any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
  }

  void _open(Map<String, dynamic> p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileSheet(person: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('All profiles')),
      body: _loading
          ? const AppLoadingView(message: 'Loading profiles…')
          : _error != null
          ? EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Couldn\'t load profiles',
              message: _error,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  PageHeading(
                    eyebrow: 'Administration',
                    title: 'Everyone in the residence',
                    subtitle:
                        '${_people.length} accounts · tap someone to view or log in as them',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search name, room, email, phone…',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in _RoleFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(switch (f) {
                                _RoleFilter.all => 'All',
                                _RoleFilter.residents => 'Residents',
                                _RoleFilter.staff => 'Staff',
                                _RoleFilter.admins => 'Admins',
                              }),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'No one matches that',
                      ),
                    )
                  else
                    for (final p in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: colors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            side: BorderSide(color: colors.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _open(p),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  _Avatar(
                                    name: nameOf(p),
                                    available: p['is_available'] == true,
                                    size: 44,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nameOf(p),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: colors.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '@${p['username'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            _Pill(
                                              text:
                                                  (p['role_name'] as String? ??
                                                          'member')
                                                      .replaceAll('_', ' '),
                                              strong: _int(p['role_id']) == 1,
                                            ),
                                            if (p['room_number'] != null)
                                              _Pill(
                                                text:
                                                    'Room ${p['room_number']}',
                                                icon:
                                                    Icons.meeting_room_outlined,
                                              ),
                                          ],
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
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool available;
  final double size;
  const _Avatar({required this.name, required this.available, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initialsFor(name),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.36,
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: available ? AppColors.success : AppColors.subtle,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool strong;
  const _Pill({required this.text, this.icon, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? AppColors.ink : colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: strong ? Colors.white : colors.onPrimaryContainer,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: strong ? Colors.white : colors.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full profile, plus Message and "Log in as…".
class _ProfileSheet extends StatefulWidget {
  final Map<String, dynamic> person;
  const _ProfileSheet({required this.person});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  String? _busy; // 'login' | 'message'

  Map<String, dynamic> get p => widget.person;
  String get _name => _AdminProfilesScreenState.nameOf(p);

  Future<void> _loginAs() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log in as $_name?'),
        content: const Text(
          'You\'ll use the app exactly as they see it, for up to 60 minutes. '
          'Anything you do (messages, votes, requests) happens as them. '
          'This is recorded in the audit log.\n\n'
          'Return to your account any time from the banner at the top.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log in as them'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = 'login');
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ApiService.post('/admin/impersonate', {
        'user_id': p['user_id'],
      });
      final token = (data as Map)['token'] as String;
      await auth.startImpersonation(token); // app switches accounts
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _message() async {
    setState(() => _busy = 'message');
    final nav = Navigator.of(context);
    try {
      final data = await ApiService.post('/conversations', {
        'is_group': false,
        'member_ids': [p['user_id']],
      });
      final raw = (data as Map)['conversation']?['conversation_id'];
      final id = raw is int ? raw : int.parse('$raw');
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(conversationId: id),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open a chat')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String? v(String k) {
      final x = p[k];
      if (x == null) return null;
      final s = '$x'.trim();
      return s.isEmpty ? null : s;
    }

    final canLogin = p['can_impersonate'] == true;
    final rows = <(IconData, String, String?, Uri?)>[
      (
        Icons.mail_outline_rounded,
        'Email',
        v('email'),
        v('email') == null ? null : Uri(scheme: 'mailto', path: v('email')),
      ),
      (
        Icons.phone_outlined,
        'Phone',
        v('phone'),
        v('phone') == null ? null : Uri(scheme: 'tel', path: v('phone')),
      ),
      (Icons.meeting_room_outlined, 'Room', v('room_number'), null),
      (
        Icons.badge_outlined,
        'Role',
        v('role_name')?.replaceAll('_', ' '),
        null,
      ),
      (
        Icons.school_outlined,
        'Study',
        p['is_student'] == true
            ? [
                'Student',
                v('year_of_study') == null
                    ? null
                    : 'Year ${v('year_of_study')}',
                v('cohort'),
              ].whereType<String>().join(' · ')
            : null,
        null,
      ),
      (
        Icons.cake_outlined,
        'Birthday',
        v('date_of_birth')?.split('T').first,
        null,
      ),
      (Icons.wc_outlined, 'Gender', v('gender'), null),
      (
        Icons.contact_emergency_outlined,
        'Emergency contact',
        [
          v('emergency_contact_name'),
          v('emergency_contact_phone'),
        ].whereType<String>().join(' · '),
        v('emergency_contact_phone') == null
            ? null
            : Uri(scheme: 'tel', path: v('emergency_contact_phone')),
      ),
    ].where((r) => r.$3 != null && r.$3!.isNotEmpty).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Center(
              child: _Avatar(
                name: _name,
                available: p['is_available'] == true,
                size: 76,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            Text(
              '@${p['username'] ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (v('bio') != null) ...[
              const SizedBox(height: 10),
              Text(
                v('bio')!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurface,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy != null ? null : _message,
                    icon: _busy == 'message'
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoader(),
                          )
                        : const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                          ),
                    label: const Text('Message'),
                  ),
                ),
                if (canLogin) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy != null ? null : _loginAs,
                      icon: _busy == 'login'
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: AppLoader(color: Colors.white),
                            )
                          : const Icon(Icons.switch_account_rounded, size: 18),
                      label: const Text('Log in as'),
                    ),
                  ),
                ],
              ],
            ),
            if (!canLogin)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Admin accounts can\'t be logged into.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 48,
                        color: colors.outlineVariant,
                      ),
                    ListTile(
                      leading: Icon(
                        rows[i].$1,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      title: Text(
                        rows[i].$2,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        rows[i].$3!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      onTap: rows[i].$4 == null
                          ? null
                          : () => launchUrl(rows[i].$4!),
                    ),
                  ],
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'They haven\'t filled in their profile yet.',
                        style: TextStyle(color: colors.onSurfaceVariant),
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
