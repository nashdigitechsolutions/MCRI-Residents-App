import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/logo_geometry.dart';

/// "Building the home" — the launch animation.
///
/// Picks up from the native launch screen (same background, same centred
/// badge) and then:
///   1. the badge dissolves back into a blueprint,
///   2. the house outline is drafted, an orange pen-tip leading the line,
///   3. the M is laid in orange with its isometric depth trailing behind,
///   4. the badge ring sweeps round and a warm light comes on in the door,
///   5. the finished logo settles in with the wordmark.
///
/// [onFinished] fires once the sequence has played; the caller decides when
/// to leave (e.g. after the auth check is also done).
class AnimatedSplash extends StatefulWidget {
  final VoidCallback onFinished;
  const AnimatedSplash({super.key, required this.onFinished});

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _c =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2600),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onFinished();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect the OS "reduce motion" setting: jump straight to the logo.
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFinished());
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.ink : Colors.white;
    final size = MediaQuery.sizeOf(context);
    // Match the native splash badge (≈196dp), shrinking on tiny screens.
    final d = math.min(196.0, size.width * 0.55);

    return Scaffold(
      backgroundColor: bg,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(
            double a,
            double b, [
            Curve curve = Curves.easeInOutCubic,
          ]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

          final badgeOut = seg(
            0.00,
            0.12,
            Curves.easeOut,
          ); // native badge fades away
          final badgeIn = seg(
            0.80,
            0.96,
            Curves.easeOutCubic,
          ); // real logo returns
          final badgeOpacity = (1 - badgeOut) + badgeIn;
          final settle = 0.94 + 0.06 * Curves.easeOutBack.transform(badgeIn);
          final words = seg(0.84, 1.0, Curves.easeOutCubic);

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: d,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _BlueprintPainter(
                          house: seg(0.08, 0.42),
                          m: seg(0.34, 0.70),
                          ring: seg(0.58, 0.84),
                          glow:
                              seg(0.66, 0.86, Curves.easeOut) *
                              (1 - badgeIn * 0.6),
                          fade: 1 - badgeIn,
                          dark: dark,
                        ),
                      ),
                      Opacity(
                        opacity: badgeOpacity.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: t < 0.5 ? 1 - 0.04 * badgeOut : settle,
                          child: Image.asset(
                            'assets/branding/splash_badge.png',
                            filterQuality: FilterQuality.medium,
                            cacheWidth:
                                (d * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: words,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - words)),
                    child: Column(
                      children: [
                        Text(
                          'MCRI RESIDENTS',
                          style: TextStyle(
                            color: dark ? Colors.white : AppColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4 + 2 * (1 - words),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your residence, connected',
                          style: TextStyle(
                            color: dark ? Colors.white60 : AppColors.muted,
                            fontSize: 12.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  final double house, m, ring, glow, fade;
  final bool dark;

  _BlueprintPainter({
    required this.house,
    required this.m,
    required this.ring,
    required this.glow,
    required this.fade,
    required this.dark,
  });

  // The badge spans logo coords 120..904 (radius 392 around 512,512).
  static const _badgeMin = 120.0, _badgeSpan = 784.0;

  static Path _toPath(List<List<(double, double)>> lines) {
    final p = Path();
    for (final line in lines) {
      p.moveTo(line.first.$1, line.first.$2);
      for (final q in line.skip(1)) {
        p.lineTo(q.$1, q.$2);
      }
    }
    return p;
  }

  static final _housePath = _toPath(LogoGeometry.house);
  static final _mPath = _toPath(LogoGeometry.m);
  static final _houseMetrics = _housePath.computeMetrics().toList();
  static final _mMetrics = _mPath.computeMetrics().toList();
  static final _houseLen = _houseMetrics.fold<double>(
    0,
    (s, m) => s + m.length,
  );
  static final _mLen = _mMetrics.fold<double>(0, (s, m) => s + m.length);

  /// Draws the first [t] of all contours (in order) and returns the tip.
  static ui.Tangent? _drawPartial(
    Canvas canvas,
    List<ui.PathMetric> metrics,
    double total,
    double t,
    Paint paint,
  ) {
    var remaining = total * t;
    ui.Tangent? tip;
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final len = math.min(remaining, metric.length);
      canvas.drawPath(metric.extractPath(0, len), paint);
      tip = metric.getTangentForOffset(len);
      remaining -= metric.length;
    }
    return tip;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0) return;
    final s = size.width / _badgeSpan;
    canvas
      ..save()
      ..scale(s)
      ..translate(-_badgeMin, -_badgeMin);

    final ink = (dark ? Colors.white : AppColors.ink).withValues(
      alpha: 0.85 * fade,
    );
    final orange = AppColors.primary.withValues(alpha: fade);
    final deep = AppColors.primaryDark.withValues(alpha: 0.9 * fade);

    // 4a. Ring sweep.
    if (ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(512, 512), radius: 376),
        -math.pi / 2,
        2 * math.pi * ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..shader =
              SweepGradient(
                transform: const GradientRotation(-math.pi / 2),
                colors: [
                  AppColors.subtle.withValues(alpha: fade),
                  orange,
                  AppColors.subtle.withValues(alpha: fade),
                ],
              ).createShader(
                Rect.fromCircle(center: const Offset(512, 512), radius: 376),
              ),
      );
    }

    // 4b. Warm light in the doorway.
    if (glow > 0) {
      const door = Offset(513, 705);
      canvas.drawCircle(
        door,
        240 * glow,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.35 * glow * fade),
              AppColors.primary.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: door, radius: 240 * glow)),
      );
    }

    // 2. House outline, drafted.
    final housePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = LogoGeometry.houseStroke
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square
      ..color = ink;
    final houseTip = _drawPartial(
      canvas,
      _houseMetrics,
      _houseLen,
      house,
      housePaint,
    );

    // 3. The M: depth layer first (offset like the logo's extrusion), then face.
    if (m > 0) {
      final mPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = LogoGeometry.mStroke
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = StrokeCap.butt;
      canvas.save();
      canvas.translate(10, 14);
      _drawPartial(
        canvas,
        _mMetrics,
        _mLen,
        (m - 0.08).clamp(0.0, 1.0),
        mPaint..color = deep,
      );
      canvas.restore();
      final mTip = _drawPartial(
        canvas,
        _mMetrics,
        _mLen,
        m,
        mPaint..color = orange,
      );
      if (m < 1 && mTip != null) _penTip(canvas, mTip.position, fade);
    }
    if (house > 0 && house < 1 && houseTip != null) {
      _penTip(canvas, houseTip.position, fade);
    }

    canvas.restore();
  }

  void _penTip(Canvas canvas, Offset at, double fade) {
    canvas.drawCircle(
      at,
      34,
      Paint()..color = AppColors.primary.withValues(alpha: 0.22 * fade),
    );
    canvas.drawCircle(
      at,
      15,
      Paint()..color = AppColors.primary.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(_BlueprintPainter old) =>
      old.house != house ||
      old.m != m ||
      old.ring != ring ||
      old.glow != glow ||
      old.fade != fade ||
      old.dark != dark;
}
