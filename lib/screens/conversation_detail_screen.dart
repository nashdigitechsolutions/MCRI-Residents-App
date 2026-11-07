import 'package:mcri_residents_app/widgets/app_loader.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:mcri_residents_app/models/conversation.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/conversation_member.dart';
import '../models/message.dart';
import '../models/reaction.dart';
import '../providers/auth_provider.dart';
import '../providers/unread_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../utils/haptics.dart';
import '../utils/linkify.dart';
import '../widgets/forward_sheet.dart';
import '../widgets/emoji_picker.dart';

const _accent = AppColors.primary;
const _red = AppColors.danger;
const _whatsappGreen = Color(0xFF25D366);
const _quickReactions = ['👍', '❤️', '😂', '🙏', '🔥', '🎉'];

class ConversationDetailScreen extends StatefulWidget {
  final int conversationId;
  final Conversation? initial;
  const ConversationDetailScreen({
    super.key,
    required this.conversationId,
    this.initial,
  });

  static final Map<int, List<ChatMessage>> _messageCache = {
    // for (final c in ConversationDetailScreen._messageCache.entries)
    //   c.key: List.of(c.value),
  };

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();

  /// The chat currently on screen, so notifications for it can be skipped.
  static int? openConversationId;

  static void clearCache() {
    _messageCache.clear();
  }
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen>
    with WidgetsBindingObserver {
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

  // ── Multi-select (long-press → Select), WhatsApp-style ──
  final Set<int> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;
  List<ChatMessage> get _selectedMessages =>
      _messages.where((m) => _selectedIds.contains(m.messageId)).toList();

  // ── In-chat search ──
  bool _searching = false;
  String _query = '';
  List<int> _hits = []; // message ids, oldest → newest
  int _hitIndex = -1;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final Map<int, GlobalKey> _bubbleKeys = {};
  GlobalKey _keyFor(int id) => _bubbleKeys.putIfAbsent(id, GlobalKey.new);
  int? get _currentHitId =>
      _hitIndex >= 0 && _hitIndex < _hits.length ? _hits[_hitIndex] : null;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  late final void Function(dynamic) _onMessage;
  late final void Function(dynamic) _onEdited;
  late final void Function(dynamic) _onDeleted;
  late final void Function(dynamic) _onPinned;
  late final void Function(dynamic) _onReaction;
  late final void Function(dynamic) _onRead;
  late final void Function(dynamic) _onTyping;
  late final UnreadProvider _unread;
  late final WebSocketProvider _ws;

  @override
  void initState() {
    super.initState();
    ConversationDetailScreen.openConversationId = widget.conversationId;
    final cached =
        ConversationDetailScreen._messageCache[widget.conversationId];
    if (cached != null) {
      _messages = List.of(cached);
      _loading = false; // we already have something to show
    }
    final init = widget.initial;
    _meta = {
      'conversation_id': init?.conversationId,
      'conversation_name': init?.conversationName,
      'is_group': init?.isGroup,
      'created_by': init?.createdBy,
    };
    _load();
    _unread = context.read<UnreadProvider>();
    // However this chat was opened (list, push, banner): it's now read,
    // the badge drops immediately and the server + other devices are told.
    _unread.openConversation(widget.conversationId);

    _ws = context.read<WebSocketProvider>();
    // Catch up on anything sent while the socket was down (cold start from a
    // notification, network drop) or the app was in the background.
    _wasSocketConnected = _ws.isConnected;
    _ws.addListener(_onSocketState);
    WidgetsBinding.instance.addObserver(this);
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

    _ws.on('message', _onMessage);
    _ws.on('message_edited', _onEdited);
    _ws.on('message_deleted', _onDeleted);
    _ws.on('message_pinned', _onPinned);
    _ws.on('reaction', _onReaction);
    _ws.on('read', _onRead);
    _ws.on('typing', _onTyping);
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
    if (ConversationDetailScreen.openConversationId == widget.conversationId) {
      ConversationDetailScreen.openConversationId = null;
    }
    ConversationDetailScreen._messageCache[widget.conversationId] = _messages
        .where((m) => m.messageId > 0)
        .toList();
    _ws.off('message', _onMessage);
    _ws.off('message_edited', _onEdited);
    _ws.off('message_deleted', _onDeleted);
    _ws.off('message_pinned', _onPinned);
    _ws.off('reaction', _onReaction);
    _ws.off('read', _onRead);
    _ws.off('typing', _onTyping);
    _ws.removeListener(_onSocketState);
    WidgetsBinding.instance.removeObserver(this);
    _unread.closeConversation(widget.conversationId);
    _textController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _wasSocketConnected = false;

  void _onSocketState() {
    final connected = _ws.isConnected;
    if (connected && !_wasSocketConnected && mounted) {
      _load();
      _unread.markConversationRead(widget.conversationId, syncServer: true);
    }
    _wasSocketConnected = connected;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _load();
      _unread.openConversation(widget.conversationId);
    }
  }

  Future<dynamic> _try(Future<dynamic> Function() request) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await request();
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          if (!mounted) return null;
        }
      }
    }
    return null;
  }

  Future<void> _load() async {
    final id = widget.conversationId;
    // Fire everything at once, but never block the messages on the rest.
    final messagesF = _try(() => ApiService.get('/conversations/$id/messages'));
    final membersF = _try(() => ApiService.get('/conversations/$id/members'));
    final readsF = _try(() => ApiService.get('/conversations/$id/reads'));
    final metaF = Future<dynamic>.value(null);

    final rawMsgs = await messagesF;
    if (!mounted) return;
    if (rawMsgs is List) {
      final msgs =
          rawMsgs
              .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
              .toList()
            ..sort(
              (a, b) => a.createdAt.compareTo(b.createdAt),
            ); // oldest first
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottomSoon(animated: false);
    } else {
      setState(() => _loading = false);
    }

    final rawMembers = await membersF;
    if (mounted && rawMembers is List) {
      setState(
        () => _members = rawMembers
            .map((j) => ConversationMember.fromJson(j as Map<String, dynamic>))
            .toList(),
      );
    }

    final rawReads = await readsF;
    if (mounted && rawReads is List) {
      setState(() {
        for (final r in rawReads) {
          final row = r as Map<String, dynamic>;
          final uid = row['user_id'] is String
              ? int.parse(row['user_id'])
              : row['user_id'] as int;
          _reads[uid] =
              DateTime.tryParse(row['last_read_at'] as String? ?? '') ??
              DateTime.now();
        }
      });
    }

    final rawMeta = await metaF;
    if (mounted && rawMeta is List) {
      final found = rawMeta.cast<Map<String, dynamic>>().where(
        (c) =>
            (c['conversation_id'] is String
                ? int.parse(c['conversation_id'])
                : c['conversation_id']) ==
            id,
      );
      if (found.isNotEmpty) setState(() => _meta = found.first);
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

  String? get _title {
    final name = _meta?['conversation_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    if (_members.isEmpty) return widget.initial?.displayName;
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
      _try(
        () => ApiService.post(
          '/conversations/${widget.conversationId}/typing',
          {},
        ),
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
        await _try(
          () => ApiService.patch(
            '/conversations/${widget.conversationId}/messages/${target.messageId}',
            {'message': text},
          ),
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
      final data = await _try(
        () => ApiService.post(
          '/conversations/${widget.conversationId}/messages',
          {'message': text, 'reply_to_message_id': replyId},
        ),
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
        await _try(
          () => ApiService.delete(
            '/conversations/${widget.conversationId}/messages/$messageId/reactions',
          ),
        );
      } else {
        await _try(
          () => ApiService.post(
            '/conversations/${widget.conversationId}/messages/$messageId/reactions',
            {'emoji': emoji},
          ),
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
      await _try(
        () => ApiService.delete(
          '/conversations/${widget.conversationId}/messages/${msg.messageId}',
        ),
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
      await _try(
        () => ApiService.post(
          '/conversations/${widget.conversationId}/messages/${msg.messageId}/pin',
          {'pinned': next},
        ),
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
      await _try(
        () => ApiService.delete(
          '/conversations/${widget.conversationId}/members/${m.userId}',
        ),
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
      final data = await _try(
        () => ApiService.post('/conversations', {
          'is_group': false,
          'member_ids': [m.userId],
        }),
      );
      final convId = data['conversation']['conversation_id'] is String
          ? int.parse(data['conversation']['conversation_id'])
          : data['conversation']['conversation_id'] as int;
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ConversationDetailScreen(conversationId: convId, initial: null),
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

  void _toggleSelected(ChatMessage msg) {
    if (msg.isDeleted || msg.messageId <= 0) return;
    AppHaptics.selection();
    setState(() {
      if (!_selectedIds.remove(msg.messageId)) _selectedIds.add(msg.messageId);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  String _plain(ChatMessage m) => stripForwarded(m.message ?? '');

  /// One message: its text. Several: WhatsApp-style "[time] Name: text".
  Future<void> _copy(List<ChatMessage> msgs) async {
    if (msgs.isEmpty) return;
    final myId = context.read<AuthProvider>().user?.userId;
    final text = msgs.length == 1
        ? _plain(msgs.first)
        : msgs
              .map((m) {
                final who = m.senderId == myId
                    ? 'You'
                    : (_memberName(m.senderId) ?? 'Member');
                final at = DateFormat('dd/MM HH:mm').format(m.createdAt);
                return '[$at] $who: ${_plain(m)}';
              })
              .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msgs.length == 1
              ? 'Message copied'
              : '${msgs.length} messages copied',
        ),
      ),
    );
  }

  Future<void> _forward(List<ChatMessage> msgs) async {
    if (msgs.isEmpty) return;
    final texts = msgs
        .map((m) => m.message ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();
    final chats = await showForwardSheet(
      context,
      messages: texts,
      excludeConversationId: widget.conversationId,
    );
    if (!mounted || chats == 0) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Forwarded to $chats chat${chats == 1 ? '' : 's'}'),
      ),
    );
  }

  /// Opens the message in a sheet where any part of it can be selected.
  void _selectText(ChatMessage msg) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select text',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copy([msg]);
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _plain(msg),
                    style: const TextStyle(fontSize: 16, height: 1.45),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Press and drag to select, then tap Copy.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSelectionBar(ColorScheme colors) {
    final msgs = _selectedMessages;
    final auth = context.read<AuthProvider>();
    final myId = auth.user?.userId;
    final canDelete =
        msgs.isNotEmpty &&
        msgs.every((m) => m.senderId == myId || auth.isAdmin);
    return AppBar(
      backgroundColor: colors.primaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Cancel',
        onPressed: _clearSelection,
      ),
      title: Text('${msgs.length} selected'),
      actions: [
        if (msgs.length == 1)
          IconButton(
            tooltip: 'Reply',
            icon: const Icon(Icons.reply_rounded),
            onPressed: () {
              final m = msgs.first;
              _clearSelection();
              _startReply(m);
            },
          ),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () => _copy(msgs),
        ),
        IconButton(
          tooltip: 'Forward',
          icon: const Icon(Icons.shortcut_rounded),
          onPressed: () => _forward(msgs),
        ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded, color: _red),
            onPressed: () async {
              final toDelete = List.of(msgs);
              _clearSelection();
              for (final m in toDelete) {
                await _deleteMessage(m);
              }
            },
          ),
      ],
    );
  }

  void _openActionMenu(ChatMessage msg) {
    final myId = context.read<AuthProvider>().user?.userId;
    final mine = msg.senderId == myId;
    final isAdmin = context.read<AuthProvider>().user?.roleId == 1;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // The menu has grown (copy, select, forward…): let it be tall and
      // scroll on small phones instead of overflowing.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => SafeArea(
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
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
                if (!msg.isDeleted) ...[
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copy'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _copy([msg]);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.text_fields_rounded),
                    title: const Text('Select text'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _selectText(msg);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.shortcut_rounded),
                    title: const Text('Forward'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _forward([msg]);
                    },
                  ),
                  if (msg.messageId > 0)
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline_rounded),
                      title: const Text('Select'),
                      subtitle: const Text(
                        'Pick several messages to copy or forward',
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _toggleSelected(msg);
                      },
                    ),
                ],
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

  /// 0 = sent, 1 = read by some of the others (groups), 2 = read by all.
  int _readState(ChatMessage msg) {
    final myId = context.read<AuthProvider>().user?.userId;
    final others = _members
        .where((m) => m.userId != myId)
        .map((m) => m.userId)
        .toSet();
    var read = 0;
    for (final entry in _reads.entries) {
      if (entry.key == myId) continue;
      if (others.isNotEmpty && !others.contains(entry.key)) continue;
      if (!entry.value.isBefore(msg.createdAt)) read++;
    }
    if (read == 0) return 0;
    final total = others.isEmpty ? read : others.length;
    return read >= total ? 2 : 1;
  }

  PreferredSizeWidget _buildSearchBar(ColorScheme colors) {
    final total = _hits.length;
    final label = _query.isEmpty
        ? ''
        : (total == 0 ? 'No matches' : '${_hitIndex + 1} of $total');
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Close search',
        onPressed: _toggleSearch,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: _runSearch,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _stepHit(older: true),
        style: TextStyle(fontSize: 15, color: colors.onSurface),
        decoration: const InputDecoration(
          hintText: 'Search messages',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
        ),
      ),
      actions: [
        if (label.isNotEmpty)
          Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: total == 0 ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
        IconButton(
          tooltip: 'Older match',
          onPressed: total > 1 ? () => _stepHit(older: true) : null,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          tooltip: 'Newer match',
          onPressed: total > 1 ? () => _stepHit(older: false) : null,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final myId = context.read<AuthProvider>().user?.userId;
    final pinned = _messages.where((m) => m.isPinned && !m.isDeleted).toList();
    final headerName = _title ?? (_loading ? 'Loading…' : 'Conversation');
    final otherPhone = !_isGroup ? _otherMember?.phone : null;

    // Back leaves selection / search mode before leaving the chat.
    return PopScope(
      canPop: !_selecting && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else if (_searching) {
          _toggleSearch();
        }
      },
      child: Scaffold(
        appBar: _selecting
            ? _buildSelectionBar(colors)
            : _searching
            ? _buildSearchBar(colors)
            : AppBar(
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
                    onPressed: _toggleSearch,
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search in chat',
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showMembers = !_showMembers),
                    icon: const Icon(Icons.people_outline),
                  ),
                ],
              ),
        body: Column(
          children: [
            // Refreshing over cached messages: a small, non-blocking pill.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _loading && _messages.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppLoader(size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Updating…',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
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
                        style: const TextStyle(fontSize: 11.5, color: _accent),
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
                  ? (_loading
                        ? const AppLoadingView(message: 'Loading messages…')
                        : Center(
                            child: Text(
                              'No messages yet — say hello 👋',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ))
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
                                      borderRadius: BorderRadius.circular(999),
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
                            GestureDetector(
                              // In selection mode a tap (or long-press) picks
                              // the message instead of the bubble's own actions.
                              behavior: HitTestBehavior.opaque,
                              onTap: _selecting
                                  ? () => _toggleSelected(msg)
                                  : null,
                              onLongPress: _selecting
                                  ? () => _toggleSelected(msg)
                                  : null,
                              child: AbsorbPointer(
                                absorbing: _selecting,
                                child: AnimatedContainer(
                                  key: _keyFor(msg.messageId),
                                  duration: const Duration(milliseconds: 250),
                                  decoration: BoxDecoration(
                                    color: _selectedIds.contains(msg.messageId)
                                        ? _accent.withValues(alpha: 0.18)
                                        : _currentHitId == msg.messageId
                                        ? _accent.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                  ),
                                  child: _MessageBubble(
                                    key: ValueKey(msg.messageId),
                                    message: msg,
                                    mine: mine,
                                    highlight: _searching && _query.isNotEmpty
                                        ? _query
                                        : null,
                                    senderName: !mine && _isGroup
                                        ? _memberName(msg.senderId)
                                        : null,
                                    replyFromName: msg.replySenderId != null
                                        ? _memberName(msg.replySenderId!)
                                        : null,
                                    // Ticks on EVERY message of mine, not
                                    // just the last one.
                                    readState: mine && !msg.isDeleted
                                        ? _readState(msg)
                                        : 0,
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
                                ),
                              ),
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
                            _editingMsg?.message ?? _replyingTo?.message ?? '',
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
                border: Border(top: BorderSide(color: colors.outlineVariant)),
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: _sending
                            ? const Padding(
                                key: ValueKey('sending'),
                                padding: EdgeInsets.all(10),
                                child: AppLoader(color: Colors.white),
                              )
                            : const Icon(
                                Icons.send,
                                key: ValueKey('send'),
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  /// Opens/closes search. Results are computed over the loaded history.
  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _hits = [];
        _hitIndex = -1;
        _searchController.clear();
      }
    });
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchFocus.requestFocus(),
      );
    }
  }

  void _runSearch(String q) {
    final needle = q.trim().toLowerCase();
    final hits = needle.isEmpty
        ? <int>[]
        : _messages
              .where(
                (m) =>
                    !m.isDeleted &&
                    (m.message ?? '').toLowerCase().contains(needle),
              )
              .map((m) => m.messageId)
              .toList();
    setState(() {
      _query = q.trim();
      _hits = hits;
      _hitIndex = hits.isEmpty ? -1 : hits.length - 1; // newest match first
    });
    if (hits.isNotEmpty) _jumpToHit();
  }

  /// [older] = true moves up the conversation (earlier messages).
  void _stepHit({required bool older}) {
    if (_hits.isEmpty) return;
    setState(() {
      _hitIndex = older
          ? (_hitIndex - 1 + _hits.length) % _hits.length
          : (_hitIndex + 1) % _hits.length;
    });
    _jumpToHit();
  }

  void _jumpToHit() {
    final id = _currentHitId;
    if (id != null) _scrollToMessage(id);
  }

  void _scrollToMessage(int messageId) {
    final index = _messages.indexWhere((m) => m.messageId == messageId);
    if (index == -1) return;
    // Already built (on/near screen)? Snap straight to it.
    final ctx = _bubbleKeys[messageId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // Otherwise scroll near it (items are lazily built), then snap.
    if (_scrollController.hasClients) {
      final target =
          (_scrollController.position.maxScrollExtent) *
          (index / _messages.length);
      _scrollController
          .animateTo(
            target.clamp(0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
          )
          .then((_) {
            final c = _bubbleKeys[messageId]?.currentContext;
            if (c != null && c.mounted) {
              Scrollable.ensureVisible(
                c,
                alignment: 0.35,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            }
          });
    }
  }
}

/// A single message bubble with swipe-to-reply and long-press actions.
class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool mine;
  final String? senderName;
  final String? replyFromName;

  /// 0 = sent ✓, 1 = read by some ✓✓ (grey), 2 = read by all ✓✓ (orange).
  final int readState;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback? onReplyTap;
  final void Function(String emoji) onReactTap;
  final void Function(String emoji, List<String> names) onReactionLongPress;

  /// Search term to highlight inside the message text, if searching.
  final String? highlight;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.senderName,
    this.replyFromName,
    required this.readState,
    required this.onLongPress,
    required this.onSwipeReply,
    this.onReplyTap,
    required this.onReactTap,
    required this.onReactionLongPress,
    this.highlight,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  double _dragOffset = 0;
  static const _swipeThreshold = 60.0;

  // Tap handlers for links in this bubble; recreated each build, disposed.
  final List<TapGestureRecognizer> _linkTaps = [];

  void _clearLinkTaps() {
    for (final t in _linkTaps) {
      t.dispose();
    }
    _linkTaps.clear();
  }

  @override
  void dispose() {
    _clearLinkTaps();
    super.dispose();
  }

  Future<void> _openLink(Uri uri) async {
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open ${uri.toString()}")),
      );
    }
  }

  /// Message text with tappable links (web, email, phone) and, while
  /// searching, highlighted matches.
  List<InlineSpan> _messageSpans(String text) {
    _clearLinkTaps();
    final spans = <InlineSpan>[];
    if (isForwarded(text)) {
      spans.add(
        TextSpan(
          text: '↪ Forwarded\n',
          style: TextStyle(
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            color: widget.mine
                ? Colors.white70
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
      text = stripForwarded(text);
    }
    for (final seg in linkify(text)) {
      if (!seg.isLink) {
        spans.addAll(_highlighted(seg.text, widget.highlight, widget.mine));
        continue;
      }
      final tap = TapGestureRecognizer()..onTap = () => _openLink(seg.uri!);
      _linkTaps.add(tap);
      spans.add(
        TextSpan(
          text: seg.text,
          recognizer: tap,
          style: TextStyle(
            color: widget.mine ? Colors.white : AppColors.primaryDark,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: widget.mine
                ? Colors.white70
                : AppColors.primaryDark,
          ),
        ),
      );
    }
    return spans;
  }

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
                              colors: [_accent, AppColors.primaryDark],
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
                                ..._messageSpans(msg.message ?? ''),
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
                        Semantics(
                          label: msg.messageId < 0
                              ? 'Sending'
                              : const [
                                  'Sent',
                                  'Read by some',
                                  'Read',
                                ][widget.readState],
                          child: Icon(
                            msg.messageId < 0
                                ? Icons.schedule
                                : (widget.readState > 0
                                      ? Icons.done_all
                                      : Icons.done),
                            size: 13,
                            color: widget.readState == 2 && msg.messageId > 0
                                ? _accent
                                : colors.onSurfaceVariant,
                          ),
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                            ? AppColors.success
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
                      ? AppColors.success
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
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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
                        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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
                        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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
                borderRadius: BorderRadius.circular(AppRadius.md),
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
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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

/// Splits [text] into spans with every case-insensitive occurrence of
/// [query] highlighted in brand orange.
List<InlineSpan> _highlighted(String text, String? query, bool mine) {
  if (query == null || query.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final q = query.toLowerCase();
  final spans = <InlineSpan>[];
  var start = 0;
  while (true) {
    final i = lower.indexOf(q, start);
    if (i < 0) break;
    if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
    spans.add(
      TextSpan(
        text: text.substring(i, i + q.length),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          backgroundColor: mine ? Colors.white : AppColors.primaryBorder,
        ),
      ),
    );
    start = i + q.length;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return spans;
}
