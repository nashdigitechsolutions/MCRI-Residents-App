import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/resident.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_loader.dart';
import '../widgets/app_refresh.dart';
import '../widgets/ui.dart';

/// WiFi payments — tracks which residents have paid for WiFi this month and
/// which haven't. COMING SOON: the API doesn't store WiFi payments yet, so
/// this is the finished layout with the real resident list and every status
/// shown as "not tracked yet". Nothing here is invented or saved.
class WifiPaymentsScreen extends StatefulWidget {
  const WifiPaymentsScreen({super.key});

  @override
  State<WifiPaymentsScreen> createState() => _WifiPaymentsScreenState();
}

class _WifiPaymentsScreenState extends State<WifiPaymentsScreen> {
  List<Resident> _residents = [];
  bool _loading = true;
  String _filter = 'all'; // all | paid | unpaid
  String _search = '';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/residents');
      if (!mounted) return;
      setState(() {
        _residents =
            (data as List)
                .map((j) => Resident.fromJson(j as Map<String, dynamic>))
                .toList()
              ..sort(
                (a, b) => a.displayName.toLowerCase().compareTo(
                  b.displayName.toLowerCase(),
                ),
              );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _comingSoon([String what = 'Payment tracking']) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$what is coming soon.')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.user?.roleId == 1;
    final q = _search.trim().toLowerCase();
    // No statuses exist yet, so the Paid / Not paid filters show nothing.
    final list = _filter != 'all'
        ? <Resident>[]
        : _residents
              .where(
                (r) =>
                    q.isEmpty ||
                    r.displayName.toLowerCase().contains(q) ||
                    (r.roomNumber ?? '').contains(q),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('WiFi payments')),
      body: _loading
          ? const AppLoadingView(message: 'Loading residents…')
          : AppRefreshIndicator(
              onRefresh: () => _load(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _comingSoonBanner(colors),
                  const SizedBox(height: 14),
                  _monthPicker(colors),
                  const SizedBox(height: 12),
                  _summary(colors),
                  const SizedBox(height: 14),
                  if (!isAdmin) ...[
                    _myStatus(colors, auth.user?.userId),
                    const SizedBox(height: 16),
                  ],
                  SectionHeader(isAdmin ? 'Residents' : 'Who\'s paid'),
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search a resident or room…',
                      prefixIcon: Icon(
                        Icons.search,
                        size: 19,
                        color: colors.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (k, l) in [
                        ('all', 'All'),
                        ('paid', 'Paid'),
                        ('unpaid', 'Not paid'),
                      ])
                        ChoiceChip(
                          label: Text(l),
                          selected: _filter == k,
                          onSelected: (_) => setState(() => _filter = k),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_residents.isEmpty)
                    const EmptyState(
                      icon: Icons.groups_2_outlined,
                      title: 'No residents yet',
                      message: 'Residents appear here once they have accounts.',
                    )
                  else if (list.isEmpty)
                    EmptyState(
                      icon: _filter == 'paid'
                          ? Icons.check_circle_outline
                          : Icons.wifi_off_rounded,
                      title: _filter == 'all'
                          ? 'No matches'
                          : 'Nothing recorded yet',
                      message: _filter == 'all'
                          ? 'Try a different search.'
                          : 'Once payments are tracked, residents who are ${_filter == 'paid' ? 'paid up' : 'still owing'} show here.',
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: colors.outlineVariant),
                            _residentRow(
                              colors,
                              list[i],
                              isAdmin,
                              isMe: list[i].userId == auth.user?.userId,
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  _howItWorks(colors, isAdmin),
                ],
              ),
            ),
    );
  }

  Widget _comingSoonBanner(ColorScheme colors) {
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.wifi_rounded,
              color: AppColors.primaryBorder,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'COMING SOON',
                    style: TextStyle(
                      color: AppColors.primaryBorder,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Who has paid for WiFi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Each month, see which residents are paid up and who still owes. Payments aren\'t recorded yet.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthPicker(ColorScheme colors) {
    final now = DateTime(DateTime.now().year, DateTime.now().month);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () =>
              setState(() => _month = DateTime(_month.year, _month.month - 1)),
          icon: Icon(Icons.chevron_left, color: colors.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM().format(_month),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: _month.isBefore(now)
              ? () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                )
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  /// Paid vs not-paid split. With nothing recorded the bar is an empty track
  /// and the counts read "—" rather than a made-up number.
  Widget _summary(ColorScheme colors) {
    Widget figure(IconData icon, Color color, String label) => Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '—',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Paid this month',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '0 of ${_residents.length} tracked',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(height: 12, color: colors.surfaceContainerHighest),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              figure(
                Icons.check_circle_outline_rounded,
                const Color(0xFF0CA30C),
                'Paid',
              ),
              figure(
                Icons.error_outline_rounded,
                const Color(0xFFD03B3B),
                'Not paid',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _myStatus(ColorScheme colors, int? myUserId) {
    final me = _residents.where((r) => r.userId == myUserId).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_pin_circle_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your WiFi status',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  me == null ? 'You\'re not listed as a resident yet.' : 'Not tracked yet — you\'ll see "Paid" or "Not paid" here.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _residentRow(
    ColorScheme colors,
    Resident r,
    bool isAdmin, {
    bool isMe = false,
  }) {
    return InkWell(
      onTap: isAdmin ? () => _comingSoon('Marking WiFi payments') : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: colors.primaryContainer,
              child: Text(
                r.displayName.isNotEmpty ? r.displayName[0].toUpperCase() : '?',
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
                    isMe ? '${r.displayName} (you)' : r.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    r.roomNumber == null ? 'No room' : 'Room ${r.roomNumber}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Not tracked',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
  }

  Widget _howItWorks(ColorScheme colors, bool isAdmin) {
    final steps = isAdmin
        ? const [
            (
              Icons.how_to_reg_outlined,
              'Mark who paid',
              'Tick residents as paid for each month.',
            ),
            (
              Icons.notifications_active_outlined,
              'Remind the rest',
              'Send a reminder to everyone who hasn\'t paid.',
            ),
            (
              Icons.history_rounded,
              'Month-by-month history',
              'Look back at who paid in earlier months.',
            ),
          ]
        : const [
            (
              Icons.verified_outlined,
              'See your status',
              'Know at a glance whether your WiFi is paid up.',
            ),
            (
              Icons.notifications_active_outlined,
              'Get reminders',
              'A heads-up when this month\'s WiFi is due.',
            ),
            (
              Icons.history_rounded,
              'Your history',
              'Every month you\'ve paid, in one list.',
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Coming with this feature'),
        for (final (icon, title, body) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Home-screen banner that leads to the WiFi payments screen.
class WifiPromoCard extends StatelessWidget {
  const WifiPromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WifiPaymentsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDeep],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                ),
                child: const Icon(Icons.wifi_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'WiFi payments',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Text(
                            'SOON',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'See who has paid for WiFi each month',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
