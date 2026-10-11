import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/notification.dart';
import '../providers/unread_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';

const _accent = Color(0xFF3355FF);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;
  bool _markingAll = false;
  late final void Function(dynamic) _onNotification;

  @override
  void initState() {
    super.initState();
    _load();

    // Live delivery: a broadcast notification arrives over the socket the
    // instant an admin sends one — prepend it immediately rather than
    // waiting for the next manual refresh.
    _onNotification = (payload) {
      final raw = payload['data']?['notification'] ?? payload['notification'];
      if (raw == null) return;
      final incoming = AppNotification.fromJson({
        // The broadcast payload is the bare `notifications` row shape
        // (title/message/notification_id/created_at) — no
        // user_notification_id or is_read yet, since that's a separate
        // per-user table row. We use notification_id as a stand-in key and
        // default is_read to false, matching a freshly-inserted recipient row.
        'user_notification_id': raw['notification_id'],
        'title': raw['title'],
        'message': raw['message'],
        'is_read': false,
        'created_at': raw['created_at'],
      });
      setState(() => _items = [incoming, ..._items]);
    };
    context.read<WebSocketProvider>().on('notification', _onNotification);
  }

  @override
  void dispose() {
    context.read<WebSocketProvider>().off('notification', _onNotification);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/notifications');
      final list = (data as List)
          .map((j) => AppNotification.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    setState(() {
      _items = _items
          .map(
            (it) => it.userNotificationId == n.userNotificationId
                ? it.copyWith(isRead: true)
                : it,
          )
          .toList();
    });
    if (mounted) context.read<UnreadProvider>().refresh();

    try {
      await ApiService.patch('/notifications/mark-read', {
        'user_notification_ids': [n.userNotificationId],
      });
    } catch (e) {
      // optimistic update stands even if the sync silently fails
    }
  }

  Future<void> _markAllRead() async {
    if (_items.every((n) => n.isRead)) return;
    setState(() {
      _markingAll = true;
      _items = _items.map((it) => it.copyWith(isRead: true)).toList();
    });
    if (mounted) context.read<UnreadProvider>().refresh();

    try {
      await ApiService.patch('/notifications/mark-read', {'all': true});
    } catch (e) {
      // optimistic update stands even if the sync silently fails
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasUnread = _items.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: _markingAll
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  : const Text(
                      'Mark all read',
                      style: TextStyle(fontSize: 12.5),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 30,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No notifications right now',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final n = _items[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: n.isRead
                          ? colors.surface
                          : _accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: n.isRead
                            ? colors.outlineVariant
                            : _accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _markRead(n),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!n.isRead) ...[
                                Container(
                                  margin: const EdgeInsets.only(top: 5),
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: _accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: n.isRead
                                            ? FontWeight.w600
                                            : FontWeight.w700,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      n.message,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      DateFormat.yMMMd().add_jm().format(
                                        n.createdAt,
                                      ),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: colors.onSurfaceVariant,
                                      ),
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
                },
              ),
            ),
    );
  }
}
