import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

class UnreadProvider extends ChangeNotifier {
  int _unreadNotifications = 0;
  int _unreadConversations = 0;
  final Map<int, DateTime> _optimisticReads = {};
  List<Map<String, dynamic>> _conversationsCache = [];
  int? _activeConversationId;

  bool _chatBadgeEnabled = true;

  int get unreadNotifications => _unreadNotifications;
  int get unreadConversations => _chatBadgeEnabled ? _unreadConversations : 0;

  void setChatBadgeEnabled(bool enabled) {
    if (_chatBadgeEnabled == enabled) return;
    _chatBadgeEnabled = enabled;
    notifyListeners();
  }

  /// The conversation screen currently on display (null when none). Messages
  /// arriving for it are treated as already read, like WhatsApp.
  void setActiveConversation(int? conversationId) {
    _activeConversationId = conversationId;
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
      _unreadConversations = _computeUnread(_conversationsCache);

      notifyListeners();
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
    notifyListeners();
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
      _optimisticReads[convId] = DateTime.now();
      ApiService.post(
        '/conversations/$convId/read',
        {},
      ).catchError((_) => null);
    }

    _unreadConversations = _computeUnread(_conversationsCache);
    notifyListeners();
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

  void markConversationRead(int conversationId) {
    _optimisticReads[conversationId] = DateTime.now();
    _unreadConversations = _computeUnread(_conversationsCache);
    notifyListeners();
  }

  void markNotificationsRead() {
    _unreadNotifications = 0;
    notifyListeners();
  }

  void reset() {
    _unreadNotifications = 0;
    _unreadConversations = 0;
    _optimisticReads.clear();
    _conversationsCache = [];
    _activeConversationId = null;
    notifyListeners();
  }
}
