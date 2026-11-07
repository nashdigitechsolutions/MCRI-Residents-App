import 'package:mcri_residents_app/widgets/text_prompt_dialog.dart';
import 'package:mcri_residents_app/widgets/app_loader.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/equipment.dart';
import '../models/equipment_report.dart';
import '../models/equipment_request.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/live_refresh.dart';

const _red = AppColors.danger;
const _accent = AppColors.primary;
const _amber = AppColors.warning;
const _green = AppColors.success;
const _orange = AppColors.primaryDark;
// Roles in the equipment workflow (must match the API's equipmentWorkflow.js).
const _lodgeManagerRoleId =
    1; // admin acts as lodge manager: buys requested items
const _caretakerRoleId = 4; // maintenance personnel: fixes reported faults

enum _Tab { browse, requests, manage, issues }

// Purchase requests: resident → lodge manager buys.
const _requestStatusMeta = {
  'pending': (
    label: 'Waiting for manager',
    color: _amber,
    icon: Icons.hourglass_top_rounded,
  ),
  'approved': (
    label: 'Approved · buying',
    color: _accent,
    icon: Icons.shopping_cart_outlined,
  ),
  'purchased': (
    label: 'Bought · collect it',
    color: _green,
    icon: Icons.inventory_2_outlined,
  ),
  'rejected': (label: 'Declined', color: _red, icon: Icons.cancel_outlined),
  'returned': (
    label: 'Returned',
    color: Colors.grey,
    icon: Icons.check_circle_outline,
  ),
};

// Fault reports: resident → maintenance fixes.
const _reportStatusMeta = {
  'open': (label: 'Reported', color: _red),
  'in_progress': (label: 'Being repaired', color: _amber),
  'resolved': (label: 'Fixed', color: _green),
};

class EquipmentScreen extends StatefulWidget {
  /// 'requests' or 'issues' to open a specific tab (from a notification).
  final String? initialTab;
  final int? highlightRequestId;
  final int? highlightReportId;

