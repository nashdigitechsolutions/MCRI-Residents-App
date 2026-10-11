import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_rule.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

const _red = Color(0xFFEF4444);
const _accent = Color(0xFF3355FF);

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
  }

  Future<void> _fetchRules({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/house-rules');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        margin: const EdgeInsets.only(bottom: 24, left: 60, right: 60),
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.roleId == 1;
    final colors = Theme.of(context).colorScheme;
    final rules = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('House rules'),
        actions: isAdmin
            ? [
                IconButton(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchRules(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- energetic header strip ---
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_accent, _accent.withValues(alpha: 0.75)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.menu_book_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'House rules',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${_rules.length} rule${_rules.length == 1 ? '' : 's'} keeping the house running smoothly',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_rules.length > 4) ...[
                    _SearchField(
                      value: _search,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 14),
                  ],

                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: rules.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: 30,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _search.isNotEmpty
                                      ? 'No matches'
                                      : 'No rules set yet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                                ),
                                if (_search.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Try a different search term.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : Material(
                            color: colors.surface,
                            child: Column(
                              children: [
                                for (var i = 0; i < rules.length; i++) ...[
                                  _RuleRow(
                                    index: i,
                                    rule: rules[i],
                                    isOpen: _openId == rules[i].ruleId,
                                    isAdmin: isAdmin,
                                    onTap: () => setState(
                                      () => _openId = _openId == rules[i].ruleId
                                          ? null
                                          : rules[i].ruleId,
                                    ),
                                    onEdit: () => _openForm(rule: rules[i]),
                                    onDelete: () => _deleteRule(rules[i]),
                                  ),
                                  if (i < rules.length - 1)
                                    Divider(
                                      height: 1,
                                      color: colors.outlineVariant,
                                    ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
    );
  }
}

/// A single accordion row — numbered badge, title, admin edit icon, chevron
/// that flips, and a smooth expand/collapse for the description.
class _RuleRow extends StatelessWidget {
  final int index;
  final HouseRule rule;
  final bool isOpen;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleRow({
    required this.index,
    required this.rule,
    required this.isOpen,
    required this.isAdmin,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  height: 26,
                  width: 26,
                  decoration: BoxDecoration(
                    color: isOpen ? _accent : colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isOpen ? Colors.white : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rule.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                if (isAdmin)
                  GestureDetector(
                    onTap: onEdit,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
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
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: isOpen
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(56, 0, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.description?.isNotEmpty == true
                            ? rule.description!
                            : 'No additional details provided.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: onDelete,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.delete_outline,
                                size: 14,
                                color: _red,
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Delete rule',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// --- Create/edit rule sheet ---
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
