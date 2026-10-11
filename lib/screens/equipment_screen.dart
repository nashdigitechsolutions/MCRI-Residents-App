import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/equipment.dart';
import '../models/equipment_report.dart';
import '../models/equipment_request.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

const _red = Color(0xFFEF4444);
const _accent = Color(0xFF3355FF);
const _amber = Color(0xFFD97706);
const _green = Color(0xFF10B981);
const _orange = Color(0xFFEA580C);
const _caretakerRoleId = 4;

enum _Tab { browse, requests, manage, issues }

const _requestStatusMeta = {
  'pending': (label: 'Pending', color: _amber, icon: Icons.access_time),
  'approved': (
    label: 'Approved',
    color: _green,
    icon: Icons.check_circle_outline,
  ),
  'rejected': (label: 'Rejected', color: _red, icon: Icons.cancel_outlined),
  'returned': (
    label: 'Returned',
    color: Colors.grey,
    icon: Icons.check_circle_outline,
  ),
};

const _reportStatusMeta = {
  'open': (label: 'Open', color: _red),
  'in_progress': (label: 'In progress', color: _amber),
  'resolved': (label: 'Resolved', color: _green),
};

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
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
  int? _sharingReportId;

  bool get _isAdmin => context.read<AuthProvider>().user?.roleId == 1;
  bool get _isCaretaker =>
      context.read<AuthProvider>().user?.roleId == _caretakerRoleId;
  bool get _isStaff => _isAdmin || _isCaretaker;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadCaretaker();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final futures = <Future<dynamic>>[
        ApiService.get('/equipment'),
        _isCaretaker ? Future.value([]) : ApiService.get('/equipment-requests'),
        _isStaff ? ApiService.get('/equipment-reports') : Future.value([]),
      ];
      final results = await Future.wait(futures);
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
      setState(() => _loading = false);
      if (mounted) _notify('Could not load equipment data', isError: true);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        margin: const EdgeInsets.only(bottom: 24, left: 60, right: 60),
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
      .where((r) => r.status == 'pending')
      .map((r) => r.equipmentId)
      .toSet();

  String _equipmentName(int id) {
    try {
      return _items.firstWhere((i) => i.equipmentId == id).equipmentName;
    } catch (_) {
      return 'Item #$id';
    }
  }

  Future<void> _requestItem(Equipment item) async {
    setState(() => _requestingId = item.equipmentId);
    try {
      await ApiService.post('/equipment-requests', {
        'equipment_id': item.equipmentId,
      });
      _notify('Request sent for ${item.equipmentName}');
      await _loadAll();
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('Failed to request item', isError: true);
    } finally {
      setState(() => _requestingId = null);
    }
  }

  Future<void> _cancelRequest(EquipmentRequest req) async {
    try {
      await ApiService.delete('/equipment-requests/${req.equipRequestId}');
      _notify('Request cancelled');
      _loadAll();
    } catch (e) {
      _notify('Could not cancel request', isError: true);
    }
  }

  Future<void> _setRequestStatus(EquipmentRequest req, String status) async {
    setState(() => _busyReqId = req.equipRequestId);
    try {
      await ApiService.patch('/equipment-requests/${req.equipRequestId}', {
        'status': status,
      });
      _notify('Request $status');
      await _loadAll();
    } catch (e) {
      _notify('Could not update request', isError: true);
    } finally {
      setState(() => _busyReqId = null);
    }
  }

  Future<void> _setReportStatus(EquipmentReport rep, String status) async {
    setState(() => _busyReportId = rep.eqReportsId);
    try {
      await ApiService.patch('/equipment-reports/${rep.eqReportsId}', {
        'status': status,
      });
      _notify('Issue marked ${_reportStatusMeta[status]?.label ?? status}');
      await _loadAll();
    } catch (e) {
      _notify('Could not update issue', isError: true);
    } finally {
      setState(() => _busyReportId = null);
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
    if (_isAdmin) {
      list.add((
        key: _Tab.manage,
        label:
            'Requests${_myRequests.isNotEmpty ? ' (${_myRequests.length})' : ''}',
      ));
      list.add((
        key: _Tab.issues,
        label: 'Issues${_reports.isNotEmpty ? ' (${_reports.length})' : ''}',
      ));
    } else if (_isCaretaker) {
      list.add((
        key: _Tab.issues,
        label: 'Issues${_reports.isNotEmpty ? ' (${_reports.length})' : ''}',
      ));
    } else {
      list.add((
        key: _Tab.requests,
        label:
            'My requests${_myRequests.isNotEmpty ? ' (${_myRequests.length})' : ''}',
      ));
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
      _notify("Issue reported — thanks for letting us know");
      if (_isStaff) _loadAll();
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
        actions: _isAdmin
            ? [
                IconButton(
                  onPressed: _openAddEquipmentSheet,
                  icon: const Icon(Icons.add),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
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

  List<Widget> _buildMyRequests(ColorScheme colors) {
    if (_myRequests.isEmpty) {
      return [
        _emptyState(
          colors,
          'No requests yet',
          'Items you request will show up here.',
        ),
      ];
    }
    return [
      for (final req in _myRequests)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              _statusIconBadge(_requestStatusMeta[req.status]!),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.equipmentName ?? _equipmentName(req.equipmentId),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      'Requested ${DateFormat.yMd().format(req.requestDate)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill((
                label: _requestStatusMeta[req.status]!.label,
                color: _requestStatusMeta[req.status]!.color,
              )),
              if (req.status == 'pending') ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _cancelRequest(req),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildManage(ColorScheme colors) {
    if (_myRequests.isEmpty) {
      return [
        _emptyState(
          colors,
          'No requests to manage',
          'Resident requests will appear here for approval.',
        ),
      ];
    }
    return [
      for (final req in _myRequests)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                req.equipmentName ?? _equipmentName(req.equipmentId),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${req.username != null ? 'From @${req.username} · ' : ''}${DateFormat.yMd().format(req.requestDate)}',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              _statusPill((
                label: _requestStatusMeta[req.status]!.label,
                color: _requestStatusMeta[req.status]!.color,
              )),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (req.status == 'pending') ...[
                    _smallButton(
                      'Approve',
                      dark: true,
                      busy: _busyReqId == req.equipRequestId,
                      onTap: () => _setRequestStatus(req, 'approved'),
                    ),
                    const SizedBox(width: 8),
                    _smallButton(
                      'Reject',
                      dark: false,
                      busy: _busyReqId == req.equipRequestId,
                      onTap: () => _setRequestStatus(req, 'rejected'),
                    ),
                  ],
                  if (req.status == 'approved')
                    _smallButton(
                      'Mark returned',
                      dark: false,
                      busy: _busyReqId == req.equipRequestId,
                      onTap: () => _setRequestStatus(req, 'returned'),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildIssues(ColorScheme colors) {
    if (_reports.isEmpty) {
      return [
        _emptyState(
          colors,
          'No issues reported',
          'Reported equipment problems will appear here.',
        ),
      ];
    }
    return [
      for (final rep in _reports)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
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
                  Expanded(
                    child: Text(
                      rep.equipmentName ?? _equipmentName(rep.equipmentId),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _statusPill((
                    label: _reportStatusMeta[rep.status]!.label,
                    color: _reportStatusMeta[rep.status]!.color,
                  )),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                rep.issueDescription,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                'Reported ${DateFormat.yMd().add_jm().format(rep.createdAt)}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (rep.status != 'in_progress' && rep.status != 'resolved')
                    _smallButton(
                      'Start',
                      dark: false,
                      busy: _busyReportId == rep.eqReportsId,
                      onTap: () => _setReportStatus(rep, 'in_progress'),
                    ),
                  if (rep.status != 'resolved')
                    _smallButton(
                      'Resolve',
                      dark: true,
                      busy: _busyReportId == rep.eqReportsId,
                      onTap: () => _setReportStatus(rep, 'resolved'),
                    ),
                  if (_isAdmin)
                    _smallButton(
                      'Share to caretaker',
                      dark: false,
                      busy: _sharingReportId == rep.eqReportsId,
                      onTap: () => _shareReportToCaretaker(rep),
                    ),
                ],
              ),
            ],
          ),
        ),
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
    required VoidCallback onTap,
  }) {
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
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                  if (!isStaff &&
                      item.status == EquipmentStatus.available &&
                      !alreadyRequested)
                    SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        onPressed: requesting ? null : onRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.onSurface,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: requesting
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.surface,
                                ),
                              )
                            : Text(
                                'Request',
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
                        'Requested',
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
                          'Report',
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                  borderRadius: BorderRadius.circular(14),
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
                      'Report issue',
                      style: TextStyle(color: _red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              if (!isStaff &&
                  item.status == EquipmentStatus.available &&
                  !alreadyRequested) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: requesting
                          ? null
                          : () {
                              onRequest();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.onSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: requesting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.surface,
                              ),
                            )
                          : Text(
                              'Request item',
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
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _accent),
      ),
    );
  }
}
