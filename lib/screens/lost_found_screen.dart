import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/live_refresh.dart';
import '../widgets/app_loader.dart';
import '../widgets/app_refresh.dart';
import '../widgets/ui.dart';

/// Lost & found board: residents post things they lost or found; the poster
/// (or an admin) marks it returned when it's sorted.
class LostFoundScreen extends StatefulWidget {
  final int? highlightItemId;
  const LostFoundScreen({super.key, this.highlightItemId});

  @override
  State<LostFoundScreen> createState() => _LostFoundScreenState();
}

class _LostFoundScreenState extends State<LostFoundScreen> with LiveRefresh {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | lost | found
  bool _showReturned = false;

  @override
  void initState() {
    super.initState();
    _load();
    listenLive(['lost_found_updated'], () => _load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/lost-found');
      if (!mounted) return;
      setState(() {
        _items = (data as List).cast<Map<String, dynamic>>();
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

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openNew() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewItemSheet(),
    );
    if (posted == true) {
      _toast('Posted. Everyone has been notified.');
      _load(quiet: true);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    try {
      await ApiService.patch('/lost-found/${item['item_id']}', {
        'status': status,
      });
      _toast(status == 'resolved' ? 'Marked as returned' : 'Reopened');
      _load(quiet: true);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this post?'),
        content: Text('"${item['title']}" will be removed for everyone.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.delete('/lost-found/${item['item_id']}');
      _toast('Deleted');
      _load(quiet: true);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthProvider, bool>(
      (a) => a.user?.roleId == 1,
    );
    final open = _items
        .where((i) => i['status'] == 'open')
        .where((i) => _filter == 'all' || i['kind'] == _filter)
        .toList();
    final returned = _items
        .where((i) => i['status'] == 'resolved')
        .where((i) => _filter == 'all' || i['kind'] == _filter)
        .toList();
    final lostCount = _items
        .where((i) => i['status'] == 'open' && i['kind'] == 'lost')
        .length;
    final foundCount = _items
        .where((i) => i['status'] == 'open' && i['kind'] == 'found')
        .length;

    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Post item'),
      ),
      body: _loading
          ? const AppLoadingView(message: 'Loading lost & found…')
          : AppRefreshIndicator(
              onRefresh: () => _load(quiet: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  PageHeading(
                    eyebrow: 'Community',
                    title: 'Lost & found',
                    subtitle: '$lostCount lost · $foundCount found',
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'lost', label: Text('Lost')),
                      ButtonSegment(value: 'found', label: Text('Found')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load lost & found',
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: _load,
                    )
                  else if (open.isEmpty && returned.isEmpty)
                    const EmptyState(
                      icon: Icons.travel_explore_rounded,
                      title: 'Nothing here yet',
                      message: 'Lost something, or found something that isn\'t yours? Post it and everyone gets a heads-up.',
                    )
                  else ...[
                    if (open.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No open posts.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final item in open)
                      _ItemCard(
                        item: item,
                        highlight: item['item_id'] == widget.highlightItemId,
                        canManage: item['is_mine'] == true || isAdmin,
                        onResolve: () => _setStatus(item, 'resolved'),
                        onDelete: () => _delete(item),
                      ),
                    if (returned.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showReturned = !_showReturned),
                        icon: Icon(
                          _showReturned
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text('Returned (${returned.length})'),
                      ),
                      if (_showReturned)
                        for (final item in returned)
                          _ItemCard(
                            item: item,
                            canManage: item['is_mine'] == true || isAdmin,
                            onReopen: () => _setStatus(item, 'open'),
                            onDelete: () => _delete(item),
                          ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool highlight;
  final bool canManage;
  final VoidCallback? onResolve;
  final VoidCallback? onReopen;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.item,
    required this.canManage,
    required this.onDelete,
    this.highlight = false,
    this.onResolve,
    this.onReopen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lost = item['kind'] == 'lost';
    final resolved = item['status'] == 'resolved';
    final accent = lost ? AppColors.warning : AppColors.success;
    final created = DateTime.tryParse('${item['created_at'] ?? ''}');
    final description = (item['description'] as String?)?.trim();
    final location = (item['location'] as String?)?.trim();

    return Opacity(
      opacity: resolved ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: highlight ? AppColors.primary : colors.outlineVariant,
            width: highlight ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                  child: Icon(
                    lost
                        ? Icons.help_outline_rounded
                        : Icons.inventory_2_outlined,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              resolved
                                  ? 'RETURNED'
                                  : lost
                                  ? 'LOST'
                                  : 'FOUND',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: accent,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (created != null)
                            Text(
                              DateFormat('d MMM').format(created.toLocal()),
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${item['title']}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      if (location != null && location.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colors.onSurface,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['is_mine'] == true
                        ? 'Posted by you'
                        : 'Posted by ${item['posted_by'] ?? 'a resident'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (canManage && !resolved && onResolve != null)
                  TextButton(
                    onPressed: onResolve,
                    child: Text(lost ? 'Got it back' : 'Returned'),
                  ),
                if (canManage && resolved && onReopen != null)
                  TextButton(onPressed: onReopen, child: const Text('Reopen')),
                if (canManage)
                  IconButton(
                    onPressed: onDelete,
                    tooltip: 'Delete',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 19,
                      color: AppColors.dangerDark,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewItemSheet extends StatefulWidget {
  const _NewItemSheet();

  @override
  State<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends State<_NewItemSheet> {
  String _kind = 'lost';
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Say what the item is');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.post('/lost-found', {
        'kind': _kind,
        'title': _title.text.trim(),
        'location': _location.text.trim(),
        'description': _description.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                'Post to lost & found',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'lost', label: Text('I lost something')),
                  ButtonSegment(
                    value: 'found',
                    label: Text('I found something'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What is it?',
                  hintText: 'e.g. Black umbrella, room key',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _location,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _kind == 'lost'
                      ? 'Where did you last have it? (optional)'
                      : 'Where did you find it? (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  hintText: 'Colour, brand, anything that helps',
                  counterText: '',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.dangerDark),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: AppLoader(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Post'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
