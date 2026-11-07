import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Jigsaw slide puzzle: a generated scene with a piece-shaped hole cut out at
/// a random spot. Dragging the slider moves the loose piece along its row;
/// release it over the hole.
///
/// Bot resistance (client side): a new random scene and hole position on
/// every attempt, tight tolerance, minimum drag time, enough motion samples,
/// and the drag speed must vary (a script moving at constant speed fails).
/// Three misses in a row lock the puzzle for a short cool-down.
const double _sceneHeight = 150;
const double _piece = 46;
const double _tolerancePx = 5;
const int _minDragMs = 300;
const int _minSamplePoints = 6;
const int _maxFailsBeforeCooldown = 3;
const Duration _cooldown = Duration(seconds: 15);
const Color _good = Color(0xFF047857);

class SlidePuzzleCaptcha extends StatefulWidget {
  final void Function(String token) onVerified;
  final VoidCallback? onReset;

  const SlidePuzzleCaptcha({super.key, required this.onVerified, this.onReset});

  @override
  State<SlidePuzzleCaptcha> createState() => _SlidePuzzleCaptchaState();
}

enum _Status { idle, dragging, success, fail, locked }

class _SlidePuzzleCaptchaState extends State<SlidePuzzleCaptcha>
    with SingleTickerProviderStateMixin {
  final _rng = Random.secure();
  late int _seed;
  late double _targetFrac; // hole x as a fraction of the usable width
  late double _holeTopFrac;
  double _x = 0; // piece / thumb offset in px
  _Status _status = _Status.idle;
  DateTime? _dragStart;
  final List<double> _speeds = [];
  DateTime? _lastSample;
  int _fails = 0;
  DateTime? _lockedUntil;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    _newPuzzle();
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _newPuzzle() {
    _seed = _rng.nextInt(1 << 31);
    _targetFrac = 0.4 + _rng.nextDouble() * 0.5;
    _holeTopFrac = 0.12 + _rng.nextDouble() * 0.6;
    _x = 0;
    _speeds.clear();
  }

  bool get _isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  void _reset() {
    if (!mounted) return;
    setState(() {
      _newPuzzle();
      _status = _isLocked ? _Status.locked : _Status.idle;
    });
    widget.onReset?.call();
  }

  void _onStart(DragStartDetails _) {
    if (_status == _Status.success || _isLocked) return;
    _dragStart = DateTime.now();
    _lastSample = _dragStart;
    _speeds.clear();
    setState(() => _status = _Status.dragging);
  }

  void _onUpdate(DragUpdateDetails d, double maxX) {
    if (_status != _Status.dragging) return;
    final now = DateTime.now();
    final dt = now.difference(_lastSample!).inMicroseconds / 1000;
    if (dt > 0) _speeds.add(d.delta.dx.abs() / dt);
    _lastSample = now;
    setState(() => _x = (_x + d.delta.dx).clamp(0.0, maxX));
  }

  void _onEnd(double targetX) {
    if (_status != _Status.dragging || _dragStart == null) return;
    final ms = DateTime.now().difference(_dragStart!).inMilliseconds;
    final onTarget = (_x - targetX).abs() <= _tolerancePx;
    final human =
        ms >= _minDragMs &&
        _speeds.length >= _minSamplePoints &&
        _speedVariation() > 0.08;

    if (onTarget && human) {
      _fails = 0;
      setState(() => _status = _Status.success);
      widget.onVerified(_token(ms, (_x - targetX).abs()));
      return;
    }
    _fails++;
    _shake.forward(from: 0);
    if (_fails >= _maxFailsBeforeCooldown) {
      _fails = 0;
      _lockedUntil = DateTime.now().add(_cooldown);
      setState(() => _status = _Status.locked);
      Future.delayed(_cooldown, _reset);
    } else {
      setState(() => _status = _Status.fail);
      Future.delayed(const Duration(milliseconds: 800), _reset);
    }
  }

  /// Coefficient of variation of drag speed: people speed up and slow down
  /// near the target; simple scripts move at a constant rate.
  double _speedVariation() {
    if (_speeds.length < 3) return 0;
    final mean = _speeds.reduce((a, b) => a + b) / _speeds.length;
    if (mean == 0) return 0;
    final variance =
        _speeds.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) /
        _speeds.length;
    return sqrt(variance) / mean;
  }

  String _token(int ms, double error) => base64Encode(
    utf8.encode(
      jsonEncode({
        'v': 2,
        't': DateTime.now().millisecondsSinceEpoch,
        'd': ms,
        's': _speeds.length,
        'e': error.toStringAsFixed(1),
        'cv': _speedVariation().toStringAsFixed(2),
      }),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth.isFinite ? c.maxWidth : 320.0;
        final maxX = width - _piece;
        final targetX = maxX * _targetFrac;
        final holeTop = (_sceneHeight - _piece) * _holeTopFrac;
        final done = _status == _Status.success;
        final pieceX = done ? targetX : _x;

        final (msg, msgColor) = switch (_status) {
          _Status.success => ('Verified — the piece fits!', _good),
          _Status.fail => (
            'Not quite — here is a new puzzle',
            AppColors.dangerDark,
          ),
          _Status.locked => (
            'Too many tries — wait a few seconds',
            AppColors.dangerDark,
          ),
          _Status.dragging => (
            'Release when the piece fills the gap',
            colors.onSurfaceVariant,
          ),
          _Status.idle => (
            'Drag the slider to fit the piece into the gap',
            colors.onSurfaceVariant,
          ),
        };

        return AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              sin(_shake.value * pi * 6) * 6 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  height: _sceneHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _ScenePainter(_seed)),
                      ),
                      if (!done)
                        Positioned(
                          left: targetX,
                          top: holeTop,
                          child: CustomPaint(
                            size: const Size(_piece, _piece),
                            painter: _HolePainter(),
                          ),
                        ),
                      AnimatedPositioned(
                        duration: _status == _Status.dragging
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        left: pieceX,
                        top: holeTop,
                        child: CustomPaint(
                          size: const Size(_piece, _piece),
                          painter: _PiecePainter(
                            _seed,
                            Size(width, _sceneHeight),
                            Offset(targetX, holeTop),
                            done,
                          ),
                        ),
                      ),
                      if (_status == _Status.locked)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.lock_clock_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: done
                      ? _good.withValues(alpha: 0.10)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: switch (_status) {
                      _Status.success => _good,
                      _Status.fail || _Status.locked => AppColors.dangerDark,
                      _ => colors.outlineVariant,
                    },
                  ),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      width: pieceX + _piece,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(
                          alpha: done ? 0 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    if (_status == _Status.idle)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Slide',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      left: pieceX,
                      child: Semantics(
                        label: 'Puzzle slider',
                        slider: true,
                        child: GestureDetector(
                          onHorizontalDragStart: _onStart,
                          onHorizontalDragUpdate: (d) => _onUpdate(d, maxX),
                          onHorizontalDragEnd: (_) => _onEnd(targetX),
                          child: Container(
                            width: _piece,
                            height: 46,
                            decoration: BoxDecoration(
                              color: switch (_status) {
                                _Status.success => _good,
                                _Status.fail ||
                                _Status.locked => AppColors.dangerDark,
                                _ => AppColors.primary,
                              },
                              borderRadius: BorderRadius.circular(
                                AppRadius.md - 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              done
                                  ? Icons.check_rounded
                                  : Icons.drag_handle_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    done ? Icons.verified_rounded : Icons.extension_rounded,
                    size: 15,
                    color: msgColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      msg,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: msgColor,
                      ),
                    ),
                  ),
                  if (!done && _status != _Status.locked)
                    IconButton(
                      tooltip: 'New puzzle',
                      onPressed: _reset,
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Puzzle-piece outline: a square body with a knob on the top and the right.
Path _piecePath(double s) {
  final k = s * 0.18; // knob radius
  final b = s - k; // body size
  return Path()
    ..moveTo(0, k)
    ..lineTo(b / 2 - k * 0.7, k)
    ..arcToPoint(
      Offset(b / 2 + k * 0.7, k),
      radius: Radius.circular(k),
      largeArc: true,
    )
    ..lineTo(b, k)
    ..lineTo(b, k + b / 2 - k * 0.7)
    ..arcToPoint(
      Offset(b, k + b / 2 + k * 0.7),
      radius: Radius.circular(k),
      largeArc: true,
    )
    ..lineTo(b, s)
    ..lineTo(0, s)
    ..close();
}

/// Procedural scene: brand gradient plus random soft shapes, so every puzzle
/// looks different and the hole can't be found with a fixed template.
class _ScenePainter extends CustomPainter {
  final int seed;
  _ScenePainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(seed);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [AppColors.ink, const Color(0xFF3A1D0C), AppColors.primaryDeep],
          [0, 0.55, 1],
        ),
    );
    const palette = [
      AppColors.primary,
      AppColors.primaryBorder,
      Colors.white,
      Color(0xFFFFD2B0),
    ];
    for (var i = 0; i < 16; i++) {
      final paint = Paint()
        ..color = palette[r.nextInt(palette.length)].withValues(
          alpha: 0.12 + r.nextDouble() * 0.3,
        );
      final c = Offset(
        r.nextDouble() * size.width,
        r.nextDouble() * size.height,
      );
      final rad = 8 + r.nextDouble() * 34;
      switch (r.nextInt(3)) {
        case 0:
          canvas.drawCircle(c, rad, paint);
        case 1:
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(r.nextDouble() * pi);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: rad * 2, height: rad),
              const Radius.circular(6),
            ),
            paint,
          );
          canvas.restore();
        default:
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - rad)
              ..lineTo(c.dx + rad, c.dy + rad)
              ..lineTo(c.dx - rad, c.dy + rad)
              ..close(),
            paint,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.seed != seed;
}

class _HolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _piecePath(size.width);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The loose piece: the scene clipped to the piece shape, cut from the hole's
/// position so it matches exactly when aligned.
class _PiecePainter extends CustomPainter {
  final int seed;
  final Size sceneSize;
  final Offset src;
  final bool glow;
  _PiecePainter(this.seed, this.sceneSize, this.src, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final path = _piecePath(size.width);
    canvas.drawShadow(path, Colors.black, 4, false);
    canvas.save();
    canvas.clipPath(path);
    canvas.translate(-src.dx, -src.dy);
    _ScenePainter(seed).paint(canvas, sceneSize);
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = glow ? 2.5 : 1.5
        ..color = glow ? const Color(0xFF34D399) : Colors.white,
    );
  }

  @override
  bool shouldRepaint(_PiecePainter o) =>
      o.seed != seed ||
      o.src != src ||
      o.glow != glow ||
      o.sceneSize != sceneSize;
}
