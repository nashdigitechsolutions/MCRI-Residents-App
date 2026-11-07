import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../services/api_service.dart';

class UnreadProvider extends ChangeNotifier {
  int _unreadNotifications = 0;
  int _unreadConversations = 0;
  final Map<int, DateTime> _optimisticReads = {};
  List<Map<String, dynamic>> _conversationsCache = [];
  int? _activeConversationId;

  bool _chatBadgeEnabled = true;

  // Fires a conversation id whenever it becomes read (opened here, read on
  // another device, or a message arrives while it's open) so lists can
  // update their own unread dots without refetching.
  final _readEvents = StreamController<int>.broadcast();
  Stream<int> get conversationReads => _readEvents.stream;

  int get unreadNotifications => _unreadNotifications;
  int get unreadConversations => _chatBadgeEnabled ? _unreadConversations : 0;
  int? get activeConversationId => _activeConversationId;

  void setChatBadgeEnabled(bool enabled) {
    if (_chatBadgeEnabled == enabled) return;
    _chatBadgeEnabled = enabled;
    _safeNotify();
  }

  /// The conversation screen currently on display (null when none). Messages
  /// arriving for it are treated as already read, like WhatsApp.
  void setActiveConversation(int? conversationId) {
    _activeConversationId = conversationId;
  }

  /// A chat screen opened (from the list, a notification, anywhere): it's
  /// active, read locally right away, and the server is told.
  void openConversation(int conversationId) {
    _activeConversationId = conversationId;
    markConversationRead(conversationId, syncServer: true);
  }

  /// A chat screen closed: one last read sync (covers messages that landed
  /// while it was open), then it's no longer active.
  void closeConversation(int conversationId) {
    if (_activeConversationId == conversationId) _activeConversationId = null;
    // Deferred: this runs from a widget's dispose(), where notifying
    // listeners synchronously would rebuild a locked tree.
    Future.microtask(
      () => markConversationRead(conversationId, syncServer: true),
    );
  }

  /// "Read at" that is never earlier than the conversation's last activity,
  /// so a phone clock running behind the server can't leave it unread.
  DateTime _readStamp(int convId) {
    final now = DateTime.now();
    final c = _conversationsCache.where(
      (c) => _asInt(c['conversation_id']) == convId,
    );
    if (c.isEmpty) return now;
    final last = DateTime.tryParse(
      '${c.first['last_activity_at'] ?? c.first['last_message_at'] ?? ''}',
    );
    if (last == null || !last.isAfter(now)) return now;
    return last.add(const Duration(milliseconds: 1));
  }

  /// Socket 'read' event. When it's ME reading on another device (website,
  /// second phone), this device's badge clears too.
  void onReadEvent(dynamic payload, int? myUserId) {
    final d = payload is Map ? (payload['read'] ?? payload) : null;
    if (d is! Map || myUserId == null) return;
    if (_asInt(d['user_id']) != myUserId) return;
    final convId = _asInt(d['conversation_id']);
    if (convId != null) markConversationRead(convId);
  }

