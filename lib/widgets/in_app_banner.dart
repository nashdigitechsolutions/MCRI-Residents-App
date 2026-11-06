import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/app_navigator.dart';
import '../services/notification_router.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// WhatsApp-style drop-down notification shown while the app is open.
///
/// Slides in from the top, auto-dismisses after a few seconds, can be
/// swiped up to dismiss, and opens the right screen when tapped. A newer
/// banner replaces the current one instead of stacking.
class InAppBanner {
  InAppBanner._();

  static OverlayEntry? _entry;
  static final _key = GlobalKey<_BannerState>();

  static void show({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    IconData icon = Icons.notifications_rounded,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    AppHaptics.light();
    _remove();
    _entry = OverlayEntry(
      builder: (_) => _Banner(
        key: _key,
        title: title,
        body: body,
        icon: icon,
        onTap: NotificationRouter.canOpen(data)
            ? () => NotificationRouter.open(data)
            : null,
        onDismissed: _remove,
      ),
    );
    overlay.insert(_entry!);
  }

  static void _remove() {
    _entry?.remove();
    _entry = null;
  }
}

class _Banner extends StatefulWidget {
  final String title;
  final String body;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback onDismissed;

  const _Banner({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();
  Timer? _timer;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 4500), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: top + 8,
      left: 10,
      right: 10,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _c,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          ),
        ),
        child: FadeTransition(
          opacity: _c,
          child: GestureDetector(
            onVerticalDragUpdate: (d) =>
                setState(() => _drag = (_drag + d.delta.dy).clamp(-120, 0)),
            onVerticalDragEnd: (d) {
              if (_drag < -24 || (d.primaryVelocity ?? 0) < -200) {
                _dismiss();
              } else {
                setState(() => _drag = 0);
              }
            },
            onTap: () {
              _dismiss();
              widget.onTap?.call();
            },
            child: Transform.translate(
              offset: Offset(0, _drag),
              child: Material(
                color: dark ? AppColors.darkSurfaceHigh : Colors.white,
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: const DecorationImage(
                            image: AssetImage(
                              'assets/branding/splash_badge.png',
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  widget.icon,
                                  size: 13,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'MCRI Residents · now',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (widget.body.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
