import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/live_refresh.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/app_refresh.dart';
import '../../widgets/ui.dart';

/// Admin: approve or decline new accounts. The app is public, so every
/// sign-up waits here (on top of email verification) before it can sign in.
class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen>
    with LiveRefresh {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    listenLive(['notification'], () => _load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/users/pending');
      if (!mounted) return;
      setState(() {
        _rows = (data as List).cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> u, bool approve) async {
    final id = (u['user_id'] as num).toInt();
    final name = _name(u);
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Decline this account?'),
          content: Text(
            '$name won\'t be able to sign in. You can still approve them later from this list.',
          ),
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
              child: const Text('Decline'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy.add(id));
    try {
      await ApiService.post('/users/$id/${approve ? 'approve' : 'reject'}', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? '$name is approved and has been emailed'
                : '$name was declined',
          ),
        ),
      );
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  static String _name(Map<String, dynamic> u) {
    final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return full.isNotEmpty ? full : (u['username'] as String? ?? 'This user');
  }

  @override
  Widget build(BuildContext context) {
    final pending = _rows
        .where((u) => u['approval_status'] == 'pending')
        .toList();
    final declined = _rows
        .where((u) => u['approval_status'] == 'rejected')
        .toList();

    return Scaffold(
      appBar: AppBar(),
      body: _loading
          ? const AppLoadingView(message: 'Loading new accounts…')
          : AppRefreshIndicator(
              onRefresh: () => _load(quiet: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  PageHeading(
                    eyebrow: 'Administration',
                    title: 'New accounts',
                    subtitle: pending.isEmpty
                        ? 'Nobody is waiting for approval'
                        : '${pending.length} waiting for approval',
                  ),
                  const SizedBox(height: 18),
                  if (_error != null)
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load accounts',
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: _load,
                    )
                  else if (pending.isEmpty && declined.isEmpty)
                    const EmptyState(
                      icon: Icons.verified_user_outlined,
                      title: 'All caught up',
                      message:
                          'New sign-ups will appear here for you to approve.',
                    )
                  else ...[
                    for (final u in pending)
                      _AccountCard(
                        user: u,
                        busy: _busy.contains((u['user_id'] as num).toInt()),
                        onApprove: () => _decide(u, true),
                        onDecline: () => _decide(u, false),
                      ),
                    if (declined.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.only(left: 2, bottom: 10),
                        child: Eyebrow('Declined'),
                      ),
                      for (final u in declined)
                        _AccountCard(
                          user: u,
                          busy: _busy.contains((u['user_id'] as num).toInt()),
                          onApprove: () => _decide(u, true),
                        ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback? onDecline;

  const _AccountCard({
    required this.user,
    required this.busy,
    required this.onApprove,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = _AdminApprovalsScreenState._name(user);
    final verified = user['is_verified'] == true;
    final google = user['provider'] == 'google';
    final signedUp = DateTime.tryParse('${user['signed_up_at'] ?? ''}');

    Widget chip(IconData icon, String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      '${user['email'] ?? ''}',
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
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              verified
                  ? chip(
                      Icons.mark_email_read_outlined,
                      'Email verified',
                      AppColors.success,
                    )
                  : chip(
                      Icons.mail_outline_rounded,
                      'Email not verified yet',
                      AppColors.warning,
                    ),
              if (google)
                chip(
                  Icons.account_circle_outlined,
                  'Google',
                  colors.onSurfaceVariant,
                ),
              if (signedUp != null)
                chip(
                  Icons.schedule_rounded,
                  'Signed up ${DateFormat.MMMd().add_jm().format(signedUp.toLocal())}',
                  colors.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (busy)
            const SizedBox(
              height: 40,
              child: Center(child: AppLoader(size: 22)),
            )
          else
            Row(
              children: [
                if (onDecline != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dangerDark,
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