  const EquipmentScreen({
    super.key,
    this.initialTab,
    this.highlightRequestId,
    this.highlightReportId,
  });

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> with LiveRefresh {
  _Tab _tab = _Tab.browse;
  List<Equipment> _items = [];
  List<EquipmentRequest> _myRequests = [];
  List<EquipmentReport> _reports = [];
  Map<String, dynamic>? _caretaker;
  bool _loading = true;
  String _search = '';
  String? _category;
  int? _requestingId;
  int? _busyReqId;
  int? _busyReportId;
  // Which action is running on the busy card, so only that button spins.
  String? _busyAction;
  int? _sharingReportId;

  bool get _isAdmin =>
      context.read<AuthProvider>().user?.roleId == _lodgeManagerRoleId;
  bool get _isCaretaker =>
      context.read<AuthProvider>().user?.roleId == _caretakerRoleId;
  bool get _isStaff => _isAdmin || _isCaretaker;

  @override
  void initState() {
    super.initState();
    _tab = switch (widget.initialTab) {
      'requests' => _isAdmin ? _Tab.manage : _Tab.requests,
      'issues' => _Tab.issues,
      _ => _Tab.browse,
    };
    _loadAll();
    _loadCaretaker();
    // Request approvals, returns, fault reports and stock changes made by
    // anyone (admin, caretaker, other residents) appear live.
    listenLive(['equipment_updated'], () => _loadAll(showLoading: false));
  }

  Future<void> _loadAll({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final futures = <Future<dynamic>>[
        ApiService.get('/equipment'),
        _isCaretaker ? Future.value([]) : ApiService.get('/equipment-requests'),
        // Staff get every report; residents get their own (API-scoped).
        ApiService.get('/equipment-reports'),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _items = (results[0] as List)
            .map((j) => Equipment.fromJson(j as Map<String, dynamic>))
            .toList();
        _myRequests = (results[1] as List)
            .map((j) => EquipmentRequest.fromJson(j as Map<String, dynamic>))
            .toList();
        _reports = (results[2] as List)
            .map((j) => EquipmentReport.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (showLoading) _notify('Could not load equipment data', isError: true);
    }
  }

  Future<void> _loadCaretaker() async {
    if (!_isAdmin) return;
    try {
      final data = await ApiService.get('/users');
      final list = (data as List).cast<Map<String, dynamic>>();
      final ct = list
          .where(
            (u) =>
                (u['role_id'] is String
                    ? int.parse(u['role_id'])
                    : u['role_id']) ==
                _caretakerRoleId,
          )
          .firstOrNull;
      setState(() => _caretaker = ct);
    } catch (e) {
      // non-fatal
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

  List<String> get _categories {
    final set = <String>{};
    for (final i in _items) {
      if (i.category != null && i.category!.isNotEmpty) set.add(i.category!);
    }
    return set.toList();
  }

  List<Equipment> get _filtered {
    return _items.where((i) {
      final q = _search.toLowerCase();
      final matchesSearch =
          i.equipmentName.toLowerCase().contains(q) ||
          (i.category ?? '').toLowerCase().contains(q);
      final matchesCategory = _category == null || i.category == _category;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  Set<int> get _pendingRequestIds => _myRequests
      .where((r) => r.status == 'pending' || r.status == 'approved')
      .map((r) => r.equipmentId)
      .whereType<int>()
      .toSet();

  String _equipmentName(int id) {
    try {
      return _items.firstWhere((i) => i.equipmentId == id).equipmentName;
    } catch (_) {
      return 'Item #$id';
    }
  }

  /// "Ask the lodge manager to buy another one of this."
  Future<void> _requestItem(Equipment item) async {
    await _openRequestSheet(prefill: item);
  }

  /// Purchase request: a new item by name, or another of a catalogue item.
  Future<void> _openRequestSheet({Equipment? prefill}) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestEquipmentSheet(item: prefill),
    );
    if (sent == true && mounted) {
      _notify('Request sent to the lodge manager');
      setState(() => _tab = _isAdmin ? _Tab.manage : _Tab.requests);
      _loadAll(showLoading: false);
    }
  }

  /// Ask for an optional note (shown to the resident in their notification).
  Future<String?> _askNote({
    required String title,
    required String hint,
    required String confirm,
  }) => showTextPrompt(
    context,
    title: title,
    hint: hint,
    confirmLabel: confirm,
    maxLines: 3,
    maxLength: 300,
  );

  Future<void> _cancelRequest(EquipmentRequest req) async {
    try {
      await ApiService.delete('/equipment-requests/${req.equipRequestId}');
      _notify('Request cancelled');
      _loadAll();
    } catch (e) {
      _notify('Could not cancel request', isError: true);
    }
  }

  /// Lodge manager: approve → buying, mark bought, or decline (with note).
  Future<void> _setRequestStatus(EquipmentRequest req, String status) async {
    String? note;
    if (status == 'rejected' || status == 'purchased') {
      note = await _askNote(
        title: status == 'rejected'
            ? 'Decline ${req.displayName}?'
            : 'Mark ${req.displayName} as bought',
        hint: status == 'rejected'
            ? 'Reason (optional) — the resident will see this'
            : 'Where to collect it (optional)',
        confirm: status == 'rejected' ? 'Decline' : 'Mark bought',
      );
      if (note == null) return; // cancelled
    }
    setState(() {
      _busyReqId = req.equipRequestId;
      _busyAction = status;
    });
    try {
      await ApiService.patch('/equipment-requests/${req.equipRequestId}', {
        'status': status,
        if (note != null && note.isNotEmpty) 'manager_note': note,
      });
      _notify(switch (status) {
        'approved' =>
          'Approved — ${req.username ?? 'the resident'} has been told you\'re buying it',
        'purchased' => 'Marked as bought — the resident has been notified',
        'rejected' => 'Request declined',
        _ => 'Request updated',
      });
      await _loadAll(showLoading: false);
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('Could not update request', isError: true);
    } finally {
      if (mounted) setState(() => _busyReqId = null);
    }
  }

  /// Maintenance: start the repair, or mark it fixed (with note).
  Future<void> _setReportStatus(EquipmentReport rep, String status) async {
    String? note;
    if (status == 'resolved') {
      note = await _askNote(
        title: 'Mark as fixed',
        hint: 'What was done (optional) — the resident will see this',
        confirm: 'Mark fixed',
      );
      if (note == null) return;
    }
    setState(() {
      _busyReportId = rep.eqReportsId;
      _busyAction = status;
    });
    try {
      await ApiService.patch('/equipment-reports/${rep.eqReportsId}', {
        'status': status,
        if (note != null && note.isNotEmpty) 'resolution_note': note,
      });
      _notify(
        status == 'resolved'
            ? 'Marked fixed — the resident has been notified'
            : 'Repair started — the resident has been notified',
      );
      await _loadAll(showLoading: false);
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('Could not update issue', isError: true);
    } finally {
      if (mounted) setState(() => _busyReportId = null);
    }
  }

  Future<void> _shareReportToCaretaker(EquipmentReport rep) async {
    if (_caretaker == null) {
      _notify('No caretaker account found to share with', isError: true);
      return;
    }
    setState(() => _sharingReportId = rep.eqReportsId);
    final equipName = rep.equipmentName ?? _equipmentName(rep.equipmentId);
    final text =
        '🔧 Equipment issue reported\n'
        'Item: $equipName\n'
        'Issue: ${rep.issueDescription}\n'
        'Reported: ${DateFormat.yMd().add_jm().format(rep.createdAt)}';

    try {
      final caretakerId = _caretaker!['user_id'] is String
          ? int.parse(_caretaker!['user_id'])
          : _caretaker!['user_id'] as int;
      final convData = await ApiService.post('/conversations', {
        'is_group': false,
        'member_ids': [caretakerId],
      });
      final convId = convData['conversation']['conversation_id'] is String
          ? int.parse(convData['conversation']['conversation_id'])
          : convData['conversation']['conversation_id'] as int;
      await ApiService.post('/conversations/$convId/messages', {
        'message': text,
      });
      _notify('Shared with caretaker');
    } catch (e) {
      _notify('Could not share with caretaker', isError: true);
    } finally {
      setState(() => _sharingReportId = null);
    }
  }

  List<({_Tab key, String label})> get _tabs {
    final list = <({_Tab key, String label})>[
      (key: _Tab.browse, label: 'Browse'),
    ];
    String count(int n) => n > 0 ? ' ($n)' : '';
    final pendingBuys = _myRequests
        .where((r) => r.status == 'pending' || r.status == 'approved')
        .length;
    final openFaults = _reports.where((r) => r.status != 'resolved').length;
    if (_isAdmin) {
      // Lodge manager: buys what residents ask for, oversees repairs.
      list.add((
        key: _Tab.manage,
        label: 'Purchase requests${count(pendingBuys)}',
      ));
      list.add((key: _Tab.issues, label: 'Repairs${count(openFaults)}'));
    } else if (_isCaretaker) {
      // Maintenance personnel: fixes reported faults.
      list.add((key: _Tab.issues, label: 'Repairs${count(openFaults)}'));
    } else {
      list.add((key: _Tab.requests, label: 'My requests${count(pendingBuys)}'));
      list.add((key: _Tab.issues, label: 'My reports${count(openFaults)}'));
    }
    return list;
  }

  void _openItemDetail(Equipment item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EquipmentDetailSheet(
        item: item,
        isStaff: _isStaff,
        alreadyRequested: _pendingRequestIds.contains(item.equipmentId),
        requesting: _requestingId == item.equipmentId,
        onRequest: () => _requestItem(item),
        onReport: () => _openReportSheet(item),
      ),
    );
  }

  Future<void> _openReportSheet(Equipment item) async {
    Navigator.of(context).maybePop(); // close detail sheet if open beneath
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportIssueSheet(item: item),
    );
    if (submitted == true) {
      _notify("Reported to maintenance — we'll let you know when it's fixed");
      if (mounted) setState(() => _tab = _Tab.issues);
      _loadAll(showLoading: false);
    }
  }

  Future<void> _openAddEquipmentSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddEquipmentSheet(),
    );
    if (created == true) {
      _notify('Equipment added');
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!_tabs.any((t) => t.key == _tab)) _tab = _Tab.browse;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment'),
        // Anyone can add an item to the shared list.
        actions: [
          IconButton(
            onPressed: _openAddEquipmentSheet,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add equipment to the list',
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingView()
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Scrolls sideways when the role's tab names don't fit.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _tabs
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: GestureDetector(
                                  onTap: () => setState(() => _tab = t.key),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _tab == t.key
                                          ? colors.surface
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      t.label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: _tab == t.key
                                            ? colors.onSurface
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == _Tab.browse) ..._buildBrowse(colors),
                  if (_tab == _Tab.requests) ..._buildMyRequests(colors),
                  if (_tab == _Tab.manage) ..._buildManage(colors),
                  if (_tab == _Tab.issues) ..._buildIssues(colors),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildBrowse(ColorScheme colors) {
    final items = _filtered;
    return [
      TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search equipment…',
          prefixIcon: Icon(
            Icons.search,
            size: 19,
            color: colors.onSurfaceVariant,
          ),
          filled: true,
          fillColor: colors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: _accent),
          ),
        ),
      ),
      if (_categories.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryChip(
                label: 'All',
                selected: _category == null,
                onTap: () => setState(() => _category = null),
              ),
              for (final c in _categories) ...[
                const SizedBox(width: 6),
                _CategoryChip(
                  label: c,
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      if (items.isEmpty)
        _emptyState(
          colors,
          'No equipment found',
          _isAdmin
              ? 'Add the first item with the button above.'
              : 'Try a different search or category.',
        )
      else
        for (final item in items)
          _EquipmentCard(
            item: item,
            isStaff: _isStaff,
            alreadyRequested: _pendingRequestIds.contains(item.equipmentId),
            requesting: _requestingId == item.equipmentId,
            onTap: () => _openItemDetail(item),
            onRequest: () => _requestItem(item),
            onReport: () => _openReportSheet(item),
          ),
    ];
  }

  // ───────────────────── Purchase requests & repairs ─────────────────────

  Widget _newRequestButton() => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: () => _openRequestSheet(),
      icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
      label: const Text('Request equipment'),
    ),
  );

  Widget _hint(ColorScheme colors, IconData icon, String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: _accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
      ],
    ),
  );