  /// Full sync from the server. Used on login, socket (re)connect and app
  /// resume, to catch anything missed while offline. Live events below
  /// update the counts locally without hitting the network.
  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        ApiService.get('/notifications'),
        ApiService.get('/conversations'),
      ]);

      final notifs = results[0] as List;
      _unreadNotifications = notifs
          .where((n) => (n as Map)['is_read'] != true)
          .length;

      _conversationsCache = (results[1] as List)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
      // A chat opened before this sync landed (e.g. straight from a push on
      // cold start) is read: re-stamp it against the server's timestamps.
      final active = _activeConversationId;
      if (active != null) _optimisticReads[active] = _readStamp(active);
      _unreadConversations = _computeUnread(_conversationsCache);

      _safeNotify();
    } catch (e) {
      // silent — badges stay at their last known value
    }
  }

  // ---- Live socket events ------------------------------------------------

  /// payload: { type: 'message', message: { conversation_id, created_at, ... } }
  /// The backend only pushes this to OTHER members, so it's never my own message.
  void onMessageEvent(dynamic payload) {
    final msg = payload is Map ? payload['message'] : null;
    if (msg is! Map) return;
    final convId = _asInt(msg['conversation_id']);
    if (convId == null) return;
    _applyActivity(convId, DateTime.tryParse('${msg['created_at']}'));
  }

  /// payload: { type: 'reaction', reaction: { conversation_id, action, ... } }
  void onReactionEvent(dynamic payload) {
    final r = payload is Map ? payload['reaction'] : null;
    if (r is! Map || r['action'] == 'remove') return;
    final convId = _asInt(r['conversation_id']);
    if (convId == null) return;
    _applyActivity(convId, DateTime.now());
  }

  void onNotificationEvent() {
    _unreadNotifications++;
    _safeNotify();
  }

  void _applyActivity(int convId, DateTime? at) {
    final idx = _conversationsCache.indexWhere(
      (c) => _asInt(c['conversation_id']) == convId,
    );
    if (idx == -1) {
      // A conversation we don't know about yet (someone just started a chat
      // with me) — one full sync picks it up.
      refresh();
      return;
    }

    final when = at ?? DateTime.now();
    _conversationsCache[idx]['last_activity_at'] = when.toIso8601String();
    _conversationsCache[idx]['last_activity_by_me'] = false;

    if (_activeConversationId == convId) {
      // I'm looking at this chat right now: count it as read, and tell the
      // server so a later refresh() doesn't resurrect it as unread.
      _optimisticReads[convId] = _readStamp(convId);
      ApiService.post(
        '/conversations/$convId/read',
        {},
      ).catchError((_) => null);
      _readEvents.add(convId);
    }

    _unreadConversations = _computeUnread(_conversationsCache);
    _safeNotify();
  }

  // ------------------------------------------------------------------------

  int? _asInt(dynamic v) => v is int ? v : int.tryParse('$v');

  int _computeUnread(List<Map<String, dynamic>> conversations) {
    var count = 0;
    for (final c in conversations) {
      if (c['last_activity_by_me'] == true) continue;
      final lastActivityAtStr = c['last_activity_at'] ?? c['last_message_at'];
      if (lastActivityAtStr == null) continue;
      final lastActivityAt = DateTime.tryParse('$lastActivityAtStr');
      if (lastActivityAt == null) continue;

      final convId = _asInt(c['conversation_id']);
      if (convId == null) continue;
      final override = _optimisticReads[convId];
      final serverReadAtStr = c['my_last_read_at'] as String?;
      final serverReadAt = serverReadAtStr == null
          ? null
          : DateTime.tryParse(serverReadAtStr);

      final effectiveReadAt =
          (override != null &&
              (serverReadAt == null || override.isAfter(serverReadAt)))
          ? override
          : serverReadAt;

      if (effectiveReadAt == null || lastActivityAt.isAfter(effectiveReadAt)) {
        count++;
      }
    }
    return count;
  }

  void markConversationRead(int conversationId, {bool syncServer = false}) {
    _optimisticReads[conversationId] = _readStamp(conversationId);
    _unreadConversations = _computeUnread(_conversationsCache);
    _readEvents.add(conversationId);
    _safeNotify();
    if (syncServer) {
      ApiService.post(
        '/conversations/$conversationId/read',
        {},
      ).catchError((_) => null);
    }
  }

  void markNotificationsRead() {
    _unreadNotifications = 0;
    _safeNotify();
  }

  /// notifyListeners() that is safe to call from initState/build (e.g. a
  /// chat screen marking itself read as it opens): if a frame is being
  /// built right now, listeners are told just after it instead of during
  /// it, which Flutter forbids ("setState() called during build").
  bool _notifyScheduled = false;
  void _safeNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _readEvents.close();
    super.dispose();
  }

  void reset() {
    _unreadNotifications = 0;
    _unreadConversations = 0;
    _optimisticReads.clear();
    _conversationsCache = [];
    _activeConversationId = null;
    _safeNotify();
  }
}
