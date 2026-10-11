import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'audit_logs_webview_screen.dart';
import '../rooms_screen.dart';
import '../polls_screen.dart';
import 'admin_roles_screen.dart';

const _red = Color(0xFFEF4444);
const _accent = Color(0xFF3355FF);
const _amber = Color(0xFFD97706);
const _green = Color(0xFF10B981);

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
      ]);
      setState(() {
        _maintenance = (results[0] as List).cast<Map<String, dynamic>>();
        _equipRequests = (results[1] as List).cast<Map<String, dynamic>>();
        _equipReports = (results[2] as List).cast<Map<String, dynamic>>();
        _duties = (results[3] as List).cast<Map<String, dynamic>>();
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
  List<Map<String, dynamic>> get _pendingDuties =>
      _duties.where((d) => d['status'] == 'pending').toList();

  Future<void> _updateMaintenance(
    Map<String, dynamic> req,
    String status,
  ) async {
    final id = req['request_id'] is String
        ? int.parse(req['request_id'])
        : req['request_id'] as int;
    setState(() => _busyId = 'm-$id');
    try {
      await ApiService.patch('/maintenance-requests/$id', {'status': status});
      _notify('Request updated');
      _loadAll(showLoading: false);
    } catch (e) {
      _notify('Update failed', isError: true);
    } finally {
      setState(() => _busyId = null);
    }
  }

  Future<void> _updateEquipRequest(
    Map<String, dynamic> req,
    String status,
  ) async {
    final id = req['equip_request_id'] is String
        ? int.parse(req['equip_request_id'])
        : req['equip_request_id'] as int;
    setState(() => _busyId = 'er-$id');
    try {
      await ApiService.patch('/equipment-requests/$id', {'status': status});
      _notify('Request updated');
      _loadAll(showLoading: false);
    } catch (e) {
      _notify('Update failed', isError: true);
    } finally {
      setState(() => _busyId = null);
    }
  }

  Future<void> _updateEquipReport(
    Map<String, dynamic> rep,
    String status,
  ) async {
    final id = rep['eq_reports_id'] is String
        ? int.parse(rep['eq_reports_id'])
        : rep['eq_reports_id'] as int;
    setState(() => _busyId = 'rep-$id');
    try {
      await ApiService.patch('/equipment-reports/$id', {'status': status});
      _notify('Report updated');
      _loadAll(showLoading: false);
    } catch (e) {
      _notify('Update failed', isError: true);
    } finally {
      setState(() => _busyId = null);
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
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadAll(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- stat strip ---
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          value: '${_pendingMaintenance.length}',
                          label: 'Open repairs',
                          color: _red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          value: '${_pendingEquipRequests.length}',
                          label: 'Equip. requests',
                          color: _amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          value: '${_openEquipReports.length}',
                          label: 'Equip. reports',
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          value: '${_pendingDuties.length}',
                          label: 'Pending duties',
                          color: _green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _sectionHeading(colors, 'Repairs', 'Maintenance requests'),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    colors,
                    empty: _pendingMaintenance.isEmpty,
                    emptyLabel: 'No open requests — all caught up.',
                    rows: _pendingMaintenance.map((req) {
                      final busy = _busyId == 'm-${req['request_id']}';
                      return _ActionRow(
                        title: req['title'] as String? ?? '',
                        subtitle:
                            '${req['priority'] ?? ''} priority · room #${req['room_id'] ?? '—'}',
                        actions: [
                          _smallOutlined(
                            'Start',
                            busy: busy,
                            onTap: () => _updateMaintenance(req, 'in_progress'),
                          ),
                          _smallDark(
                            colors,
                            'Resolve',
                            busy: busy,
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
                      final busy = _busyId == 'er-${req['equip_request_id']}';
                      return _ActionRow(
                        icon: Icons.build_outlined,
                        title:
                            req['equipment_name'] as String? ??
                            'Item #${req['equipment_id']}',
                        actions: [
                          _smallOutlined(
                            'Reject',
                            busy: busy,
                            onTap: () => _updateEquipRequest(req, 'rejected'),
                          ),
                          _smallDark(
                            colors,
                            'Approve',
                            busy: busy,
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
                      final busy = _busyId == 'rep-${rep['eq_reports_id']}';
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
                                  onTap: () =>
                                      _updateEquipReport(rep, 'in_progress'),
                                )
                              : _smallDark(
                                  colors,
                                  'Resolve',
                                  busy: busy,
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
        borderRadius: BorderRadius.circular(16),
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
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
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
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.surface,
                ),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
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

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
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
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
            ],
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
