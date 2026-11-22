import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/lunchbox_resident.dart';
import '../models/poll.dart';
import '../models/poll_detail.dart';
import '../models/poll_vote_row.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/live_refresh.dart';
import '../utils/poll_export.dart';
import '../utils/whatsapp_share.dart';
import '../widgets/ui.dart';

const _red = AppColors.danger;
const _green = AppColors.success;

class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key});

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> with LiveRefresh {
  List<PollDetail> _polls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPolls();
    // Votes, new polls, closures and deletions from anyone show up live.
    listenLive(['poll_updated'], () => _fetchPolls(showLoading: false));
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
      if (!mounted) return;
      setState(() {
        _polls = details
            .map((d) => PollDetail.fromJson(d as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // Background refreshes fail silently; the next event retries.
      if (showLoading) _notify('Could not load polls', isError: true);
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

    final openPolls = _polls.where((p) => p.isOpen).toList();
    final scheduledPolls = _polls.where((p) => p.isScheduled).toList();
    final pastPolls = _polls.where((p) => !p.isOpen && !p.isScheduled).toList();

    return Scaffold(
      appBar: AppBar(),
      body: _loading
          ? const AppLoadingView()
          : AppRefreshIndicator(
              onRefresh: () => _fetchPolls(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: isAdmin
                    ? _buildAdminList(openPolls, pastPolls, scheduledPolls)
                    : _buildResidentList(openPolls, pastPolls),
              ),
            ),
    );
  }

  List<Widget> _buildAdminList(
    List<PollDetail> open,
    List<PollDetail> past,
    List<PollDetail> scheduled,
  ) {
    final votes = open.fold<int>(0, (s, p) => s + p.totalVotes);
    final widgets = <Widget>[
      PageHeading(
        eyebrow: 'Kitchen',
        title: 'Meal polls',
        subtitle: open.isEmpty
            ? 'No poll is open right now'
            : '${open.length} open · $votes vote${votes == 1 ? '' : 's'} so far',
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _openNewPollSheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New poll'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openLunchboxSheet,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Lunchboxes'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
    ];

    if (_polls.isEmpty) {
      widgets.add(
        const EmptyState(
          icon: Icons.ramen_dining_outlined,
          title: 'No polls yet',
          message: 'Tap "New poll" to launch the first meal vote.',
        ),
      );
      return widgets;
    }

    void section(String label, List<PollDetail> polls) {
      if (polls.isEmpty) return;
      widgets.add(_SectionLabel(label, count: polls.length));
      for (final poll in polls) {
        widgets.add(
          _ManagePollCard(
            key: ValueKey('manage-${poll.pollId}'),
            poll: poll,
            onChanged: () => _fetchPolls(showLoading: false),
            notify: _notify,
          ),
        );
      }
      widgets.add(const SizedBox(height: 8));
    }

    section('Open now', open);
    section('Scheduled', scheduled);
    section('Closed', past);
    return widgets;
  }

  List<Widget> _buildResidentList(
    List<PollDetail> open,
    List<PollDetail> past,
  ) {
    final toVote = open.where((p) => p.myOptionIds.isEmpty).length;
    final widgets = <Widget>[
      PageHeading(
        eyebrow: 'Kitchen',
        title: 'Meal polls',
        subtitle: open.isEmpty
            ? 'No vote is open right now'
            : toVote == 0
            ? 'You\'re all voted up'
            : '$toVote poll${toVote == 1 ? '' : 's'} waiting for your vote',
      ),
      const SizedBox(height: 18),
    ];

    if (open.isEmpty) {
      widgets.add(
        const EmptyState(
          icon: Icons.ramen_dining_outlined,
          title: 'No active polls',
          message: 'We\'ll notify you when the next meal vote opens.',
        ),
      );
    } else {
      for (final poll in open) {
        widgets.add(
          _VoteCard(
            key: ValueKey('vote-${poll.pollId}'),
            poll: poll,
            onVoted: () => _fetchPolls(showLoading: false),
            notify: _notify,
          ),
        );
        widgets.add(const SizedBox(height: 14));
      }
    }

    if (past.isNotEmpty) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_SectionLabel('Past results', count: past.length));
      for (final poll in past) {
        widgets.add(
          _ResultCard(key: ValueKey('past-${poll.pollId}'), poll: poll),
        );
      }
    }

    return widgets;
  }
}

// ───────────────────────────── shared pieces ─────────────────────────────

/// "Closes in 2d 4h", "Closes in 35 min", "Closed Mar 4".
String _closesLabel(PollDetail poll) {
  if (poll.isScheduled) {
    return 'Opens ${DateFormat('EEE d MMM, HH:mm').format(poll.startDate)}';
  }
  if (!poll.isOpen) return 'Closed ${DateFormat.MMMd().format(poll.endDate)}';
  final left = poll.endDate.difference(DateTime.now());
  if (left.inDays >= 1) {
    final h = left.inHours % 24;
    return 'Closes in ${left.inDays}d${h > 0 ? ' ${h}h' : ''}';
  }
  if (left.inHours >= 1) return 'Closes in ${left.inHours}h';
  return 'Closes in ${left.inMinutes.clamp(1, 59)} min';
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final int count;
  const _SectionLabel(this.text, {required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Row(
        children: [
          Eyebrow(text),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small rounded status pill: green "Open" dot, or grey lock "Closed".
class _StatusPill extends StatelessWidget {
  final PollDetail poll;
  const _StatusPill(this.poll);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final open = poll.isOpen;
    final scheduled = poll.isScheduled;
    final fg = open
        ? _green
        : scheduled
        ? AppColors.primary
        : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (open)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            )
          else
            Icon(
              scheduled ? Icons.schedule_rounded : Icons.lock_outline_rounded,
              size: 11,
              color: fg,
            ),
          const SizedBox(width: 5),
          Text(
            _closesLabel(poll),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Orange rounded tile with a meal icon; anchors every poll card.
class _MealBadge extends StatelessWidget {
  final bool muted;
  const _MealBadge({this.muted = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: muted ? colors.surfaceContainerHighest : colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      ),
      child: Icon(
        Icons.ramen_dining_rounded,
        size: 20,
        color: muted ? colors.onSurfaceVariant : AppColors.primary,
      ),
    );
  }
}

/// One option as a tile whose background fills with its share of the vote.
/// Used for voting (with a check circle), for admin results and for past
/// results. [highlight] marks the resident's pick.
class _OptionTile extends StatelessWidget {
  final PollOption option;
  final int total;
  final bool highlight;
  final bool? checked; // null = not a voting tile
  final VoidCallback? onTap;

  const _OptionTile({
    required this.option,
    required this.total,
    this.highlight = false,
    this.checked,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final share = total > 0 ? option.voteCount / total : 0.0;
    final pct = (share * 100).round();
    final accent = highlight;
    final borderColor = highlight ? AppColors.primary : colors.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: onTap != null,
        selected: checked ?? false,
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            side: BorderSide(color: borderColor, width: highlight ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Vote share fill.
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      widthFactor: share.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: ColoredBox(
                        color: accent
                            ? AppColors.primary.withValues(alpha: 0.13)
                            : colors.onSurfaceVariant.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      if (checked != null) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: checked!
                                ? AppColors.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: checked!
                                  ? AppColors.primary
                                  : colors.outline,
                              width: 2,
                            ),
                          ),
                          child: checked!
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          option.optionName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: accent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: accent
                                  ? AppColors.primary
                                  : colors.onSurface,
                            ),
                          ),
                          Text(
                            '${option.voteCount} vote${option.voteCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
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

/// Card shell shared by every poll card: meal badge, title, status pill.
class _PollCardShell extends StatelessWidget {
  final PollDetail poll;
  final Widget? headerTrailing;
  final List<Widget> children;
  final Widget? footer;

  const _PollCardShell({
    required this.poll,
    required this.children,
    this.headerTrailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (poll.isOpen) Container(height: 3, color: AppColors.primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MealBadge(muted: !poll.isOpen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poll.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusPill(poll),
                          if (poll.repeats)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.repeat_rounded,
                                  size: 13,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  poll.recurrence == 'daily'
                                      ? 'Daily'
                                      : 'Weekly',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          Text(
                            '${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ?headerTrailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

/// --- Resident: a closed poll's results ---
class _ResultCard extends StatelessWidget {
  final PollDetail poll;
  const _ResultCard({super.key, required this.poll});

  @override
  Widget build(BuildContext context) {
    return _PollCardShell(
      poll: poll,
      children: [
        for (final opt in poll.options)
          _OptionTile(
            option: opt,
            total: poll.totalVotes,
            highlight: poll.myOptionIds.contains(opt.id),
          ),
        if (poll.myOptionIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'Outlined in orange: your pick',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    super.key,
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

  @override
  void didUpdateWidget(covariant _VoteCard old) {
    super.didUpdateWidget(old);
    // A live refresh brought new server state. If the resident hasn't
    // started changing their selection, follow the server (e.g. a vote cast
    // from another device); otherwise keep their unsaved draft.
    final untouched =
        (List.of(_draft)..sort()).toString() ==
        (List.of(old.poll.myOptionIds)..sort()).toString();
    if (untouched) _draft = List.of(widget.poll.myOptionIds);
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
    final voted = poll.myOptionIds.isNotEmpty;

    return _PollCardShell(
      poll: poll,
      headerTrailing: voted
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 12, color: _green),
                  SizedBox(width: 4),
                  Text(
                    'Voted',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                ],
              ),
            )
          : null,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              voted
                  ? 'Changed your mind? Tap options, then update.'
                  : 'Tap one or more options, then submit.',
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: (!_hasChanges || _submitting) ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: AppLoader(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        voted
                            ? 'Update my vote'
                            : _draft.isEmpty
                            ? 'Pick an option'
                            : 'Submit vote (${_draft.length})',
                      ),
              ),
            ),
          ],
        ),
      ),
      children: [
        for (final opt in poll.options)
          _OptionTile(
            option: opt,
            total: poll.totalVotes,
            highlight: _draft.contains(opt.id),
            checked: _draft.contains(opt.id),
            onTap: () => _toggle(opt.id),
          ),
      ],
    );
  }
}

/// --- Admin manage card ---
class _ManagePollCard extends StatefulWidget {
  final PollDetail poll;
  final VoidCallback onChanged;
  final void Function(String, {bool isError}) notify;

  const _ManagePollCard({
    super.key,
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

  // Who voted, for what, and when. Loaded on first open, refreshed when the
  // poll's vote count changes (live updates rebuild this card).
  bool _showVotes = false;
  List<PollVoteRow>? _votes;
  bool _votesLoading = false;
  int _votesForTotal = -1;

  Future<void> _loadVotes() async {
    setState(() => _votesLoading = true);
    try {
      final data = await ApiService.get('/polls/${widget.poll.pollId}/votes');
      if (!mounted) return;
      final rows =
          (data as List)
              .map((j) => PollVoteRow.fromJson(j as Map<String, dynamic>))
              .toList()
            ..sort((a, b) {
              final at = a.votedAt, bt = b.votedAt;
              if (at == null || bt == null) return 0;
              return bt.compareTo(at); // newest first
            });
      setState(() {
        _votes = rows;
        _votesForTotal = widget.poll.totalVotes;
      });
    } catch (_) {
      widget.notify('Could not load votes', isError: true);
    } finally {
      if (mounted) setState(() => _votesLoading = false);
    }
  }

  void _toggleVotes() {
    setState(() => _showVotes = !_showVotes);
    if (_showVotes && _votesForTotal != widget.poll.totalVotes) _loadVotes();
  }

  @override
  void didUpdateWidget(covariant _ManagePollCard old) {
    super.didUpdateWidget(old);
    if (_showVotes && widget.poll.totalVotes != _votesForTotal) _loadVotes();
  }

  Future<void> _stopRepeating() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop repeating?'),
        content: const Text(
          'This poll will run as normal, but no new round will be created after it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop repeating'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ApiService.post('/polls/${widget.poll.pollId}/recurrence', {
        'recurrence': 'none',
      });
      widget.notify('This poll won\'t repeat');
      widget.onChanged();
    } on ApiException catch (e) {
      widget.notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final poll = widget.poll;
    final timeFmt = DateFormat('EEE d MMM, HH:mm');

    Widget action(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      Color? color,
    }) {
      final fg = color ?? colors.onSurface;
      return Expanded(
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _PollCardShell(
      poll: poll,
      footer: Column(
        children: [
          Divider(height: 1, color: colors.outlineVariant),
          Row(
            children: [
              action(Icons.people_outline_rounded, 'By option', _openVoters),
              action(Icons.ios_share_rounded, 'Share', _openShare),
              if (poll.isActive && !poll.isScheduled)
                action(Icons.lock_clock_outlined, 'Close', _closePoll),
              action(
                Icons.delete_outline_rounded,
                'Delete',
                _deletePoll,
                color: _red,
              ),
            ],
          ),
        ],
      ),
      children: [
        if (poll.repeats)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.repeat_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    poll.recurrence == 'daily'
                        ? 'Repeats every day with the same options'
                        : 'Repeats every week with the same options',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _stopRepeating,
                  child: const Text('Stop', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ),
        for (final opt in poll.options)
          _OptionTile(option: opt, total: poll.totalVotes),

        // Who voted, for what, and when.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: poll.totalVotes == 0 ? null : _toggleVotes,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.how_to_vote_outlined,
                    size: 17,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      poll.totalVotes == 0
                          ? 'No votes yet'
                          : 'Who voted, for what, and when',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  if (poll.totalVotes > 0)
                    Icon(
                      _showVotes
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_showVotes)
          if (_votesLoading && _votes == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: AppLoader(size: 22)),
            )
          else
            for (final v in _votes ?? <PollVoteRow>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: colors.primaryContainer,
                      child: Text(
                        v.residentName.isNotEmpty
                            ? v.residentName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.residentName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          Text(
                            [
                              v.optionName,
                              if (v.roomNumber != null) 'Room ${v.roomNumber}',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (v.votedAt != null)
                      Text(
                        timeFmt.format(v.votedAt!.toLocal()),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    ? const AppLoadingView()
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
                                          backgroundColor: AppColors.primary
                                              .withValues(alpha: 0.12),
                                          child: Text(
                                            v.residentName.isNotEmpty
                                                ? v.residentName[0]
                                                      .toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: AppColors.primary,
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
                                        Text(
                                          [
                                            if (v.roomNumber != null)
                                              'Room ${v.roomNumber}',
                                            if (v.votedAt != null)
                                              DateFormat('EEE HH:mm')
                                                  .format(v.votedAt!.toLocal()),
                                          ].join(' · '),
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
                child: AppLoadingView(),
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
                          child: AppLoader(
                            strokeWidth: 2,
                            color: colors.surface,
                          ),
                        )
                      : const FaIcon(FontAwesomeIcons.whatsapp, size: 20),
                  label: const Text('Share to WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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

  /// 'none', 'daily' or 'weekly': repeat with the same options.
  String _recurrence = 'none';

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
        'recurrence': _recurrence,
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
                    if (_start != null && _start!.isAfter(DateTime.now()))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 15,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Scheduled: residents see it and get notified when it opens.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      'Repeat',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'none', label: Text('Once')),
                        ButtonSegment(value: 'daily', label: Text('Daily')),
                        ButtonSegment(value: 'weekly', label: Text('Weekly')),
                      ],
                      selected: {_recurrence},
                      onSelectionChanged: (s) =>
                          setState(() => _recurrence = s.first),
                    ),
                    if (_recurrence != 'none')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _recurrence == 'daily'
                              ? 'A new round opens every day at the same time, with the same options.'
                              : 'A new round opens every week at the same time, with the same options.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
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
                            borderRadius: BorderRadius.circular(
                              AppRadius.sm + 2,
                            ),
                          ),
                        ),
                        child: _submitting
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: AppLoader(
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
        borderSide: const BorderSide(color: AppColors.primary),
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
                top: Radius.circular(20),
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
                      ? const AppLoadingView()
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
                                          child: AppLoader(
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