  /// Three-step tracker: Requested → Approved → Bought (or Reported →
  /// Repairing → Fixed). Declined requests show a single red step.
  Widget _steps(
    ColorScheme colors,
    List<String> labels,
    int reached, {
    bool failed = false,
  }) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: !failed && i <= reached
                    ? _accent
                    : colors.outlineVariant,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: failed && i == 0
                      ? _red
                      : (!failed && i <= reached ? _accent : colors.surface),
                  border: Border.all(
                    color: failed && i == 0
                        ? _red
                        : (!failed && i <= reached ? _accent : colors.outline),
                    width: 1.5,
                  ),
                ),
                child: (failed && i == 0) || (!failed && i <= reached)
                    ? Icon(
                        failed ? Icons.close_rounded : Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                failed && i == 0 ? 'Declined' : labels[i],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: !failed && i == reached
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: !failed && i <= reached
                      ? colors.onSurface
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  int _requestStep(String s) => switch (s) {
    'approved' => 1,
    'purchased' || 'returned' => 2,
    _ => 0,
  };

  int _reportStep(String s) => switch (s) {
    'in_progress' => 1,
    'resolved' => 2,
    _ => 0,
  };

  BoxDecoration _cardDecoration(ColorScheme colors, {bool highlight = false}) =>
      BoxDecoration(
        color: highlight ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: highlight ? _accent : colors.outlineVariant,
          width: highlight ? 1.5 : 1,
        ),
      );

  Widget _noteLine(ColorScheme colors, String label, String note) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: note),
          ],
        ),
        style: TextStyle(fontSize: 12, height: 1.35, color: colors.onSurface),
      ),
    ),
  );

  Widget _requestCard(
    ColorScheme colors,
    EquipmentRequest req, {
    required bool manager,
  }) {
    final meta =
        _requestStatusMeta[req.status] ?? _requestStatusMeta['pending']!;
    final busy = _busyReqId == req.equipRequestId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        colors,
        highlight: widget.highlightRequestId == req.equipRequestId,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusIconBadge(meta),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${req.quantity > 1 ? '${req.quantity} × ' : ''}${req.displayName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${manager && req.username != null ? '${req.username} · ' : ''}${DateFormat('d MMM, HH:mm').format(req.requestDate)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill((label: meta.label, color: meta.color)),
            ],
          ),
          if (req.reason != null && req.reason!.isNotEmpty)
            _noteLine(colors, 'Why', req.reason!),
          if (req.managerNote != null && req.managerNote!.isNotEmpty)
            _noteLine(colors, 'Manager', req.managerNote!),
          const SizedBox(height: 12),
          _steps(
            colors,
            const ['Requested', 'Approved', 'Bought'],
            _requestStep(req.status),
            failed: req.status == 'rejected',
          ),
          if (manager &&
              (req.status == 'pending' || req.status == 'approved')) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (req.status == 'pending')
                  _smallButton(
                    'Approve & buy',
                    dark: true,
                    busy: busy,
                    spinning: busy && _busyAction == 'approved',
                    onTap: () => _setRequestStatus(req, 'approved'),
                  ),
                if (req.status == 'approved')
                  _smallButton(
                    'Mark bought',
                    dark: true,
                    busy: busy,
                    spinning: busy && _busyAction == 'purchased',
                    onTap: () => _setRequestStatus(req, 'purchased'),
                  ),
                _smallButton(
                  'Decline',
                  dark: false,
                  busy: busy,
                  spinning: busy && _busyAction == 'rejected',
                  onTap: () => _setRequestStatus(req, 'rejected'),
                ),
              ],
            ),
          ],
          if (!manager && req.status == 'pending') ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _cancelRequest(req),
                style: TextButton.styleFrom(
                  foregroundColor: _red,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Cancel request'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildMyRequests(ColorScheme colors) {
    return [
      _hint(
        colors,
        Icons.shopping_bag_outlined,
        'Need something for the residence? Ask the lodge manager to buy it. '
        "You'll be notified when it's approved and when it's bought.",
      ),
      _newRequestButton(),
      const SizedBox(height: 16),
      if (_myRequests.isEmpty)
        _emptyState(
          colors,
          'No requests yet',
          'Tap "Request equipment" to ask for something.',
        )
      else
        for (final req in _myRequests)
          _requestCard(colors, req, manager: false),
    ];
  }

  List<Widget> _buildManage(ColorScheme colors) {
    final open = _myRequests
        .where((r) => r.status == 'pending' || r.status == 'approved')
        .toList();
    final done = _myRequests.where((r) => !open.contains(r)).toList();
    return [
      _hint(
        colors,
        Icons.shopping_cart_outlined,
        'Residents ask you to buy these. Approve to let them know you\'re buying it, '
        'then mark it bought once it\'s ready to collect.',
      ),
      if (_myRequests.isEmpty)
        _emptyState(
          colors,
          'No purchase requests',
          'Resident requests will appear here.',
        )
      else ...[
        if (open.isNotEmpty) ...[
          _sectionLabel(colors, 'To do · ${open.length}'),
          for (final req in open) _requestCard(colors, req, manager: true),
        ],
        if (done.isNotEmpty) ...[
          _sectionLabel(colors, 'Done'),
          for (final req in done) _requestCard(colors, req, manager: true),
        ],
      ],
    ];
  }

  Widget _sectionLabel(ColorScheme colors, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _accent,
      ),
    ),
  );

  Widget _reportCard(
    ColorScheme colors,
    EquipmentReport rep, {
    required bool staff,
  }) {
    final meta = _reportStatusMeta[rep.status] ?? _reportStatusMeta['open']!;
    final busy = _busyReportId == rep.eqReportsId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        colors,
        highlight: widget.highlightReportId == rep.eqReportsId,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  rep.status == 'resolved'
                      ? Icons.check_rounded
                      : Icons.build_rounded,
                  size: 16,
                  color: meta.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rep.equipmentName ?? _equipmentName(rep.equipmentId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${staff && rep.reporterName != null ? '${rep.reporterName} · ' : ''}${DateFormat('d MMM, HH:mm').format(rep.createdAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill((label: meta.label, color: meta.color)),
            ],
          ),
          _noteLine(colors, 'Fault', rep.issueDescription),
          if (rep.resolutionNote != null && rep.resolutionNote!.isNotEmpty)
            _noteLine(colors, 'Maintenance', rep.resolutionNote!),
          const SizedBox(height: 12),
          _steps(colors, const [
            'Reported',
            'Repairing',
            'Fixed',
          ], _reportStep(rep.status)),
          if (staff && rep.status != 'resolved') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (rep.status == 'open')
                  _smallButton(
                    'Start repair',
                    dark: false,
                    busy: busy,
                    spinning: busy && _busyAction == 'in_progress',
                    onTap: () => _setReportStatus(rep, 'in_progress'),
                  ),
                _smallButton(
                  'Mark fixed',
                  dark: true,
                  busy: busy,
                  spinning: busy && _busyAction == 'resolved',
                  onTap: () => _setReportStatus(rep, 'resolved'),
                ),
                if (_isAdmin)
                  _smallButton(
                    'Message maintenance',
                    dark: false,
                    busy: _sharingReportId == rep.eqReportsId,
                    onTap: () => _shareReportToCaretaker(rep),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildIssues(ColorScheme colors) {
    final staff = _isStaff;
    final open = _reports.where((r) => r.status != 'resolved').toList();
    final fixed = _reports.where((r) => r.status == 'resolved').toList();
    return [
      _hint(
        colors,
        Icons.build_circle_outlined,
        staff
            ? 'Faults reported by residents. Start the repair so they know it\'s being handled, then mark it fixed.'
            : 'Something broken? Open it in Browse and tap "Report a fault" — maintenance will be alerted.',
      ),
      if (_reports.isEmpty)
        _emptyState(
          colors,
          staff ? 'Nothing to repair' : 'No reports yet',
          staff
              ? 'Reported faults will appear here.'
              : 'Faults you report will show up here.',
        )
      else ...[
        if (open.isNotEmpty) ...[
          _sectionLabel(
            colors,
            '${staff ? 'To fix' : 'Open'} · ${open.length}',
          ),
          for (final rep in open) _reportCard(colors, rep, staff: staff),
        ],
        if (fixed.isNotEmpty) ...[
          _sectionLabel(colors, 'Fixed'),
          for (final rep in fixed) _reportCard(colors, rep, staff: staff),
        ],
      ],
    ];
  }

  Widget _emptyState(ColorScheme colors, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.build_outlined, size: 30, color: colors.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _statusPill(({String label, Color color}) meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: meta.color,
        ),
      ),
    );
  }

  Widget _statusIconBadge(({String label, Color color, IconData icon}) meta) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(meta.icon, size: 16, color: meta.color),
    );
  }

  Widget _smallButton(
    String label, {
    required bool dark,
    required bool busy,
    bool? spinning,
    required VoidCallback onTap,
  }) {
    // busy disables the button; only the tapped one shows the loader.
    final showSpinner = spinning ?? busy;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: dark ? colors.onSurface : Colors.transparent,
          side: BorderSide(
            color: dark ? colors.onSurface : colors.outlineVariant,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          ),
        ),
        child: showSpinner
            ? SizedBox(
                width: 14,
                height: 14,
                child: AppLoader(
                  strokeWidth: 2,
                  color: dark ? colors.surface : colors.onSurfaceVariant,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dark ? colors.surface : colors.onSurface,
                ),
              ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.onSurface : Colors.transparent,
          border: Border.all(
            color: selected ? colors.onSurface : colors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? colors.surface : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  final Equipment item;
  final bool isStaff;
  final bool alreadyRequested;
  final bool requesting;
  final VoidCallback onTap;
  final VoidCallback onRequest;
  final VoidCallback onReport;

  const _EquipmentCard({
    required this.item,
    required this.isStaff,
    required this.alreadyRequested,
    required this.requesting,
    required this.onTap,
    required this.onRequest,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusMeta = _equipmentStatusMeta[item.status]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.equipmentName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _statusDot(statusMeta),
                        const SizedBox(width: 8),
                        if (item.category != null)
                          Text(
                            item.category!,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isStaff && !alreadyRequested)
                    SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        onPressed: requesting ? null : onRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.onSurface,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.sm + 2,
                            ),
                          ),
                        ),
                        child: requesting
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: AppLoader(
                                  strokeWidth: 2,
                                  color: colors.surface,
                                ),
                              )
                            : Text(
                                'Ask to buy',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.surface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  if (!isStaff && alreadyRequested)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Asked to buy',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _amber,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onReport,
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 12,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Report fault',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot(({String label, Color color}) meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: meta.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            meta.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: meta.color,
            ),
          ),
        ],
      ),
    );
  }
}

