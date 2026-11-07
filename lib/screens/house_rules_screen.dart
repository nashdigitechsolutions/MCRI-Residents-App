import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_rule.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/ui.dart';

const _red = AppColors.danger;
const _accent = AppColors.primary;

class HouseRulesScreen extends StatefulWidget {
  const HouseRulesScreen({super.key});

  @override
  State<HouseRulesScreen> createState() => _HouseRulesScreenState();
}

class _HouseRulesScreenState extends State<HouseRulesScreen> {
  List<HouseRule> _rules = [];
  bool _loading = true;
  String _search = '';
  int? _openId;

  @override
  void initState() {
    super.initState();
    _fetchRules();
    _loadRead();
  }

  Future<void> _fetchRules({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/house-rules');
      if (!mounted) return;
      setState(() {
        _rules = (data as List)
            .map((j) => HouseRule.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _notify('Could not load house rules', isError: true);
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

  List<HouseRule> get _filtered {
    if (_search.trim().isEmpty) return _rules;
    final q = _search.toLowerCase();
    return _rules
        .where(
          (r) =>
              r.title.toLowerCase().contains(q) ||
              (r.description ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _openForm({HouseRule? rule}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RuleFormSheet(rule: rule),
    );
    if (saved == true) {
      _notify(rule == null ? 'Rule created' : 'Rule updated');
      _fetchRules(showLoading: false);
    }
  }

  Future<void> _deleteRule(HouseRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete rule?'),
        content: Text('Delete "${rule.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.delete('/house-rules/${rule.ruleId}');
      _notify('Rule deleted');
      _fetchRules(showLoading: false);
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('Could not delete rule', isError: true);
    }
  }

  // Rules this device has opened (kept locally so the progress survives restarts).
  static const _readKey = 'house_rules_read_v1';
  Set<int> _read = {};
  bool _expandAll = false;

  Future<void> _loadRead() async {
    try {
      final raw = await StorageService.getItem(_readKey);
      if (raw == null || !mounted) return;
      setState(
        () => _read = raw.split(',').map(int.tryParse).whereType<int>().toSet(),
      );
    } catch (_) {}
  }

  void _markRead(Iterable<int> ids) {
    final before = _read.length;
    _read = {..._read, ...ids};
    if (_read.length != before) {
      StorageService.setItem(_readKey, _read.join(',')).catchError((_) {});
    }
  }

  void _toggle(HouseRule r) {
    setState(() {
      _openId = _openId == r.ruleId ? null : r.ruleId;
      _markRead([r.ruleId]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.roleId == 1;
    final rules = _filtered;
    final readCount = _rules.where((r) => _read.contains(r.ruleId)).length;
    final allRead = _rules.isNotEmpty && readCount == _rules.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('House rules'),
        actions: [
          if (_rules.isNotEmpty)
            IconButton(
              tooltip: _expandAll ? 'Collapse all' : 'Expand all',
              icon: Icon(
                _expandAll
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
              ),
              onPressed: () => setState(() {
                _expandAll = !_expandAll;
                _openId = null;
                if (_expandAll) _markRead(_rules.map((r) => r.ruleId));
              }),
            ),
          if (isAdmin)
            IconButton(
              tooltip: 'Add rule',
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: _loading
          ? const AppLoadingView(message: 'Loading house rules…')
          : AppRefreshIndicator(
              onRefresh: () => _fetchRules(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _hero(readCount, allRead),
                  const SizedBox(height: 16),
                  if (_rules.length > 4) ...[
                    _SearchField(
                      value: _search,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (rules.isEmpty)
                    EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: _search.isNotEmpty
                          ? 'No matches'
                          : 'No rules set yet',
                      message: _search.isNotEmpty
                          ? 'Try a different search term.'
                          : isAdmin
                          ? 'Tap + to add the first house rule.'
                          : 'The lodge manager hasn\'t added any rules yet.',
                    )
                  else
                    for (var i = 0; i < rules.length; i++)
                      _RuleRow(
                        index: _rules.indexOf(rules[i]),
                        rule: rules[i],
                        isOpen: _expandAll || _openId == rules[i].ruleId,
                        isRead: _read.contains(rules[i].ruleId),
                        isAdmin: isAdmin,
                        onTap: () => _toggle(rules[i]),
                        onEdit: () => _openForm(rule: rules[i]),
                        onDelete: () => _deleteRule(rules[i]),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _hero(int readCount, bool allRead) {
    final total = _rules.length;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  allRead ? Icons.verified_rounded : Icons.menu_book_rounded,
                  color: AppColors.primaryBorder,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LIVING TOGETHER',
                      style: TextStyle(
                        color: AppColors.primaryBorder,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? 'House rules'
                          : '$total rule${total == 1 ? '' : 's'} for a happy house',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: readCount / total,
                      minHeight: 8,
                      color: AppColors.primary,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  allRead ? 'All read' : '$readCount of $total read',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (!allRead) ...[
              const SizedBox(height: 10),
              Text(
                'Tap a rule to read it. Everyone in the house agrees to these.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Picks an icon from the rule's wording so the list scans at a glance.
IconData _iconFor(HouseRule r) {
  final t = '${r.title} ${r.description ?? ''}'.toLowerCase();
  const table = <(List<String>, IconData)>[
    (['quiet', 'noise', 'music', 'loud'], Icons.volume_off_outlined),
    (['guest', 'visitor', 'visit'], Icons.group_outlined),
    (['smok', 'vape', 'alcohol', 'drink'], Icons.smoke_free_outlined),
    (['kitchen', 'cook', 'food', 'dish', 'fridge'], Icons.kitchen_outlined),
    (
      ['clean', 'tidy', 'trash', 'rubbish', 'bin', 'waste'],
      Icons.cleaning_services_outlined,
    ),
    (['laundry', 'wash', 'cloth'], Icons.local_laundry_service_outlined),
    (['pay', 'rent', 'fee', 'fine'], Icons.payments_outlined),
    (['wifi', 'internet', 'network'], Icons.wifi_rounded),
    (
      ['safety', 'fire', 'lock', 'key', 'security', 'gate'],
      Icons.shield_outlined,
    ),
    (['curfew', 'time', 'hour', 'night'], Icons.schedule_rounded),
    (['water', 'electric', 'power', 'light'], Icons.bolt_outlined),
    (['pet', 'animal'], Icons.pets_outlined),
  ];
  for (final (words, icon) in table) {
    if (words.any(t.contains)) return icon;
  }
  return Icons.rule_rounded;
}

class _SearchField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: c),
    );
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search rules…',
        prefixIcon: Icon(
          Icons.search,
          size: 19,
          color: colors.onSurfaceVariant,
        ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border(colors.outlineVariant),
        enabledBorder: border(colors.outlineVariant),
        focusedBorder: border(_accent),
      ),
    );
  }
}

/// One rule card: keyword icon, number, title, read tick, smooth expand.
class _RuleRow extends StatelessWidget {
  final int index;
  final HouseRule rule;
  final bool isOpen;
  final bool isRead;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleRow({
    required this.index,
    required this.rule,
    required this.isOpen,
    required this.isRead,
    required this.isAdmin,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isOpen ? _accent : colors.outlineVariant,
          width: isOpen ? 1.4 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isOpen ? _accent : colors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                      ),
                      child: Icon(
                        _iconFor(rule),
                        size: 20,
                        color: isOpen ? Colors.white : _accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RULE ${index + 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            rule.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isRead && !isOpen)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 17,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                          semanticLabel: 'Read',
                        ),
                      ),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: isOpen
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(52, 10, 6, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.description?.isNotEmpty == true
                                    ? rule.description!
                                    : 'No additional details provided.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colors.onSurfaceVariant,
                                  height: 1.55,
                                ),
                              ),
                              if (isAdmin) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    TextButton.icon(
                                      onPressed: onEdit,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Edit'),
                                    ),
                                    TextButton.icon(
                                      onPressed: onDelete,
                                      style: TextButton.styleFrom(
                                        foregroundColor: _red,
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 16,
                                      ),
                                      label: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleFormSheet extends StatefulWidget {
  final HouseRule? rule;
  const _RuleFormSheet({this.rule});

  @override
  State<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends State<_RuleFormSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.rule?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.rule?.description ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }

    setState(() => _submitting = true);
    try {
      if (widget.rule != null) {
        await ApiService.patch('/house-rules/${widget.rule!.ruleId}', {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        });
      } else {
        await ApiService.post('/house-rules', {
          'title': _titleController.text.trim(),
          if (_descriptionController.text.trim().isNotEmpty)
            'description': _descriptionController.text.trim(),
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save rule');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEdit = widget.rule != null;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? 'Edit rule' : 'New house rule',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: colors.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: _decoration(colors, hint: 'Rule title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
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
                        isEdit ? 'Save changes' : 'Create rule',
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
