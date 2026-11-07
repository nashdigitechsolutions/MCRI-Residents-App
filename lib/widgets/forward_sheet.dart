import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/initials.dart';
import 'app_loader.dart';

/// Messages forwarded from another chat start with this marker, so every
/// client (app + website) can show a "Forwarded" label like WhatsApp.
const kForwardedPrefix = '↪ Forwarded\n';

bool isForwarded(String? text) => text?.startsWith(kForwardedPrefix) ?? false;
String stripForwarded(String text) =>
    isForwarded(text) ? text.substring(kForwardedPrefix.length) : text;

/// Pick up to [maxTargets] chats and forward [messages] to each.
/// Returns how many chats received them (0 if cancelled).
Future<int> showForwardSheet(
  BuildContext context, {
  required List<String> messages,
  int? excludeConversationId,
}) async {
  final sent = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ForwardSheet(messages: messages, excludeId: excludeConversationId),
  );
  return sent ?? 0;
}

class _ForwardSheet extends StatefulWidget {
  final List<String> messages;
  final int? excludeId;
  const _ForwardSheet({required this.messages, this.excludeId});

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  static const maxTargets = 5;
  List<Conversation>? _chats;
  String _query = '';
  final Set<int> _picked = {};
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/conversations');
      final list =
          (data as List)
              .map((j) => Conversation.fromJson(j as Map<String, dynamic>))
              .where((c) => c.conversationId != widget.excludeId)
              .toList()
            ..sort(
              (a, b) => (b.lastActivityAt ?? b.lastMessageAt ?? DateTime(0))
                  .compareTo(
                    a.lastActivityAt ?? a.lastMessageAt ?? DateTime(0),
                  ),
            );
      if (mounted) setState(() => _chats = list);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _chats = [];
          _error = e.message;
        });
      }
    }
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    var delivered = 0;
    try {
      for (final id in _picked) {
        for (final m in widget.messages) {
          final body = isForwarded(m) ? m : '$kForwardedPrefix$m';
          await ApiService.post('/conversations/$id/messages', {
            'message': body,
          });
        }
        delivered++;
      }
      if (mounted) Navigator.of(context).pop(delivered);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = delivered > 0
              ? 'Sent to $delivered chat(s), then: ${e.message}'
              : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final chats = (_chats ?? [])
        .where((c) => q.isEmpty || c.displayName.toLowerCase().contains(q))
        .toList();
    final count = widget.messages.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    'Forward ${count == 1 ? 'message' : '$count messages'}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Choose up to $maxTargets chats',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search chats',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _chats == null
                  ? const AppLoadingView()
                  : chats.isEmpty
                  ? Center(
                      child: Text(
                        _error ?? 'No chats to forward to yet',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: chats.length,
                      itemBuilder: (_, i) {
                        final c = chats[i];
                        final picked = _picked.contains(c.conversationId);
                        final full = _picked.length >= maxTargets && !picked;
                        return ListTile(
                          enabled: !full && !_sending,
                          onTap: () => setState(
                            () => picked
                                ? _picked.remove(c.conversationId)
                                : _picked.add(c.conversationId),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: picked
                                ? AppColors.primary
                                : colors.primaryContainer,
                            child: picked
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                  )
                                : Text(
                                    c.isGroup
                                        ? 'G'
                                        : initialsFor(c.displayName),
                                    style: TextStyle(
                                      color: colors.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          title: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            c.isGroup ? 'Group' : 'Direct message',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null && (_chats?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 12.5),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _picked.isEmpty || _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: AppLoader(color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _picked.isEmpty
                          ? 'Select a chat'
                          : 'Send to ${_picked.length}',
                    ),
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