const _equipmentStatusMeta = {
  EquipmentStatus.available: (label: 'Available', color: _green),
  EquipmentStatus.inUse: (label: 'In use', color: _amber),
  EquipmentStatus.reserved: (label: 'Reserved', color: _accent),
  EquipmentStatus.maintenance: (label: 'Under maintenance', color: _orange),
  EquipmentStatus.retired: (label: 'Retired', color: Colors.grey),
};

/// --- The requested "pop up view": full detail sheet for one item ---
class _EquipmentDetailSheet extends StatelessWidget {
  final Equipment item;
  final bool isStaff;
  final bool alreadyRequested;
  final bool requesting;
  final VoidCallback onRequest;
  final VoidCallback onReport;

  const _EquipmentDetailSheet({
    required this.item,
    required this.isStaff,
    required this.alreadyRequested,
    required this.requesting,
    required this.onRequest,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusMeta = _equipmentStatusMeta[item.status]!;

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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusMeta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.build_outlined,
                  color: statusMeta.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.equipmentName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusMeta.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusMeta.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusMeta.color,
                          ),
                        ),
                        if (item.category != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· ${item.category}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: colors.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onReport();
                    },
                    icon: const Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: _red,
                    ),
                    label: const Text(
                      'Report a fault',
                      style: TextStyle(color: _red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                      ),
                    ),
                  ),
                ),
              ),
              if (!isStaff && !alreadyRequested) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: requesting
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              onRequest();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.onSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                        ),
                      ),
                      child: requesting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: AppLoader(
                                strokeWidth: 2,
                                color: colors.surface,
                              ),
                            )
                          : Text(
                              'Ask to buy one',
                              style: TextStyle(
                                color: colors.surface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// --- Add equipment sheet ---
class _AddEquipmentSheet extends StatefulWidget {
  const _AddEquipmentSheet();

  @override
  State<_AddEquipmentSheet> createState() => _AddEquipmentSheetState();
}

class _AddEquipmentSheetState extends State<_AddEquipmentSheet> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_nameController.text.trim().length < 2) {
      setState(() => _error = 'Give the equipment a name');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/equipment', {
        'equipment_name': _nameController.text.trim(),
        if (_categoryController.text.trim().isNotEmpty)
          'category': _categoryController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not add equipment');
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
              'Add equipment',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: _decoration(colors, hint: 'e.g. Vacuum cleaner'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: _decoration(
                colors,
                hint: 'Category (optional), e.g. cleaning',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: _decoration(colors, hint: 'Description (optional)'),
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
                        'Add equipment',
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

/// --- Report issue sheet ---
class _ReportIssueSheet extends StatefulWidget {
  final Equipment item;
  const _ReportIssueSheet({required this.item});

  @override
  State<_ReportIssueSheet> createState() => _ReportIssueSheetState();
}

class _ReportIssueSheetState extends State<_ReportIssueSheet> {
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Describe the issue first');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/equipment-reports', {
        'equipment_id': widget.item.equipmentId,
        'issue_description': _descriptionController.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not submit report');
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
              'Report an issue',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            Text(
              widget.item.equipmentName,
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: _decoration(colors, hint: "What's wrong with it?"),
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
                        'Submit report',
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
    );
  }
}

/// --- Purchase request sheet ---
/// A resident asks the lodge manager to buy something: either a new item by
/// name, or another one of a catalogue item ([item]).
class _RequestEquipmentSheet extends StatefulWidget {
  final Equipment? item;
  const _RequestEquipmentSheet({this.item});

  @override
  State<_RequestEquipmentSheet> createState() => _RequestEquipmentSheetState();
}

class _RequestEquipmentSheetState extends State<_RequestEquipmentSheet> {
  late final _name = TextEditingController(
    text: widget.item?.equipmentName ?? '',
  );
  final _reason = TextEditingController();
  int _quantity = 1;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (widget.item == null && name.isEmpty) {
      setState(() => _error = 'What do you need?');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ApiService.post('/equipment-requests', {
        if (widget.item != null) 'equipment_id': widget.item!.equipmentId,
        if (name.isNotEmpty) 'item_name': name,
        if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        'quantity': _quantity,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send request');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                const Text(
                  'PURCHASE REQUEST',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.item == null
                      ? 'What do you need?'
                      : 'Request another ${widget.item!.equipmentName}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The lodge manager will review it, buy it, and let you know when it\'s ready.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                if (widget.item == null) ...[
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 150,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      hintText: 'e.g. Kettle, iron, extension cord',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Text(
                      'Quantity',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton.outlined(
                      onPressed: _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$_quantity',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: _quantity < 50
                          ? () => setState(() => _quantity++)
                          : null,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  maxLines: 3,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Why do you need it? (optional)',
                    hintText: 'Helps the manager decide quickly',
                    counterText: '',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: _red, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: AppLoader(color: Colors.white),
                          )
                        : const Text('Send to lodge manager'),
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
