import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/conversation_member.dart';
import '../models/message.dart';
import '../models/reaction.dart';
import '../providers/auth_provider.dart';
import '../providers/unread_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../widgets/emoji_picker.dart';

const _accent = Color(0xFF3355FF);
const _red = Color(0xFFEF4444);
const _whatsappGreen = Color(0xFF25D366);
const _quickReactions = ['👍', '❤️', '😂', '🙏', '🔥', '🎉'];

class ConversationDetailScreen extends StatefulWidget {
  final int conversationId;
  const ConversationDetailScreen({super.key, required this.conversationId});

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  List<ChatMessage> _messages = [];
  List<ConversationMember> _members = [];
  Map<String, dynamic>? _meta;
  bool _loading = true;
  bool _sending = false;
  bool _showMembers = false;
  final Map<int, DateTime> _reads = {};
  final Set<int> _typingUserIds = {};

  ChatMessage? _replyingTo;
  ChatMessage? _editingMsg;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  late final void Function(dynamic) _onMessage;
  late final void Function(dynamic) _onEdited;
  late final void Function(dynamic) _onDeleted;
  late final void Function(dynamic) _onPinned;
  late final void Function(dynamic) _onReaction;
  late final void Function(dynamic) _onRead;
  late final void Function(dynamic) _onTyping;
  late final UnreadProvider _unread;

