import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/logo_geometry.dart';

/// The MCRI loading animation, used everywhere instead of a generic spinner.
///
/// A faint outline of the logo (house + M) with an orange "pen" racing
/// around it, the same drawing motion as the launch animation, as a loop.
/// It scales from an 16px button spinner to a full-screen loader.
///
/// Accepts the same arguments as [CircularProgressIndicator] (`color`,
/// `strokeWidth`, `value`, `backgroundColor`), so it's a drop-in
/// replacement. A non-null [value] shows a determinate ring instead, since
/// that means real progress rather than "busy".
class AppLoader extends StatefulWidget {
  final double? size;
  final Color? color;
  final double? strokeWidth;
  final double? value;
  final Color? backgroundColor;
  final String? semanticsLabel;

  const AppLoader({
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.value,
    this.backgroundColor,
    this.semanticsLabel,
  });

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value != null) {
      return CircularProgressIndicator(
        value: widget.value,
        color: widget.color ?? AppColors.primary,
        backgroundColor: widget.backgroundColor,
        strokeWidth: widget.strokeWidth ?? 4,
      );
    }
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.color ?? AppColors.primary;
    // A white/light requested colour means "on a dark/filled surface".
    final onFilled = accent.computeLuminance() > 0.6;
    final track =
        widget.backgroundColor ??
        (onFilled
            ? accent.withValues(alpha: 0.28)
            : (dark ? Colors.white : AppColors.ink).withValues(alpha: 0.12));

    Widget painted(double side) => RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.square(side),
          painter: _LoaderPainter(
            t: reduceMotion ? 0.35 : _c.value,
            color: accent,
            track: track,
          ),
        ),
      ),
    );

    return Semantics(
      label: widget.semanticsLabel ?? 'Loading',
      child: widget.size != null
          ? SizedBox.square(
              dimension: widget.size,
              child: painted(widget.size!),
            )
          : LayoutBuilder(
              builder: (context, c) {
                // Fill a parent SizedBox like CircularProgressIndicator does,
                // otherwise default to 40.
                final bounded = c.hasBoundedWidth && c.hasBoundedHeight;
                final side = bounded ? math.min(c.maxWidth, c.maxHeight) : 40.0;
                return Center(
                  child: SizedBox.square(
                    dimension: side.isFinite && side > 0 && side < 400
                        ? side
                        : 40,
                    child: painted(
                      side.isFinite && side > 0 && side < 400 ? side : 40,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final double t;
  final Color color;
  final Color track;

  _LoaderPainter({required this.t, required this.color, required this.track});

  static Path _path(List<List<(double, double)>> lines) {
    final p = Path();
    for (final l in lines) {
      p.moveTo(l.first.$1, l.first.$2);
      for (final q in l.skip(1)) {
        p.lineTo(q.$1, q.$2);
      }
    }
    return p;
  }

  // One continuous route: house first, then the M.
  static final _metrics = [
    ..._path(LogoGeometry.house).computeMetrics(),
    ..._path(LogoGeometry.m).computeMetrics(),
  ];
  static final _total = _metrics.fold<double>(0, (s, m) => s + m.length);
  static final _trackPath = _path([...LogoGeometry.house, ...LogoGeometry.m]);

  /// Extracts [from, to] (in route distance) across contour boundaries.
  static Path _segment(double from, double to) {
    final out = Path();
    var offset = 0.0;
    for (final m in _metrics) {
      final start = from - offset, end = to - offset;
      if (end > 0 && start < m.length) {
        out.addPath(
          m.extractPath(math.max(0, start), math.min(m.length, end)),
          Offset.zero,
        );
      }
      offset += m.length;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Mark spans roughly x 212..812, y 214..720 of the 1024 design space.
    const minX = 190.0, minY = 190.0, span = 644.0;
    final s = size.width / span;
    canvas
      ..save()
      ..scale(s)
      ..translate(-minX, -minY + 12);

    // Thicker relative strokes at small sizes so it stays legible.
    final boost = (40 / size.width).clamp(1.0, 2.2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      _trackPath,
      base
        ..color = track
        ..strokeWidth = 46 * boost,
    );

    // The pen: a comet whose length breathes as it travels.
    final head = Curves.easeInOutSine.transform(t) * _total * 1.0;
    final len = _total * (0.16 + 0.10 * math.sin(t * math.pi));
    final tail = head - len;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 58 * boost
      ..color = color;
    canvas.drawPath(_segment(tail, head), paint);
    // Wrap-around so the loop is seamless.
    if (tail < 0) canvas.drawPath(_segment(_total + tail, _total), paint);

    // Glowing nib at the head.
    final tip = _tipAt(head);
    if (tip != null) {
      canvas.drawCircle(
        tip,
        44 * boost,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
      );
    }
    canvas.restore();
  }

  Offset? _tipAt(double d) {
    var offset = 0.0;
    for (final m in _metrics) {
      if (d <= offset + m.length) {
        return m.getTangentForOffset((d - offset).clamp(0, m.length))?.position;
      }
      offset += m.length;
    }
    return null;
  }

  @override
  bool shouldRepaint(_LoaderPainter old) =>
      old.t != t || old.color != color || old.track != track;
}

/// Full-area loading state: the loader plus an optional caption.
class AppLoadingView extends StatelessWidget {
  final String? message;
  final double size;
  const AppLoadingView({super.key, this.message, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLoader(size: size),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
