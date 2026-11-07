import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small chart kit for the admin dashboard, following the dataviz rules:
/// thin marks (≤24px bars, 4px rounded data-end, square at the baseline),
/// one hue for a single series (brand orange), hairline recessive grid,
/// values in text colours (never the series colour), tap-to-inspect
/// tooltips, and a table view on every chart for accessibility.

/// Fixed status palette (validated reference instance): never reused for a
/// series, always shown with an icon + label.
abstract final class StatusColors {
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const critical = Color(0xFFD03B3B);
}

/// Card shell: title, optional subtitle, chart ⇄ table toggle.
class ChartCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget chart;
  final List<(String, String)> table; // (label, value) rows
  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.chart,
    required this.table,
  });

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _asTable = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _asTable ? 'Show chart' : 'Show as table',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _asTable
                      ? Icons.bar_chart_rounded
                      : Icons.table_rows_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _asTable = !_asTable),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _asTable
                  ? Column(
                      key: const ValueKey('table'),
                      children: [
                        for (final (l, v) in widget.table)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  v,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : KeyedSubtree(
                      key: const ValueKey('chart'),
                      child: widget.chart,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero number: label · value · optional delta vs a named period.
class StatFigure extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? delta; // e.g. "+3 vs last week"
  final bool deltaGood;
  final VoidCallback? onTap;
  const StatFigure({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.delta,
    this.deltaGood = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              if (delta != null)
                Text(
                  delta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: deltaGood
                        ? const Color(0xFF006300)
                        : AppColors.dangerDark,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-series column chart (one hue). Tap a column for its value.
class ColumnChart extends StatefulWidget {
  final List<(String, num)> data;
  final String unit;
  final double height;
  const ColumnChart({
    super.key,
    required this.data,
    this.unit = '',
    this.height = 150,
  });

  @override
  State<ColumnChart> createState() => _ColumnChartState();
}

class _ColumnChartState extends State<ColumnChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final maxV = widget.data.fold<num>(0, (m, e) => math.max(m, e.$2));
    final niceMax = maxV <= 0 ? 4 : _niceCeil(maxV);
    return LayoutBuilder(
      builder: (context, c) {
        const axisW = 26.0;
        final plotW = c.maxWidth - axisW;
        final slot = plotW / math.max(1, widget.data.length);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final x = d.localPosition.dx - axisW;
            if (x < 0) return;
            final i = (x / slot).floor().clamp(0, widget.data.length - 1);
            setState(() => _selected = _selected == i ? null : i);
          },
          // Explicit width: inside a start-aligned Column the paint area would
          // otherwise shrink to 0 wide and every column lands on the axis.
          child: SizedBox(
            width: c.maxWidth,
            height: widget.height + 22,
            child: CustomPaint(
              painter: _ColumnPainter(
                data: widget.data,
                maxV: niceMax.toDouble(),
                selected: _selected,
                bar: AppColors.primary,
                grid: dark ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9),
                baseline: dark
                    ? const Color(0xFF383835)
                    : const Color(0xFFC3C2B7),
                text: colors.onSurfaceVariant,
                strong: colors.onSurface,
                surface: colors.surface,
                unit: widget.unit,
                plotHeight: widget.height,
                axisW: axisW,
              ),
            ),
          ),
        );
      },
    );
  }
}

num _niceCeil(num v) {
  if (v <= 4) return 4;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor());
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (m * mag >= v) return m * mag;
  }
  return 10 * mag;
}

class _ColumnPainter extends CustomPainter {
  final List<(String, num)> data;
  final double maxV;
  final int? selected;
  final Color bar, grid, baseline, text, strong, surface;
  final String unit;
  final double plotHeight, axisW;

  _ColumnPainter({
    required this.data,
    required this.maxV,
    required this.selected,
    required this.bar,
    required this.grid,
    required this.baseline,
    required this.text,
    required this.strong,
    required this.surface,
    required this.unit,
    required this.plotHeight,
    required this.axisW,
  });

