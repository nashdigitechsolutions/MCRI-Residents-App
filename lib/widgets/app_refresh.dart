import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_loader.dart';

/// Pull-to-refresh that shows the app's own loader instead of Material's
/// spinner. Drop-in for [RefreshIndicator] (same `onRefresh` + `child`).
///
/// Works with both scroll physics: Android's clamping (reports overscroll)
/// and iOS bouncing (reports negative pixels). The child should be
/// scrollable even when short (AlwaysScrollableScrollPhysics), exactly as
/// with RefreshIndicator.
class AppRefreshIndicator extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

class _AppRefreshIndicatorState extends State<AppRefreshIndicator>
    with SingleTickerProviderStateMixin {
  static const _trigger = 80.0; // pull distance that triggers a refresh
  static const _maxPull = 130.0;
  static const _restOffset = 18.0; // where the loader sits while refreshing

  double _pull = 0;
  bool _dragging = false;
  bool _refreshing = false;
  bool _hapticDone = false;

  late final AnimationController _settle =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
      )..addListener(
        () => setState(
          () => _pull =
              _settleFrom * (1 - Curves.easeOut.transform(_settle.value)),
        ),
      );
  double _settleFrom = 0;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _setPull(double v) {
    final next = v.clamp(0.0, _maxPull);
    if (next >= _trigger && !_hapticDone) {
      _hapticDone = true;
      HapticFeedback.selectionClick();
    } else if (next < _trigger) {
      _hapticDone = false;
    }
    setState(() => _pull = next);
  }

  void _release() {
    _dragging = false;
    if (_refreshing) return;
    if (_pull >= _trigger) {
      _start();
    } else if (_pull > 0) {
      _settleFrom = _pull;
      _settle.forward(from: 0);
    }
  }

  Future<void> _start() async {
    setState(() {
      _refreshing = true;
      _pull = _trigger;
    });
    try {
      await widget.onRefresh();
    } catch (_) {
      // The screen shows its own error; the indicator just goes away.
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
        _settleFrom = _pull;
        _settle.forward(from: 0);
      }
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (_refreshing) return false;

    if (n is ScrollStartNotification && n.dragDetails != null) {
      _settle.stop();
      _dragging = n.metrics.extentBefore == 0;
    } else if (n is OverscrollNotification &&
        _dragging &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      // Clamping physics: list is at the top and the finger keeps pulling.
      _setPull(_pull - n.overscroll * 0.6);
    } else if (n is ScrollUpdateNotification && _dragging) {
      if (n.metrics.pixels < 0 && n.dragDetails != null) {
        // Bouncing physics.
        _setPull(-n.metrics.pixels * 0.9);
      } else if ((n.scrollDelta ?? 0) > 0 && _pull > 0) {
        // Pushing back up cancels the pull.
        _setPull(_pull - n.scrollDelta!);
      }
      if (n.dragDetails == null && _pull > 0) _release(); // finger lifted
    } else if (n is ScrollEndNotification ||
        (n is UserScrollNotification && n.direction.name == 'idle')) {
      if (_dragging || _pull > 0) _release();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = (_pull / _trigger).clamp(0.0, 1.0);
    final visible = _pull > 1 || _refreshing;
    final top = _refreshing
        ? _restOffset
        : (_pull * 0.6 - 20).clamp(-40.0, _maxPull);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (visible)
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Semantics(
                    label: _refreshing ? 'Refreshing' : 'Pull to refresh',
                    child: Opacity(
                      opacity: _refreshing ? 1 : progress,
                      child: Transform.scale(
                        scale: _refreshing ? 1 : 0.6 + 0.4 * progress,
                        child: Container(
                          width: 44,
                          height: 44,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.outlineVariant),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: _refreshing
                              ? const AppLoader(size: 28, strokeWidth: 3)
                              // While pulling the ring fills up to show how
                              // far is left, then spins once released.
                              : Transform.rotate(
                                  angle: progress * math.pi * 1.5,
                                  child: AppLoader(
                                    size: 28,
                                    strokeWidth: 3,
                                    value: math.max(0.02, progress),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