  @override
  void initState() {
    super.initState();
    _load();
    _unread = context.read<UnreadProvider>();
    _unread.setActiveConversation(widget.conversationId);
    _unread.markConversationRead(widget.conversationId);
    ApiService.post(
      '/conversations/${widget.conversationId}/read',
      {},
    ).catchError((_) => null);

    final ws = context.read<WebSocketProvider>();
    final myId = context.read<AuthProvider>().user?.userId;

    _onMessage = (payload) {
      final msg = payload['data']?['message'] ?? payload['message'];
      if (msg == null) return;
      final convId = msg['conversation_id'] is String
          ? int.parse(msg['conversation_id'])
          : msg['conversation_id'] as int;
      if (convId != widget.conversationId) return;
      final parsed = ChatMessage.fromJson(msg as Map<String, dynamic>);
      setState(() {
        final idx = _messages.indexWhere(
          (m) => m.messageId == parsed.messageId,
        );
        if (idx != -1) {
          _messages[idx] = parsed;
        } else {
          _messages.add(parsed);
        }
      });
      _scrollToBottomSoon();
    };
    _onEdited = (payload) => _updateMessage(
      payload,
      (m, data) => m.copyWith(
        message: data['message'] as String?,
        editedAt: DateTime.tryParse(data['edited_at'] as String? ?? ''),
      ),
    );
    _onDeleted = (payload) => _updateMessage(
      payload,
      (m, data) => m.copyWith(isDeleted: true, message: null),
    );
    _onPinned = (payload) => _updateMessage(
      payload,
      (m, data) => m.copyWith(isPinned: data['is_pinned'] as bool? ?? false),
    );
    _onReaction = (payload) {
      final d = payload['reaction'] ?? payload['data']?['reaction'] ?? payload;
      final convId = d['conversation_id'] is String
          ? int.parse(d['conversation_id'])
          : d['conversation_id'] as int;
      if (convId != widget.conversationId) return;
      final targetId = d['message_id'] is String
          ? int.parse(d['message_id'])
          : d['message_id'] as int;
      final from = d['user_id'] is String
          ? int.parse(d['user_id'])
          : d['user_id'] as int;
      setState(() {
        _messages = _messages.map((m) {
          if (m.messageId != targetId) return m;
          final others = m.reactions.where((r) => r.userId != from).toList();
          if (d['action'] == 'remove') return m.copyWith(reactions: others);
          return m.copyWith(
            reactions: [
              ...others,
              Reaction(
                userId: from,
                emoji: d['emoji'] as String,
                username: d['username'] as String?,
                firstName: d['first_name'] as String?,
                lastName: d['last_name'] as String?,
              ),
            ],
          );
        }).toList();
      });
    };
    _onRead = (payload) {
      final d = payload['read'] ?? payload;
      final convId = d['conversation_id'] is String
          ? int.parse(d['conversation_id'])
          : d['conversation_id'] as int;
      if (convId != widget.conversationId) return;
      final uid = d['user_id'] is String
          ? int.parse(d['user_id'])
          : d['user_id'] as int;
      setState(
        () => _reads[uid] =
            DateTime.tryParse(d['at'] as String? ?? '') ?? DateTime.now(),
      );
    };
    _onTyping = (payload) {
      final d = payload['typing'] ?? payload;
      final convId = d['conversation_id'] is String
          ? int.parse(d['conversation_id'])
          : d['conversation_id'] as int;
      if (convId != widget.conversationId) return;
      final uid = d['user_id'] is String
          ? int.parse(d['user_id'])
          : d['user_id'] as int;
      if (uid == myId) return;
      setState(() => _typingUserIds.add(uid));
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (mounted) setState(() => _typingUserIds.remove(uid));
      });
    };

    ws.on('message', _onMessage);
    ws.on('message_edited', _onEdited);
    ws.on('message_deleted', _onDeleted);
    ws.on('message_pinned', _onPinned);
    ws.on('reaction', _onReaction);
    ws.on('read', _onRead);
    ws.on('typing', _onTyping);
  }

  void _updateMessage(
    dynamic payload,
    ChatMessage Function(ChatMessage, Map<String, dynamic>) updater,
  ) {
    final msg = payload['message'] ?? payload;
    final convId = msg['conversation_id'] is String
        ? int.parse(msg['conversation_id'])
        : msg['conversation_id'] as int;
    if (convId != widget.conversationId) return;
    final targetId = msg['message_id'] is String
        ? int.parse(msg['message_id'])
        : msg['message_id'] as int;
    setState(() {
      _messages = _messages
          .map(
            (m) => m.messageId == targetId
                ? updater(m, msg as Map<String, dynamic>)
                : m,
          )
          .toList();
    });
  }

  @override
  void dispose() {
    final ws = context.read<WebSocketProvider>();
    ws.off('message', _onMessage);
    ws.off('message_edited', _onEdited);
    ws.off('message_deleted', _onDeleted);
    ws.off('message_pinned', _onPinned);
    ws.off('reaction', _onReaction);
    ws.off('read', _onRead);
    ws.off('typing', _onTyping);
    _unread.setActiveConversation(null);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.get('/conversations/${widget.conversationId}/messages'),
        ApiService.get('/conversations/${widget.conversationId}/members'),
        ApiService.get('/conversations'),
        ApiService.get('/conversations/${widget.conversationId}/reads'),
      ]);
      final msgs = (results[0] as List)
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final members = (results[1] as List)
          .map((j) => ConversationMember.fromJson(j as Map<String, dynamic>))
          .toList();
      final allConvs = results[2] as List;
      final meta = allConvs.cast<Map<String, dynamic>>().firstWhere(
        (c) =>
            (c['conversation_id'] is String
                ? int.parse(c['conversation_id'])
                : c['conversation_id']) ==
            widget.conversationId,
        orElse: () => {},
      );
      for (final r in (results[3] as List)) {
        final row = r as Map<String, dynamic>;
        final uid = row['user_id'] is String
            ? int.parse(row['user_id'])
            : row['user_id'] as int;
        _reads[uid] =
            DateTime.tryParse(row['last_read_at'] as String? ?? '') ??
            DateTime.now();
      }
      setState(() {
        _messages = msgs;
        _members = members;
        _meta = meta.isEmpty ? null : meta;
        _loading = false;
      });
      _scrollToBottomSoon(animated: false);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _scrollToBottomSoon({bool animated = true}) {
    // Wait for the next frame, then give the list a moment to lay out
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!_scrollController.hasClients) return;
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (animated) {
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(maxExtent);
        }
      });
    });
  }

  bool get _isGroup => (_meta?['is_group'] as bool?) ?? _members.length > 2;

  bool get _canManage {
    final auth = context.read<AuthProvider>().user;
    if (auth?.roleId == 1) return true;
    final createdBy = _meta?['created_by'];
    if (createdBy == null) return false;
    final createdByInt = createdBy is String
        ? int.parse(createdBy)
        : createdBy as int;
    return createdByInt == auth?.userId;
  }

  ConversationMember? get _otherMember {
    final myId = context.read<AuthProvider>().user?.userId;
    try {
      return _members.firstWhere((m) => m.userId != myId);
    } catch (_) {
      return null;
    }
  }

  String get _title {
    final name = _meta?['conversation_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final myId = context.read<AuthProvider>().user?.userId;
    final others = _members.where((m) => m.userId != myId).toList();
    if (others.isEmpty) return 'Conversation';
    final first = others.first.displayName;
    return others.length == 1 ? first : '$first +${others.length - 1} more';
  }

  String? _memberName(int userId) {
    try {
      return _members.firstWhere((m) => m.userId == userId).displayName;
    } catch (_) {
      return 'User $userId';
    }
  }

  String? _normalizePhone(String? phone) {
    if (phone == null) return null;
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 8 ? digits : null;
  }

  Future<void> _openWhatsApp(String? phone) async {
    final n = _normalizePhone(phone);
    if (n == null) return;
    await launchUrl(
      Uri.parse('https://wa.me/$n'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openDialer(String? phone) async {
    final n = _normalizePhone(phone);
    if (n == null) return;
    await launchUrl(Uri.parse('tel:+$n'));
  }

  void _onTextChanged(String v) {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds > 2500) {
      _lastTypingSent = now;
      ApiService.post(
        '/conversations/${widget.conversationId}/typing',
        {},
      ).catchError((_) => null);
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    if (_editingMsg != null) {
      final target = _editingMsg!;
      setState(() {
        _editingMsg = null;
        _textController.clear();
        _messages = _messages
            .map(
              (m) => m.messageId == target.messageId
                  ? m.copyWith(message: text, editedAt: DateTime.now())
                  : m,
            )
            .toList();
      });
      try {
        await ApiService.patch(
          '/conversations/${widget.conversationId}/messages/${target.messageId}',
          {'message': text},
        );
      } catch (e) {
        _load();
      }
      return;
    }

    final replyId = _replyingTo?.messageId;
    final optimisticId = -DateTime.now().millisecondsSinceEpoch;
    final myId = context.read<AuthProvider>().user!.userId;
    final optimistic = ChatMessage(
      messageId: optimisticId,
      conversationId: widget.conversationId,
      senderId: myId,
      message: text,
      createdAt: DateTime.now(),
      replyToMessageId: replyId,
      replyMessage: _replyingTo?.message,
      replySenderId: _replyingTo?.senderId,
    );

    setState(() {
      _messages.add(optimistic);
      _textController.clear();
      _replyingTo = null;
      _sending = true;
    });
    _scrollToBottomSoon();

    try {
      final data = await ApiService.post(
        '/conversations/${widget.conversationId}/messages',
        {'message': text, 'reply_to_message_id': ?replyId},
      );
      final saved = ChatMessage.fromJson(
        (data['message'] ?? data) as Map<String, dynamic>,
      );
      setState(() {
        _messages = _messages
            .map((m) => m.messageId == optimisticId ? saved : m)
            .toList();
      });
    } catch (e) {
      setState(() => _messages.removeWhere((m) => m.messageId == optimisticId));
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _react(int messageId, String emoji) async {
    if (messageId < 0) return;
    final myId = context.read<AuthProvider>().user!.userId;
    final target = _messages.firstWhere((m) => m.messageId == messageId);
    final mine = target.reactions.where((r) => r.userId == myId).firstOrNull;
    final toggleOff = mine?.emoji == emoji;
    final user = context.read<AuthProvider>().user!;

    setState(() {
      _messages = _messages.map((m) {
        if (m.messageId != messageId) return m;
        final others = m.reactions.where((r) => r.userId != myId).toList();
        final next = toggleOff
            ? others
            : [
                ...others,
                Reaction(userId: myId, emoji: emoji, username: user.username),
              ];
        return m.copyWith(reactions: next);
      }).toList();
    });

    try {
      if (toggleOff) {
        await ApiService.delete(
          '/conversations/${widget.conversationId}/messages/$messageId/reactions',
        );
      } else {
        await ApiService.post(
          '/conversations/${widget.conversationId}/messages/$messageId/reactions',
          {'emoji': emoji},
        );
      }
    } catch (e) {
      _load();
    }
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this message?'),
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

    setState(() {
      _messages = _messages
          .map(
            (m) => m.messageId == msg.messageId
                ? m.copyWith(isDeleted: true, message: null)
                : m,
          )
          .toList();
    });
    try {
      await ApiService.delete(
        '/conversations/${widget.conversationId}/messages/${msg.messageId}',
      );
    } catch (e) {
      _load();
    }
  }

  Future<void> _togglePin(ChatMessage msg) async {
    final next = !msg.isPinned;
    setState(() {
      _messages = _messages
          .map(
            (m) =>
                m.messageId == msg.messageId ? m.copyWith(isPinned: next) : m,
          )
          .toList();
    });
    try {
      await ApiService.post(
        '/conversations/${widget.conversationId}/messages/${msg.messageId}/pin',
        {'pinned': next},
      );
    } catch (e) {
      _load();
    }
  }

  void _startReply(ChatMessage msg) => setState(() {
    _editingMsg = null;
    _replyingTo = msg;
  });

  void _startEdit(ChatMessage msg) => setState(() {
    _replyingTo = null;
    _editingMsg = msg;
    _textController.text = msg.message ?? '';
  });

  Future<void> _removeMember(ConversationMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${m.displayName} from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.delete(
        '/conversations/${widget.conversationId}/members/${m.userId}',
      );
      setState(
        () => _members = _members.where((x) => x.userId != m.userId).toList(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove member')),
        );
      }
    }
  }

  Future<void> _replyPrivately(ConversationMember m) async {
    Navigator.of(context).pop();
    try {
      final data = await ApiService.post('/conversations', {
        'is_group': false,
        'member_ids': [m.userId],
      });
      final convId = data['conversation']['conversation_id'] is String
          ? int.parse(data['conversation']['conversation_id'])
          : data['conversation']['conversation_id'] as int;
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConversationDetailScreen(conversationId: convId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open private chat')),
        );
      }
    }
  }

  void _openMemberSheet(ConversationMember m) {
    final myId = context.read<AuthProvider>().user?.userId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberSheet(
        member: m,
        isGroup: _isGroup,
        canManage: _canManage && m.userId != myId,
        onRemove: () => _removeMember(m),
        onReplyPrivately: _isGroup ? () => _replyPrivately(m) : null,
        onWhatsApp: () => _openWhatsApp(m.phone),
        onCall: () => _openDialer(m.phone),
      ),
    );
  }

  void _openActionMenu(ChatMessage msg) {
    final myId = context.read<AuthProvider>().user?.userId;
    final mine = msg.senderId == myId;
    final isAdmin = context.read<AuthProvider>().user?.roleId == 1;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: _quickReactions
                      .map(
                        (e) => Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              _react(msg.messageId, e);
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                e,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(context).pop();
                  _startReply(msg);
                },
              ),
              if (mine && msg.messageId > 0)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _startEdit(msg);
                  },
                ),
              ListTile(
                leading: Icon(
                  msg.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(msg.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.of(context).pop();
                  _togglePin(msg);
                },
              ),
              if ((mine || isAdmin) && msg.messageId > 0)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: _red),
                  title: const Text('Delete', style: TextStyle(color: _red)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _deleteMessage(msg);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionViewer(String emoji, List<String> names) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(
                  '${names.length}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final n in names)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(n),
              ),
          ],
        ),
      ),
    );
  }

  void _openEmojiPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: EmojiPickerPanel(
          onSelect: (emoji) {
            Navigator.of(context).pop();
            _textController.text += emoji;
          },
        ),
      ),
    );
  }

  bool _isSeenByOthers(ChatMessage msg) {
    final myId = context.read<AuthProvider>().user?.userId;
    for (final entry in _reads.entries) {
      if (entry.key == myId) continue;
      if (!entry.value.isBefore(msg.createdAt)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final myId = context.read<AuthProvider>().user?.userId;
    final pinned = _messages.where((m) => m.isPinned && !m.isDeleted).toList();
    final headerName = _title;
    final otherPhone = !_isGroup ? _otherMember?.phone : null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            if (!_isGroup && _otherMember != null) {
              _openMemberSheet(_otherMember!);
            }
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: _accent,
                child: Text(
                  _isGroup ? 'G' : (_otherMember?.initials ?? 'C'),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      headerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _typingUserIds.isNotEmpty
                          ? '${_typingUserIds.map((id) => _memberName(id)?.split(' ').first ?? '').join(', ')} typing…'
                          : (_isGroup
                                ? '${_members.length} members'
                                : (_otherMember?.isAvailable == true
                                      ? 'Available'
                                      : 'Tap to view profile')),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _typingUserIds.isNotEmpty
                            ? _accent
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!_isGroup && otherPhone != null)
            IconButton(
              onPressed: () => _openWhatsApp(otherPhone),
              // Updated to use the FontAwesome WhatsApp icon
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                color: _whatsappGreen,
              ),
              tooltip: 'WhatsApp',
            ),
          IconButton(
            onPressed: () => setState(() => _showMembers = !_showMembers),
            icon: const Icon(Icons.people_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (pinned.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: _accent.withValues(alpha: 0.06),
                    child: Row(
                      children: [
                        const Icon(Icons.push_pin, size: 14, color: _accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pinned${pinned.length > 1 ? ' · ${pinned.length}' : ''} — ${pinned.first.message}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: _accent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_showMembers)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _members.length,
                      itemBuilder: (context, i) {
                        final m = _members[i];
                        final isMe = m.userId == myId;
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: _accent,
                            child: Text(
                              m.initials,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Text(
                            '${m.displayName}${isMe ? ' (you)' : ''}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _openMemberSheet(m),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            'No messages yet — say hello 👋',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final msg = _messages[i];
                            final mine = msg.senderId == myId;
                            final showDateHeader =
                                i == 0 ||
                                !_sameDay(
                                  _messages[i - 1].createdAt,
                                  msg.createdAt,
                                );
                            final isLastOfMine =
                                mine && i == _messages.length - 1;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDateHeader)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          _dateHeading(msg.createdAt),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: colors.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                _MessageBubble(
                                  key: ValueKey(msg.messageId),
                                  message: msg,
                                  mine: mine,
                                  senderName: !mine && _isGroup
                                      ? _memberName(msg.senderId)
                                      : null,
                                  replyFromName: msg.replySenderId != null
                                      ? _memberName(msg.replySenderId!)
                                      : null,
                                  seen:
                                      isLastOfMine &&
                                      !msg.isDeleted &&
                                      _isSeenByOthers(msg),
                                  onLongPress: () => _openActionMenu(msg),
                                  onSwipeReply: () => _startReply(msg),
                                  onReplyTap: msg.replyToMessageId != null
                                      ? () => _scrollToMessage(
                                          msg.replyToMessageId!,
                                        )
                                      : null,
                                  onReactTap: (emoji) =>
                                      _react(msg.messageId, emoji),
                                  onReactionLongPress: (emoji, names) =>
                                      _showReactionViewer(emoji, names),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                if (_replyingTo != null || _editingMsg != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: colors.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Container(width: 3, height: 30, color: _accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _editingMsg != null
                                    ? 'Editing message'
                                    : 'Replying to ${_replyingTo!.senderId == myId ? 'yourself' : (_memberName(_replyingTo!.senderId) ?? '')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                              Text(
                                _editingMsg?.message ??
                                    _replyingTo?.message ??
                                    '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _replyingTo = null;
                            _editingMsg = null;
                            _textController.clear();
                          }),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    8,
                    8,
                    8 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          onChanged: _onTextChanged,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: _editingMsg != null
                                ? 'Edit your message…'
                                : 'Type a message…',
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              onPressed: _openEmojiPicker,
                              icon: Icon(
                                Icons.emoji_emotions_outlined,
                                size: 20,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _sending ? null : _send,
                        child: Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateHeading(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_sameDay(d, yesterday)) return 'Yesterday';
    return DateFormat.yMMMMd().format(d);
  }

  void _scrollToMessage(int messageId) {
    final index = _messages.indexWhere((m) => m.messageId == messageId);
    if (index == -1) return;
    // Approximate scroll — ListView.builder doesn't give exact offsets
    // without a fixed item extent, so this jumps proportionally rather
    // than pixel-precisely. Good enough to bring the message on-screen.
    if (_scrollController.hasClients) {
      final target =
          (_scrollController.position.maxScrollExtent) *
          (index / _messages.length);
      _scrollController.animateTo(
        target.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
}

/// A single message bubble with swipe-to-reply and long-press actions.
class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool mine;
  final String? senderName;
  final String? replyFromName;
  final bool seen;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback? onReplyTap;
  final void Function(String emoji) onReactTap;
  final void Function(String emoji, List<String> names) onReactionLongPress;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.senderName,
    this.replyFromName,
    required this.seen,
    required this.onLongPress,
    required this.onSwipeReply,
    this.onReplyTap,
    required this.onReactTap,
    required this.onReactionLongPress,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  double _dragOffset = 0;
  static const _swipeThreshold = 60.0;

  Map<String, List<String>> _groupedReactions() {
    final map = <String, List<String>>{};
    for (final r in widget.message.reactions) {
      map.putIfAbsent(r.emoji, () => []).add(r.displayName);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final msg = widget.message;
    final grouped = _groupedReactions();

    return GestureDetector(
      onLongPress: msg.isDeleted ? null : widget.onLongPress,
      onHorizontalDragUpdate: (details) {
        setState(
          () =>
              _dragOffset = (_dragOffset + details.delta.dx).clamp(-70.0, 0.0),
        );
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() > _swipeThreshold) widget.onSwipeReply();
        setState(() => _dragOffset = 0);
      },
      child: Stack(
        alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          if (_dragOffset != 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.reply,
                size: 18,
                color: colors.onSurfaceVariant.withValues(
                  alpha: (_dragOffset.abs() / _swipeThreshold).clamp(0, 1),
                ),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: widget.mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (widget.senderName != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 2),
                    child: Text(
                      widget.senderName!,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      gradient: widget.mine
                          ? const LinearGradient(
                              colors: [_accent, Color(0xFF2543E0)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: widget.mine
                          ? null
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(widget.mine ? 16 : 4),
                        bottomRight: Radius.circular(widget.mine ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.replyToMessageId != null && !msg.isDeleted)
                          GestureDetector(
                            onTap: widget.onReplyTap,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: widget.mine
                                        ? Colors.white70
                                        : _accent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.replyFromName ?? 'Reply',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: widget.mine
                                          ? Colors.white70
                                          : _accent,
                                    ),
                                  ),
                                  Text(
                                    msg.replyMessage ?? 'Original message',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: widget.mine
                                          ? Colors.white60
                                          : colors.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (msg.isDeleted)
                          Text(
                            'This message was deleted',
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: widget.mine
                                  ? Colors.white70
                                  : colors.onSurfaceVariant,
                            ),
                          )
                        else
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 14,
                                color: widget.mine
                                    ? Colors.white
                                    : colors.onSurface,
                              ),
                              children: [
                                TextSpan(text: msg.message ?? ''),
                                if (msg.editedAt != null)
                                  TextSpan(
                                    text: '  (edited)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: widget.mine
                                          ? Colors.white60
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (grouped.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 4,
                      children: grouped.entries.map((e) {
                        return GestureDetector(
                          onTap: () => widget.onReactTap(e.key),
                          onLongPress: () =>
                              widget.onReactionLongPress(e.key, e.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              border: Border.all(color: colors.outlineVariant),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  e.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${e.value.length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat.jm().format(msg.createdAt),
                        style: TextStyle(
                          fontSize: 9.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (widget.mine) ...[
                        const SizedBox(width: 3),
                        Icon(
                          msg.messageId < 0
                              ? Icons.schedule
                              : (widget.seen ? Icons.done_all : Icons.done),
                          size: 12,
                          color: widget.seen
                              ? _accent
                              : colors.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// --- Member bottom sheet ---
class _MemberSheet extends StatelessWidget {
  final ConversationMember member;
  final bool isGroup;
  final bool canManage;
  final VoidCallback onRemove;
  final VoidCallback? onReplyPrivately;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;

  const _MemberSheet({
    required this.member,
    required this.isGroup,
    required this.canManage,
    required this.onRemove,
    this.onReplyPrivately,
    required this.onWhatsApp,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasPhone = member.phone != null && member.phone!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: colors.onSurface),
            ),
          ),
          CircleAvatar(
            radius: 36,
            backgroundColor: _accent,
            child: Text(
              member.initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            member.displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
          ),
          if (member.username != null)
            Text(
              '@${member.username}',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          if (member.isAvailable != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    (member.isAvailable!
                            ? const Color(0xFF10B981)
                            : colors.onSurfaceVariant)
                        .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                member.isAvailable! ? 'Available' : 'Unavailable',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: member.isAvailable!
                      ? const Color(0xFF10B981)
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (isGroup && onReplyPrivately != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReplyPrivately,
                icon: const Icon(Icons.reply, size: 17, color: _accent),
                label: const Text(
                  'Message privately',
                  style: TextStyle(color: _accent),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (hasPhone)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onWhatsApp,
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                    label: const Text('Message'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _whatsappGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.onSurface,
                      foregroundColor: colors.surface,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  'No phone number on file',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (isGroup && canManage) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.person_remove_outlined,
                  size: 17,
                  color: _red,
                ),
                label: const Text(
                  'Remove from group',
                  style: TextStyle(color: _red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
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