  void _text(
    Canvas c,
    String s,
    Offset at, {
    Color? color,
    double size = 10,
    bool bold = false,
    TextAlign align = TextAlign.center,
    double width = 40,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color ?? text,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(c, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final top = 14.0; // room for the selected value label
    final h = plotHeight - top;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Gridlines at 0, ½, max — hairline, solid, recessive.
    for (final f in [0.5, 1.0]) {
      final y = top + h * (1 - f);
      canvas.drawLine(Offset(axisW, y), Offset(size.width, y), gridPaint);
      _text(
        canvas,
        _fmt(maxV * f),
        Offset(0, y - 6),
        align: TextAlign.right,
        width: axisW - 4,
      );
    }
    canvas.drawLine(
      Offset(axisW, top + h),
      Offset(size.width, top + h),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    _text(
      canvas,
      '0',
      Offset(0, top + h - 6),
      align: TextAlign.right,
      width: axisW - 4,
    );

    final slot = (size.width - axisW) / math.max(1, data.length);
    final barW = math.min(24.0, slot - 6);
    for (var i = 0; i < data.length; i++) {
      final v = data[i].$2.toDouble();
      final x = axisW + slot * i + (slot - barW) / 2;
      final bh = maxV == 0 ? 0.0 : h * (v / maxV);
      final rect = Rect.fromLTWH(x, top + h - bh, barW, bh);
      final faded = selected != null && selected != i;
      if (bh > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = faded ? bar.withValues(alpha: 0.35) : bar,
        );
      }
      // x labels (thin out if crowded)
      if (data.length <= 8 || i % 2 == 0 || i == data.length - 1) {
        _text(
          canvas,
          data[i].$1,
          Offset(axisW + slot * i, top + h + 5),
          width: slot,
        );
      }
      // value: selected column, or the latest one by default (selective labels)
      if (i == (selected ?? data.length - 1) && (selected != null || v > 0)) {
        _text(
          canvas,
          '${_fmt(v)}$unit',
          Offset(axisW + slot * i, top + h - bh - 14),
          color: strong,
          bold: true,
          width: slot,
        );
      }
    }
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(_ColumnPainter o) =>
      o.data != data ||
      o.selected != selected ||
      o.maxV != maxV ||
      o.bar != bar ||
      o.surface != surface;
}

/// Horizontal bars, each against its own capacity (e.g. room occupancy).
/// Fill hue steps with severity: orange → warning near full → critical when
/// over; the track is a light step of the same family.
class CapacityBars extends StatelessWidget {
  final List<({String label, num value, num max})> rows;
  final int maxRows;

  /// true: bars darken as they fill (capacity). false: one hue (rankings).
  final bool severity;
  const CapacityBars({
    super.key,
    required this.rows,
    this.maxRows = 8,
    this.severity = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = rows.take(maxRows).toList();
    return Column(
      children: [
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final frac = r.max <= 0
                          ? 0.0
                          : (r.value / r.max).clamp(0.0, 1.0).toDouble();
                      final full = r.max > 0 && r.value >= r.max;
                      final fill = !severity
                          ? AppColors.primary
                          : r.value > r.max
                          ? StatusColors.critical
                          : full
                          ? AppColors.primaryDeep
                          : AppColors.primary;
                      return Stack(
                        children: [
                          Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            height: 12,
                            width: c.maxWidth * frac,
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${r.value}/${r.max}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (rows.length > maxRows)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+${rows.length - maxRows} more — see the table',
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// One whole split into parts (e.g. repairs by status), 2px surface gaps,
/// with an icon + label + count legend so status is never colour-alone.
class SegmentedBar extends StatelessWidget {
  final List<({String label, int value, Color color, IconData icon})> parts;
  const SegmentedBar({super.key, required this.parts});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = parts.fold<int>(0, (s, p) => s + p.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 16,
            child: total == 0
                ? Container(color: colors.surfaceContainerHighest)
                : Row(
                    children: [
                      for (var i = 0; i < parts.length; i++)
                        if (parts[i].value > 0)
                          Expanded(
                            flex: parts[i].value,
                            child: Container(
                              margin: EdgeInsets.only(
                                left: i == 0 ? 0 : 2,
                              ), // 2px surface gap
                              color: parts[i].color,
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(p.icon, size: 14, color: p.color),
                  const SizedBox(width: 4),
                  Text(
                    p.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${p.value}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
