import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/lunchbox_resident.dart';
import '../models/poll.dart';
import '../models/poll_detail.dart';
import '../models/poll_vote_row.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/poll_export.dart';
import '../utils/whatsapp_share.dart';

const _red = Color(0xFFEF4444);
const _green = Color(0xFF10B981);

class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key});

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  List<PollDetail> _polls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPolls();
  }

  Future<void> _fetchPolls({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final list = await ApiService.get('/polls');
      final ids = (list as List)
          .map((p) => (p as Map<String, dynamic>)['poll_id'])
          .toList();
      final details = await Future.wait(
        ids.map((id) => ApiService.get('/polls/$id')),
      );
      setState(() {
        _polls = details
            .map((d) => PollDetail.fromJson(d as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _notify('Could not load polls', isError: true);
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

  Future<void> _openNewPollSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewPollSheet(),
    );
    if (created == true) {
      _notify('Poll created');
      _fetchPolls(showLoading: false);
    }
  }

  Future<void> _openLunchboxSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LunchboxSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.roleId == 1;
    final colors = Theme.of(context).colorScheme;

    final openPolls = _polls.where((p) => p.isOpen).toList();
    final pastPolls = _polls.where((p) => !p.isOpen).toList();

    return Scaffold(
      appBar: AppBar(
        actions: isAdmin
            ? [
                IconButton(
                  onPressed: _openLunchboxSheet,
                  icon: const Icon(Icons.inventory_2_outlined),
                  tooltip: 'Lunchboxes',
                ),
                IconButton(
                  onPressed: _openNewPollSheet,
                  icon: const Icon(Icons.add),
                  tooltip: 'New poll',
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchPolls(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: isAdmin
                    ? _buildAdminList(colors)
                    : _buildResidentList(colors, openPolls, pastPolls),
              ),
            ),
    );
  }

  List<Widget> _buildAdminList(ColorScheme colors) {
    if (_polls.isEmpty) {
      return [
        _emptyState(
          colors,
          'No polls created yet',
          'Use "New poll" to launch the first meal vote.',
        ),
      ];
    }
    return _polls
        .map(
          (poll) => _ManagePollCard(
            poll: poll,
            onChanged: () => _fetchPolls(showLoading: false),
            notify: _notify,
          ),
        )
        .toList();
  }

  List<Widget> _buildResidentList(
    ColorScheme colors,
    List<PollDetail> open,
    List<PollDetail> past,
  ) {
    final widgets = <Widget>[];

    if (open.isEmpty) {
      widgets.add(
        _emptyState(
          colors,
          'No active polls',
          'Check back when the next meal vote opens.',
        ),
      );
    } else {
      for (final poll in open) {
        widgets.add(
          _VoteCard(
            poll: poll,
            onVoted: () => _fetchPolls(showLoading: false),
            notify: _notify,
          ),
        );
        widgets.add(const SizedBox(height: 12));
      }
    }

    if (past.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Past polls (${past.length})',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          children: [
            for (final poll in past) ...[
              _VoteCard(
                poll: poll,
                onVoted: () => _fetchPolls(showLoading: false),
                notify: _notify,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      );
    }

    return widgets;
  }

  Widget _emptyState(ColorScheme colors, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.ramen_dining_outlined,
            size: 32,
            color: colors.onSurfaceVariant,
          ),
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
}

/// A single option's vote bar — shared by both the resident voting view and
/// the admin results view.
class _OptionBar extends StatelessWidget {
  final PollOption option;
  final int total;
  final bool selected;

  const _OptionBar({
    required this.option,
    required this.total,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pct = total > 0 ? ((option.voteCount / total) * 100).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              option.optionName,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? const Color(0xFF3355FF) : colors.onSurface,
              ),
            ),
            Text(
              '${option.voteCount} vote${option.voteCount == 1 ? '' : 's'} · $pct%',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: total > 0 ? option.voteCount / total : 0,
            minHeight: 6,
            backgroundColor: colors.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              selected
                  ? const Color(0xFF3355FF)
                  : colors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// --- Resident voting card ---
class _VoteCard extends StatefulWidget {
  final PollDetail poll;
  final VoidCallback onVoted;
  final void Function(String, {bool isError}) notify;

  const _VoteCard({
    required this.poll,
    required this.onVoted,
    required this.notify,
  });

  @override
  State<_VoteCard> createState() => _VoteCardState();
}

class _VoteCardState extends State<_VoteCard> {
  late List<int> _draft;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _draft = List.of(widget.poll.myOptionIds);
  }

  bool get _hasChanges {
    final a = List.of(_draft)..sort();
    final b = List.of(widget.poll.myOptionIds)..sort();
    return a.toString() != b.toString();
  }

  void _toggle(int id) {
    setState(() {
      if (_draft.contains(id)) {
        _draft.remove(id);
      } else {
        _draft.add(id);
      }
    });
  }

  Future<void> _submit() async {
    if (_draft.isEmpty) {
      widget.notify('Pick at least one option', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/polls/${widget.poll.pollId}/vote', {
        'option_ids': _draft,
      });
      widget.notify('Your vote is locked in');
      widget.onVoted();
    } on ApiException catch (e) {
      widget.notify(e.message, isError: true);
    } catch (e) {
      widget.notify('Vote failed', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final poll = widget.poll;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  poll.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (!poll.isOpen)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 11,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Closed',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${DateFormat.MMMd().format(poll.startDate)} – ${DateFormat.yMMMd().format(poll.endDate)}',
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          for (final opt in poll.options) ...[
            if (poll.isOpen)
              InkWell(
                onTap: () => _toggle(opt.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _draft.contains(opt.id)
                              ? const Color(0xFF3355FF)
                              : Colors.transparent,
                          border: Border.all(
                            color: _draft.contains(opt.id)
                                ? const Color(0xFF3355FF)
                                : colors.outlineVariant,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _draft.contains(opt.id)
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionBar(
                          option: opt,
                          total: poll.totalVotes,
                          selected: _draft.contains(opt.id),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _OptionBar(
                  option: opt,
                  total: poll.totalVotes,
                  selected: poll.myOptionIds.contains(opt.id),
                ),
              ),
          ],
          if (poll.isOpen) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: (!_hasChanges || _submitting) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.surface,
                        ),
                      )
                    : Text(
                        poll.myOptionIds.isNotEmpty
                            ? 'Update my vote'
                            : 'Submit vote',
                        style: TextStyle(
                          color: colors.surface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// --- Admin manage card ---
class _ManagePollCard extends StatefulWidget {
  final PollDetail poll;
  final VoidCallback onChanged;
  final void Function(String, {bool isError}) notify;

  const _ManagePollCard({
    required this.poll,
    required this.onChanged,
    required this.notify,
  });

  @override
  State<_ManagePollCard> createState() => _ManagePollCardState();
}

class _ManagePollCardState extends State<_ManagePollCard> {
  bool _busy = false;

  Future<void> _closePoll() async {
    setState(() => _busy = true);
    try {
      await ApiService.post('/polls/${widget.poll.pollId}/close', {});
      widget.notify('Poll closed');
      widget.onChanged();
    } on ApiException catch (e) {
      widget.notify(e.message, isError: true);
    } catch (e) {
      widget.notify('Could not close poll', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePoll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete poll?'),
        content: Text(
          'Permanently delete "${widget.poll.title}"? This cannot be undone.',
        ),
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

    setState(() => _busy = true);
    try {
      await ApiService.delete('/polls/${widget.poll.pollId}');
      widget.notify('Poll deleted');
      widget.onChanged();
    } on ApiException catch (e) {
      widget.notify(e.message, isError: true);
    } catch (e) {
      widget.notify('Could not delete poll', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openVoters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VotersSheet(poll: widget.poll),
    );
  }

  void _openShare() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(poll: widget.poll, notify: widget.notify),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final poll = widget.poll;
    PollOption? leading;
    for (final o in poll.options) {
      if (leading == null || o.voteCount > leading.voteCount) leading = o;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              poll.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (poll.isActive
                                          ? _green
                                          : colors.onSurfaceVariant)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              poll.isActive ? 'Open' : 'Closed',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: poll.isActive
                                    ? _green
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (poll.isActive)
                      TextButton(
                        onPressed: _busy ? null : _closePoll,
                        child: const Text(
                          'Close',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    IconButton(
                      onPressed: _busy ? null : _deletePoll,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 19,
                        color: _red,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${DateFormat.MMMd().format(poll.startDate)} – ${DateFormat.yMMMd().format(poll.endDate)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${poll.totalVotes}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          'TOTAL VOTES',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    if (leading != null && poll.totalVotes > 0) ...[
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              leading.optionName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'LEADING OPTION',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                for (final opt in poll.options) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _OptionBar(
                      option: opt,
                      total: poll.totalVotes,
                      selected: false,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _openVoters,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'View voters',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 40, color: colors.outlineVariant),
              Expanded(
                child: InkWell(
                  onTap: _openShare,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Share',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// --- Voters list sheet ---
class _VotersSheet extends StatefulWidget {
  final PollDetail poll;
  const _VotersSheet({required this.poll});

  @override
  State<_VotersSheet> createState() => _VotersSheetState();
}

class _VotersSheetState extends State<_VotersSheet> {
  List<PollVoteRow>? _rows;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/polls/${widget.poll.pollId}/votes');
      setState(() {
        _rows = (data as List)
            .map((j) => PollVoteRow.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load votes';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = _rows ?? [];
    final byOption = <String, List<PollVoteRow>>{};
    for (final r in rows) {
      byOption.putIfAbsent(r.optionName, () => []).add(r);
    }
    final grouped = byOption.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final uniqueVoters = rows.map((r) => r.userId).toSet().length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Responses',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        widget.poll.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.onSurface),
                  ),
                ],
              ),
              if (!_loading && _rows != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                      bottom: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      _stat(colors, '$uniqueVoters', 'Residents voted'),
                      const SizedBox(width: 16),
                      Container(
                        width: 1,
                        height: 32,
                        color: colors.outlineVariant,
                      ),
                      const SizedBox(width: 16),
                      _stat(colors, '${rows.length}', 'Total selections'),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _red),
                        ),
                      )
                    : grouped.isEmpty
                    ? Center(
                        child: Text(
                          'No one has voted yet.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: grouped.length,
                        itemBuilder: (context, i) {
                          final entry = grouped[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${entry.value.length}',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                for (final v in entry.value)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: const Color(
                                            0xFF3355FF,
                                          ).withValues(alpha: 0.12),
                                          child: Text(
                                            v.residentName.isNotEmpty
                                                ? v.residentName[0]
                                                      .toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF3355FF),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            v.residentName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colors.onSurface,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (v.roomNumber != null)
                                          Text(
                                            'Room ${v.roomNumber}',
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
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(ColorScheme colors, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

/// --- Share sheet (txt export + WhatsApp) ---
class _ShareSheet extends StatefulWidget {
  final PollDetail poll;
  final void Function(String, {bool isError}) notify;

  const _ShareSheet({required this.poll, required this.notify});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  ExportScope _scope = ExportScope.all;
  List<PollVoteRow>? _rows;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/polls/${widget.poll.pollId}/votes');
      setState(() {
        _rows = (data as List)
            .map((j) => PollVoteRow.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      widget.notify('Could not load votes for export', isError: true);
    }
  }

  String? _buildText() {
    if (_rows == null || _rows!.isEmpty) return null;
    final body = buildPollExportText(_rows!, _scope);
    return '${widget.poll.title}\n\n$body';
  }

  Future<void> _handleShare() async {
    final text = _buildText();
    if (text == null) {
      widget.notify('No votes to export yet', isError: true);
      return;
    }
    setState(() => _working = true);
    await shareToWhatsApp(text);
    if (mounted) setState(() => _working = false);
  }

  Future<void> _handleCopy() async {
    final text = _buildText();
    if (text == null) {
      widget.notify('No votes to export yet', isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    widget.notify('Copied to clipboard');
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
              'Share votes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            Text(
              widget.poll.title,
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              'What to include',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _scopeChip(colors, 'All data', ExportScope.all),
                _scopeChip(colors, 'Names only', ExportScope.names),
                _scopeChip(colors, 'Lunchbox #s only', ExportScope.lunchbox),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _working ? null : _handleShare,
                  icon: _working
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.surface,
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Share to WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _handleCopy,
                  icon: const Icon(Icons.copy_outlined, size: 17),
                  label: const Text('Copy text'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scopeChip(ColorScheme colors, String label, ExportScope scope) {
    final selected = _scope == scope;
    return GestureDetector(
      onTap: () => setState(() => _scope = scope),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.onSurface : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? colors.surface : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// --- New poll sheet ---
class _NewPollSheet extends StatefulWidget {
  const _NewPollSheet();

  @override
  State<_NewPollSheet> createState() => _NewPollSheetState();
}

class _NewPollSheetState extends State<_NewPollSheet> {
  final _titleController = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? DateTime.now()),
    );
    if (time == null) return date;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _addOption() {
    if (_optionControllers.length >= 20) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int i) {
    setState(() {
      final removed = _optionControllers.removeAt(i);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (_titleController.text.trim().isEmpty ||
        _start == null ||
        _end == null) {
      setState(() => _error = 'Title, start date, and end date are required');
      return;
    }
    if (options.length < 2) {
      setState(() => _error = 'Add at least 2 options');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/polls', {
        'title': _titleController.text.trim(),
        'start_date': _start!.toUtc().toIso8601String(),
        'end_date': _end!.toUtc().toIso8601String(),
        'options': options,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not create poll');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('MMM d, h:mm a');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
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
              'New meal poll',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: _decoration(
                        colors,
                        hint: 'Poll title, e.g. Friday dinner vote',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await _pickDateTime(_start);
                              if (picked != null) {
                                setState(() => _start = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _start == null
                                    ? 'Opens…'
                                    : dateFmt.format(_start!),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _start == null
                                      ? colors.onSurfaceVariant
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await _pickDateTime(_end);
                              if (picked != null) setState(() => _end = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _end == null
                                    ? 'Closes…'
                                    : dateFmt.format(_end!),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _end == null
                                      ? colors.onSurfaceVariant
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Options',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _optionControllers.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _optionControllers[i],
                                decoration: _decoration(
                                  colors,
                                  hint: 'Option ${i + 1}',
                                ),
                              ),
                            ),
                            if (_optionControllers.length > 2)
                              IconButton(
                                onPressed: () => _removeOption(i),
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_optionControllers.length < 20)
                      TextButton.icon(
                        onPressed: _addOption,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add option'),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: _red, fontSize: 13),
                      ),
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
                                'Create poll',
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
        borderSide: const BorderSide(color: Color(0xFF3355FF)),
      ),
    );
  }
}

/// --- Lunchbox directory sheet ---
class _LunchboxSheet extends StatefulWidget {
  const _LunchboxSheet();

  @override
  State<_LunchboxSheet> createState() => _LunchboxSheetState();
}

class _LunchboxSheetState extends State<_LunchboxSheet> {
  List<LunchboxResident> _residents = [];
  final Map<int, TextEditingController> _controllers = {};
  bool _loading = true;
  int? _savingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/lunchbox-directory');
      final list = (data as List)
          .map((j) => LunchboxResident.fromJson(j as Map<String, dynamic>))
          .toList();
      for (final r in list) {
        _controllers[r.residentId] = TextEditingController(
          text: r.lunchboxNumber ?? '',
        );
      }
      setState(() {
        _residents = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save(LunchboxResident r) async {
    setState(() => _savingId = r.residentId);
    final value = _controllers[r.residentId]!.text.trim();
    try {
      await ApiService.patch('/lunchbox-directory/${r.residentId}', {
        'lunchbox_number': value.isEmpty ? null : value,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved for ${r.displayName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
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
                      'Lunchbox numbers',
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
                Text(
                  "Assign each resident's box number. Included on poll exports.",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _residents.isEmpty
                      ? Center(
                          child: Text(
                            'No residents found',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _residents.length,
                          itemBuilder: (context, i) {
                            final r = _residents[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.displayName,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                            color: colors.onSurface,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          r.roomNumber != null
                                              ? 'Room ${r.roomNumber}'
                                              : 'No room',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 64,
                                    child: TextField(
                                      controller: _controllers[r.residentId],
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        hintText: 'e.g. 12',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide(
                                            color: colors.outlineVariant,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide(
                                            color: colors.outlineVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _savingId == r.residentId
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        )
                                      : TextButton(
                                          onPressed: () => _save(r),
                                          child: const Text(
                                            'Save',
                                            style: TextStyle(fontSize: 12.5),
                                          ),
                                        ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
