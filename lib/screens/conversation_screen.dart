import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../providers/unread_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../utils/initials.dart';
import 'conversation_detail_screen.dart';

const _accent = Color(0xFF3355FF);
const _red = Color(0xFFEF4444);

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation> _conversations = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  int? _deletingId;

  void Function(dynamic)? _onMessage;
  void Function(dynamic)? _onReaction;

  @override
  void initState() {
    super.initState();
    _fetch();

    final ws = context.read<WebSocketProvider>();
    _onMessage = (payload) {
      final msg = payload['data']?['message'] ?? payload['message'];
      if (msg == null) return;
      final targetId = msg['conversation_id'] is String
          ? int.parse(msg['conversation_id'])
          : msg['conversation_id'] as int;
      final exists = _conversations.any((c) => c.conversationId == targetId);
      if (!exists) {
        _fetch(showLoading: false);
        return;
      }
      final me = context.read<AuthProvider>().user?.userId;
      setState(() {
        _conversations =
            _conversations.map((c) {
              if (c.conversationId != targetId) return c;
              return c.copyWith(
                lastMessage: msg['message'] as String?,
                lastMessageAt: DateTime.tryParse(
                  msg['created_at'] as String? ?? '',
                ),
                lastActivityType: 'message',
                lastActivityAt: DateTime.tryParse(
                  msg['created_at'] as String? ?? '',
                ),
                lastActivityByMe:
                    (msg['sender_id'] is String
                        ? int.parse(msg['sender_id'])
                        : msg['sender_id']) ==
                    me,
              );
            }).toList()..sort(
              (a, b) => (b.lastActivityAt ?? DateTime(0)).compareTo(
                a.lastActivityAt ?? DateTime(0),
              ),
            );
      });
    };
    _onReaction = (_) => _fetch(showLoading: false);
    ws.on('message', _onMessage!);
    ws.on('reaction', _onReaction!);
  }

  @override
  void dispose() {
    final ws = context.read<WebSocketProvider>();
    if (_onMessage != null) ws.off('message', _onMessage!);
    if (_onReaction != null) ws.off('reaction', _onReaction!);
    super.dispose();
  }

  Future<void> _fetch({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await ApiService.get('/conversations');
      setState(() {
        _conversations = (data as List)
            .map((j) => Conversation.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load conversations. Pull to refresh or try again.';
      });
    }
  }

  List<Conversation> get _filtered {
    if (_search.trim().isEmpty) return _conversations;
    final q = _search.toLowerCase();
    return _conversations
        .where((c) => c.displayName.toLowerCase().contains(q))
        .toList();
  }

  bool _canDelete(Conversation c) {
    final auth = context.read<AuthProvider>().user;
    if (auth?.roleId == 1) return true;
    return c.createdBy != null && c.createdBy == auth?.userId;
  }

  Future<void> _delete(Conversation c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          'Delete "${c.displayName}"? This removes it for everyone and cannot be undone.',
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

    setState(() => _deletingId = c.conversationId);
    try {
      await ApiService.delete('/conversations/${c.conversationId}');
      setState(() {
        _conversations = _conversations
            .where((x) => x.conversationId != c.conversationId)
            .toList();
        _deletingId = null;
      });
    } catch (e) {
      setState(() => _deletingId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete conversation')),
        );
      }
    }
  }

  void _openConversation(Conversation c) {
    context.read<UnreadProvider>().markConversationRead(c.conversationId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConversationDetailScreen(conversationId: c.conversationId),
      ),
    );
  }

  Future<void> _openNewConversationSheet() async {
    final created = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewConversationSheet(),
    );
    if (created != null) {
      _fetch(showLoading: false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(conversationId: created),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMd().format(DateTime.now())),
        actions: [
          IconButton(
            onPressed: _openNewConversationSheet,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetch(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search conversations…',
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
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: _red, fontSize: 12.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 30,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _search.isNotEmpty
                                ? 'No matches'
                                : 'No conversations yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _search.isNotEmpty
                                ? 'Try a different search term.'
                                : 'Start one with anyone in the system.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final c in _filtered)
                      _ConversationRow(
                        conversation: c,
                        deletable: _canDelete(c),
                        deleting: _deletingId == c.conversationId,
                        onTap: () => _openConversation(c),
                        onDelete: () => _delete(c),
                      ),
                ],
              ),
            ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final Conversation conversation;
  final bool deletable;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationRow({
    required this.conversation,
    required this.deletable,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = conversation.isUnread;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: unread ? _accent.withValues(alpha: 0.05) : colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _accent,
                    child: Text(
                      initialsFor(conversation.displayName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (unread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.displayName,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: colors.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.lastActivityAt != null)
                          Text(
                            _relativeTime(conversation.lastActivityAt!),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: unread ? _accent : colors.onSurfaceVariant,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conversation.activityPreview,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: unread
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                        fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (deletable)
                deleting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    : IconButton(
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat.MMMd().format(dt);
  }
}

/// --- New conversation sheet ---
class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet();

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  List<Map<String, dynamic>> _users = [];
  final Set<int> _selected = {};
  String _search = '';
  final _groupNameController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final myId = context.read<AuthProvider>().user?.userId;
    try {
      final data = await ApiService.get('/users');
      setState(() {
        _users = (data as List)
            .cast<Map<String, dynamic>>()
            .where(
              (u) =>
                  (u['user_id'] is String
                      ? int.parse(u['user_id'])
                      : u['user_id'] as int) !=
                  myId,
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load the user directory.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      final first = (u['first_name'] as String? ?? '').toLowerCase();
      final last = (u['last_name'] as String? ?? '').toLowerCase();
      final username = (u['username'] as String? ?? '').toLowerCase();
      return first.contains(q) || last.contains(q) || username.contains(q);
    }).toList();
  }

  String _nameFor(Map<String, dynamic> u) {
    final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return full.isNotEmpty ? full : '@${u['username']}';
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_selected.isEmpty) {
      setState(() => _error = 'Pick at least one person');
      return;
    }
    setState(() => _submitting = true);
    try {
      final isGroup = _selected.length > 1;
      final data = await ApiService.post('/conversations', {
        'is_group': isGroup,
        if (isGroup && _groupNameController.text.trim().isNotEmpty)
          'conversation_name': _groupNameController.text.trim(),
        'member_ids': _selected.toList(),
      });
      final convId = (data['conversation']['conversation_id'] is String)
          ? int.parse(data['conversation']['conversation_id'])
          : data['conversation']['conversation_id'] as int;
      if (mounted) Navigator.of(context).pop(convId);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not start conversation');
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'New conversation',
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
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search people by name or username…',
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
              ),
            ),
            if (_selected.length > 1) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _groupNameController,
                decoration: InputDecoration(
                  hintText: 'Group name (optional)',
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
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
                ),
              ),
            ],
            const SizedBox(height: 10),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _filteredUsers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          _search.isNotEmpty
                              ? 'No matches found'
                              : 'No other users available',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, i) {
                        final u = _filteredUsers[i];
                        final userId = u['user_id'] is String
                            ? int.parse(u['user_id'])
                            : u['user_id'] as int;
                        final isSelected = _selected.contains(userId);
                        final hasNames =
                            (u['first_name'] != null) ||
                            (u['last_name'] != null);
                        final fullName = _nameFor(u);

                        return InkWell(
                          onTap: () => setState(
                            () => isSelected
                                ? _selected.remove(userId)
                                : _selected.add(userId),
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _accent.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: _accent,
                                  child: Text(
                                    initialsFor(fullName),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fullName,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: colors.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (hasNames)
                                        Text(
                                          '@${u['username']}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? colors.onSurface
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected
                                          ? colors.onSurface
                                          : colors.outlineVariant,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: colors.surface,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: _red, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 14),
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
                        'Start conversation',
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
}
