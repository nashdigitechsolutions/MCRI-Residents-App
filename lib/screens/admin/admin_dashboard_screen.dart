import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../../widgets/app_refresh.dart';

import '../weekly_menu_screen.dart';
import '../duties_screen.dart';
import '../equipment_screen.dart';
import 'admin_profiles_screen.dart';
import '../../widgets/ui.dart';
import '../../widgets/charts.dart';

import 'package:intl/intl.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'audit_logs_webview_screen.dart';
import '../rooms_screen.dart';
import '../polls_screen.dart';
import 'admin_roles_screen.dart';

const _red = AppColors.danger;
const _accent = AppColors.primary;
const _amber = AppColors.warning;
const _green = AppColors.success;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Map<String, dynamic>> _maintenance = [];
  List<Map<String, dynamic>> _equipRequests = [];
  List<Map<String, dynamic>> _equipReports = [];
  List<Map<String, dynamic>> _duties = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.get('/maintenance-requests'),
        ApiService.get('/equipment-requests'),
        ApiService.get('/equipment-reports'),
        ApiService.get('/duties'),
        ApiService.get('/rooms').catchError((_) => []),
        ApiService.get('/users').catchError((_) => []),
      ]);
      if (!mounted) return;
      setState(() {
        _maintenance = (results[0] as List).cast<Map<String, dynamic>>();
        _equipRequests = (results[1] as List).cast<Map<String, dynamic>>();
        _equipReports = (results[2] as List).cast<Map<String, dynamic>>();
        _duties = (results[3] as List).cast<Map<String, dynamic>>();
        _rooms = (results[4] as List).cast<Map<String, dynamic>>();
        _users = (results[5] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _notify('Could not load admin data', isError: true);
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  List<Map<String, dynamic>> get _pendingMaintenance =>
      _maintenance.where((m) => m['status'] == 'open').toList();
  List<Map<String, dynamic>> get _pendingEquipRequests =>
      _equipRequests.where((r) => r['status'] == 'pending').toList();
  List<Map<String, dynamic>> get _openEquipReports =>
      _equipReports.where((r) => r['status'] != 'resolved').toList();

  Future<void> _updateMaintenance(
    Map<String, dynamic> req,
    String status,
  ) async {
    final id = req['request_id'] is String
        ? int.parse(req['request_id'])
        : req['request_id'] as int;
    setState(() => _busyId = 'm-$id:$status');
    try {
      await ApiService.patch('/maintenance-requests/$id', {'status': status});
      _notify('Request updated');
      _loadAll(showLoading: false);
    } catch (e) {
      _notify('Update failed', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _updateEquipRequest(
    Map<String, dynamic> req,
    String status,
  ) async {
    final id = req['equip_request_id'] is String
        ? int.parse(req['equip_request_id'])
        : req['equip_request_id'] as int;
    setState(() => _busyId = 'er-$id:$status');
    try {
      await ApiService.patch('/equipment-requests/$id', {'status': status});
      _notify('Request updated');
      _loadAll(showLoading: false);
    } catch (e) {
      _notify('Update failed', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _updateEquipReport(
    Map<String, dynamic> rep,
    String status,
  ) async {
    final id = rep['eq_reports_id'] is String
        ? int.parse(rep['eq_reports_id'])
        : rep['eq_reports_id'] as int;
    setState(() => _busyId = 'rep-$id:$status');
    try {
      await ApiService.patch('/equipment-reports/$id', {'status': status});
      _notify('Report updated');
      _loadAll(showLoading: false);
    } catch (e) {
      _notify('Update failed', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openBroadcastSheet() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BroadcastSheet(),
    );
    if (sent == true) _notify('Notification sent to all residents');
  }

  void _openAuditLogs() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditLogsWebViewScreen(token: token)),
    );
  }

  // ───────────────────────────── insights ─────────────────────────────

  static DateTime? _date(Map<String, dynamic> m) => DateTime.tryParse(
    '${m['created_at'] ?? m['request_date'] ?? m['assigned_date'] ?? ''}',
  );

  /// Requests + reports raised per week, last 8 weeks (oldest → newest).
  List<(String, num)> get _weeklyActivity {
    final now = DateTime.now();
    final startOfThisWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final counts = List<int>.filled(8, 0);
    for (final m in [..._maintenance, ..._equipRequests, ..._equipReports]) {
      final d = _date(m);
      if (d == null) continue;
      final weeksAgo = startOfThisWeek
          .difference(DateTime(d.year, d.month, d.day))
          .inDays;
      final idx = 7 - (weeksAgo < 0 ? 0 : (weeksAgo / 7).ceil());
      if (idx >= 0 && idx < 8) counts[idx]++;
    }
    return [
      for (var i = 0; i < 8; i++)
        (
          DateFormat('d/M')
              .format(startOfThisWeek.subtract(Duration(days: 7 * (7 - i)))),
          counts[i],
        ),
    ];
  }

  ({int open, int inProgress, int fixed}) get _repairStatus {
    var open = 0, inProgress = 0, fixed = 0;
    for (final m in [..._maintenance, ..._equipReports]) {
      switch (m['status']) {
        case 'open':
          open++;
        case 'in_progress':
          inProgress++;
        case 'resolved':
          fixed++;
      }
    }
    return (open: open, inProgress: inProgress, fixed: fixed);
  }

  List<({String label, num value, num max})> get _occupancy {
    int n(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    final rows =
        [
          for (final r in _rooms)
            (
              label: 'Rm ${r['room_number'] ?? '?'}',
              value: n(r['current_occupancy']),
              max: n(r['max_capacity']),
            ),
        ]..sort(
          (a, b) => (b.max == 0 ? 0 : b.value / b.max).compareTo(
            a.max == 0 ? 0 : a.value / a.max,
          ),
        );
    return rows;
  }

  List<(String, int)> get _topRequested {
    final counts = <String, int>{};
    for (final r in _equipRequests) {
      final name = '${r['equipment_name'] ?? r['item_name'] ?? 'Item'}'.trim();
      counts[name] =
          (counts[name] ?? 0) +
          ((r['quantity'] is int) ? r['quantity'] as int : 1);
    }
    final list = counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(5).toList();
  }

  Widget _insights(ColorScheme colors) {
    final residents = _users.where((u) => '${u['role_id']}' == '2').length;
    final beds = _rooms.fold<int>(
      0,
      (s, r) => s + (int.tryParse('${r['max_capacity']}') ?? 0),
    );
    final occupied = _rooms.fold<int>(
      0,
      (s, r) => s + (int.tryParse('${r['current_occupancy']}') ?? 0),
    );
    final occPct = beds == 0 ? 0 : ((occupied / beds) * 100).round();
    final weekly = _weeklyActivity;
    final thisWeek = weekly.last.$2, lastWeek = weekly[weekly.length - 2].$2;
    final diff = thisWeek - lastWeek;
    final repairs = _repairStatus;
    final dutiesDone = _duties.where((d) => d['status'] == 'completed').length;
    final dutyPct = _duties.isEmpty
        ? 0
        : ((dutiesDone / _duties.length) * 100).round();
    final purchases = _equipRequests
        .where((r) => r['status'] == 'pending' || r['status'] == 'approved')
        .length;
    final top = _topRequested;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          eyebrow: 'Administration',
          title: 'Residence at a glance',
          subtitle: 'Live numbers — pull down to refresh',
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            StatFigure(
              label: 'Residents',
              value: '$residents',
              icon: Icons.groups_2_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminProfilesScreen()),
              ),
            ),
            StatFigure(
              label: 'Occupancy',
              value: '$occPct%',
              icon: Icons.bed_outlined,
              delta: '$occupied of $beds beds',
            ),
            StatFigure(
              label: 'Open repairs',
              value: '${repairs.open + repairs.inProgress}',
              icon: Icons.build_circle_outlined,
              delta: repairs.fixed > 0 ? '${repairs.fixed} fixed so far' : null,
            ),
            StatFigure(
              label: 'Purchases to handle',
              value: '$purchases',
              icon: Icons.shopping_cart_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EquipmentScreen(initialTab: 'requests'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Quick actions
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Broadcast'),
              onPressed: _openBroadcastSheet,
            ),
            ActionChip(
              avatar: const Icon(Icons.groups_2_outlined, size: 18),
              label: const Text('All profiles'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminProfilesScreen()),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.assignment_outlined, size: 18),
              label: const Text('Duties'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DutiesScreen())),
            ),
            ActionChip(
              avatar: const Icon(Icons.restaurant_menu_rounded, size: 18),
              label: const Text('Weekly menu'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WeeklyMenuScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        ChartCard(
          title: 'Requests & reports per week',
          subtitle: diff == 0
              ? '$thisWeek this week — same as last week'
              : '$thisWeek this week · ${diff > 0 ? '+' : ''}$diff vs last week',
          chart: ColumnChart(data: weekly),
          table: [for (final (l, v) in weekly) ('Week of $l', '$v')],
        ),
        const SizedBox(height: 12),

        ChartCard(
          title: 'Repairs by status',
          subtitle: 'Maintenance requests and equipment faults',
          chart: SegmentedBar(
            parts: [
              (
                label: 'Open',
                value: repairs.open,
                color: StatusColors.critical,
                icon: Icons.error_outline_rounded,
              ),
              (
                label: 'In progress',
                value: repairs.inProgress,
                color: StatusColors.warning,
                icon: Icons.timelapse_rounded,
              ),
              (
                label: 'Fixed',
                value: repairs.fixed,
                color: StatusColors.good,
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
          table: [
            ('Open', '${repairs.open}'),
            ('In progress', '${repairs.inProgress}'),
            ('Fixed', '${repairs.fixed}'),
          ],
        ),
        const SizedBox(height: 12),

        if (_rooms.isNotEmpty) ...[
          ChartCard(
            title: 'Room occupancy',
            subtitle: 'Fullest rooms first',
            chart: CapacityBars(rows: _occupancy),
            table: [
              for (final r in _occupancy) (r.label, '${r.value} / ${r.max}'),
            ],
          ),
          const SizedBox(height: 12),
        ],

        ChartCard(
          title: 'Duty completion',
          subtitle: '$dutiesDone of ${_duties.length} duties done',
          chart: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$dutyPct%',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _duties.isEmpty ? 0 : dutiesDone / _duties.length,
                  minHeight: 10,
                  color: AppColors.primary,
                  backgroundColor: colors.primaryContainer,
                ),
              ),
            ],
          ),
          table: [
            ('Done', '$dutiesDone'),
            ('Not done', '${_duties.length - dutiesDone}'),
          ],
        ),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          ChartCard(
            title: 'Most requested items',
            subtitle: 'What residents ask the lodge manager for',
            chart: CapacityBars(
              severity: false,
              rows: [
                for (final (n, c) in top)
                  (label: n, value: c, max: top.first.$2),
              ],
            ),
            table: [for (final (n, c) in top) (n, '$c')],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin dashboard'),
        actions: [
          IconButton(
            onPressed: _openBroadcastSheet,
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Broadcast',
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingView()
          : AppRefreshIndicator(
              onRefresh: () => _loadAll(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _insights(colors),
                  const SizedBox(height: 20),
                  _sectionHeading(colors, 'Repairs', 'Maintenance requests'),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    colors,
                    empty: _pendingMaintenance.isEmpty,
                    emptyLabel: 'No open requests — all caught up.',
                    rows: _pendingMaintenance.map((req) {
                      final rowKey = 'm-${req['request_id']}';
                      final busy = _busyId?.startsWith('$rowKey:') ?? false;
                      return _ActionRow(
                        title: req['title'] as String? ?? '',
                        subtitle:
                            '${req['priority'] ?? ''} priority · room #${req['room_id'] ?? '—'}',
                        actions: [
                          _smallOutlined(
                            'Start',
                            busy: busy,
                            spinning: _busyId == '$rowKey:in_progress',
                            onTap: () => _updateMaintenance(req, 'in_progress'),
                          ),
                          _smallDark(
                            colors,
                            'Resolve',
                            busy: busy,
                            spinning: _busyId == '$rowKey:resolved',
                            onTap: () => _updateMaintenance(req, 'resolved'),
                          ),
                        ],
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionHeading(
                    colors,
                    'Equipment',
                    'Pending equipment requests',
                  ),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    colors,
                    empty: _pendingEquipRequests.isEmpty,
                    emptyLabel: 'No pending requests.',
                    rows: _pendingEquipRequests.map((req) {
                      final rowKey = 'er-${req['equip_request_id']}';
                      final busy = _busyId?.startsWith('$rowKey:') ?? false;
                      return _ActionRow(
                        icon: Icons.build_outlined,
                        title:
                            req['equipment_name'] as String? ??
                            req['item_name'] as String? ??
                            'Equipment request',
                        actions: [
                          _smallOutlined(
                            'Reject',
                            busy: busy,
                            spinning: _busyId == '$rowKey:rejected',
                            onTap: () => _updateEquipRequest(req, 'rejected'),
                          ),
                          _smallDark(
                            colors,
                            'Approve',
                            busy: busy,
                            spinning: _busyId == '$rowKey:approved',
                            onTap: () => _updateEquipRequest(req, 'approved'),
                          ),
                        ],
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionHeading(colors, 'Equipment', 'Faulty item reports'),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    colors,
                    empty: _openEquipReports.isEmpty,
                    emptyLabel: 'No open reports.',
                    rows: _openEquipReports.map((rep) {
                      final rowKey = 'rep-${rep['eq_reports_id']}';
                      final busy = _busyId?.startsWith('$rowKey:') ?? false;
                      final isOpen = rep['status'] == 'open';
                      return _ActionRow(
                        icon: Icons.warning_amber_rounded,
                        iconColor: _amber,
                        title: rep['issue_description'] as String? ?? '',
                        actions: [
                          isOpen
                              ? _smallOutlined(
                                  'Start',
                                  busy: busy,
                                  spinning: _busyId == '$rowKey:in_progress',
                                  onTap: () =>
                                      _updateEquipReport(rep, 'in_progress'),
                                )
                              : _smallDark(
                                  colors,
                                  'Resolve',
                                  busy: busy,
                                  spinning: _busyId == '$rowKey:resolved',
                                  onTap: () =>
                                      _updateEquipReport(rep, 'resolved'),
                                ),
                        ],
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionHeading(colors, 'Chores', 'Duty roster'),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    colors,
                    empty: _duties.isEmpty,
                    emptyLabel: 'No duties assigned yet.',
                    rows: _duties.take(6).map((d) {
                      final status = d['status'] as String? ?? 'pending';
                      final statusColor = status == 'completed'
                          ? _green
                          : status == 'missed'
                          ? _red
                          : status == 'in_progress'
                          ? _amber
                          : Colors.grey;
                      return _ActionRow(
                        icon: Icons.checklist_outlined,
                        title: d['title'] as String? ?? '',
                        subtitle: (d['assigned_date'] as String?)
                            ?.split('T')
                            .first,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.6,
                    children: [
                      _quickLink(
                        colors,
                        'Roles & permissions',
                        Icons.admin_panel_settings_outlined,
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminRolesScreen(),
                          ),
                        ),
                      ),
                      _quickLink(
                        colors,
                        'Audit logs',
                        Icons.open_in_new,
                        _openAuditLogs,
                      ),
                      _quickLink(
                        colors,
                        'Manage rooms',
                        Icons.meeting_room_outlined,
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RoomsScreen(),
                          ),
                        ),
                      ),
                      _quickLink(
                        colors,
                        'Manage polls',
                        Icons.ramen_dining_outlined,
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PollsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeading(ColorScheme colors, String eyebrow, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    ColorScheme colors, {
    required bool empty,
    required String emptyLabel,
    required List<Widget> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: empty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  emptyLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1)
                    Divider(height: 1, color: colors.outlineVariant),
                ],
              ],
            ),
    );
  }

  Widget _smallOutlined(
    String label, {
    required bool busy,
    bool spinning = false,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          ),
        ),
        child: spinning
            ? SizedBox(
                width: 12,
                height: 12,
                child: AppLoader(
                  strokeWidth: 2,
                  color: colors.onSurfaceVariant,
                ),
              )
            : Text(
                label,
                style: TextStyle(fontSize: 11.5, color: colors.onSurface),
              ),
      ),
    );
  }

  Widget _smallDark(
    ColorScheme colors,
    String label, {
    required bool busy,
    bool spinning = false,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 30,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          ),
        ),
        child: spinning
            ? SizedBox(
                width: 12,
                height: 12,
                child: AppLoader(strokeWidth: 2, color: colors.surface),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.surface,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _quickLink(
    ColorScheme colors,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_forward, size: 13, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? trailing;

  const _ActionRow({
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.actions,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? colors.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (actions != null) ...[
            for (final a in actions!)
              Padding(padding: const EdgeInsets.only(left: 6), child: a),
          ],
        ],
      ),
    );
  }
}

/// --- Broadcast notification sheet ---
class _BroadcastSheet extends StatefulWidget {
  const _BroadcastSheet();

  @override
  State<_BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<_BroadcastSheet> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_titleController.text.trim().isEmpty ||
        _messageController.text.trim().isEmpty) {
      setState(() => _error = 'Title and message are required');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/notifications', {
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not send notification');
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
              'Broadcast notification',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: _decoration(colors, hint: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: _decoration(colors, hint: 'Message'),
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
                        'Send to all residents',
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
