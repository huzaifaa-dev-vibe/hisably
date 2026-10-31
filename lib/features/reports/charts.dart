import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/theme_spec.dart';

/// Hand-painted charts — no charting dependency, every colour from the
/// active theme spec, all values passed pre-normalised (minor units).
///
/// All painters are pure functions of (canvas, size, data) and draw with
/// anti-aliasing; they render identically in every theme because colours
/// are resolved in the widgets, not inside the painters.

// ---------------------------------------------------------------------------
// Donut
// ---------------------------------------------------------------------------

class DonutSlice {
  const DonutSlice({required this.value, required this.color});
  final double value;
  final Color color;
}

/// Slices are (value, color); values must be > 0. The centre shows a label.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerLabel,
    required this.centerSublabel,
    this.size = 168,
  });

  final List<DonutSlice> slices;
  final String centerLabel;
  final String centerSublabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: slices,
          trackColor: s.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerSublabel,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 2),
              Text(
                centerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.trackColor});

  final List<DonutSlice> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.30;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius - stroke / 2, track);

    final total = slices.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0 || slices.isEmpty) return;

    const gap = 0.035; // radians between slices
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    var start = -math.pi / 2;
    final usable = 2 * math.pi - (slices.length - 1) * gap;
    for (final slice in slices) {
      final sweep = (slice.value / total) * usable;
      paint.color = slice.color;
      canvas.drawArc(rect, start, math.max(sweep, 0.01), false, paint);
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices || old.trackColor != trackColor;
}

// ---------------------------------------------------------------------------
// Grouped bars (daily in/out, monthly in/out)
// ---------------------------------------------------------------------------

/// Each group renders two bars (in = income colour, out = expense colour)
/// with an optional label under the group.
class GroupedBarChart extends StatelessWidget {
  const GroupedBarChart({
    super.key,
    required this.groups,
    required this.maxValue,
    this.height = 170,
    this.labelEvery = 1,
  });

  /// (label, inValue, outValue) — values in minor units, already scoped to
  /// a single currency.
  final List<(String, double, double)> groups;
  final double maxValue;
  final double height;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarsPainter(
          groups: groups,
          maxValue: maxValue <= 0 ? 1 : maxValue,
          inColor: s.income,
          outColor: s.expense,
          axisColor: s.isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          labelColor: s.textTertiary,
          labelEvery: labelEvery,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.groups,
    required this.maxValue,
    required this.inColor,
    required this.outColor,
    required this.axisColor,
    required this.labelColor,
    required this.labelEvery,
  });

  final List<(String, double, double)> groups;
  final double maxValue;
  final Color inColor;
  final Color outColor;
  final Color axisColor;
  final Color labelColor;
  final int labelEvery;

  @override
  void paint(Canvas canvas, Size size) {
    if (groups.isEmpty) return;
    const topPad = 10.0;
    const bottomPad = 20.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width;

    // Baseline.
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, size.height - bottomPad), Offset(chartW, size.height - bottomPad), axis);

    final n = groups.length;
    final groupW = chartW / n;
    final barW = math.min(groupW * 0.30, 14.0);
    final barPaint = Paint();

    final labelStyle = TextStyle(
      fontSize: 9.5,
      color: labelColor,
      fontWeight: FontWeight.w500,
    );

    for (var i = 0; i < n; i++) {
      final (label, inV, outV) = groups[i];
      final cx = groupW * i + groupW / 2;

      void bar(double v, Color c, double dx) {
        if (v <= 0) return;
        final h = (v / maxValue) * chartH;
        final rrect = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx + dx - barW / 2, topPad + chartH - h, barW, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        barPaint.color = c;
        canvas.drawRRect(rrect, barPaint);
      }

      bar(inV, inColor, -barW / 2 - 1.5);
      bar(outV, outColor, barW / 2 + 1.5);

      if (label.isNotEmpty && (n <= labelEvery || i % labelEvery == 0)) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: groupW + 8);
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, size.height - bottomPad + 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.groups != groups ||
      old.maxValue != maxValue ||
      old.inColor != inColor ||
      old.outColor != outColor;
}

// ---------------------------------------------------------------------------
// Line
// ---------------------------------------------------------------------------

/// Balance-trend line with a soft gradient fill underneath. Values are
/// minor units of ONE currency; negative dips render below the top.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.values,
    required this.minValue,
    required this.maxValue,
    this.height = 170,
  });

  final List<double> values;
  final double minValue;
  final double maxValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(
          values: values,
          minValue: minValue,
          maxValue: maxValue,
          lineColor: s.accent,
          fillColor: s.accent,
          axisColor: s.isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.axisColor,
  });

  final List<double> values;
  final double minValue;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    if (values.length < 2) {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), axis);
      return;
    }

    const pad = 6.0;
    final chartH = size.height - pad * 2;
    final range = (maxValue - minValue) <= 0 ? 1.0 : (maxValue - minValue);
    final dx = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final t = (values[i] - minValue) / range;
      return Offset(dx * i, pad + chartH * (1 - t));
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }

    // Fill under the line, down to the chart bottom.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fillColor.withValues(alpha: 0.28),
            fillColor.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // End-point dot.
    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = lineColor);
    canvas.drawCircle(
      last,
      2,
      Paint()..color = fillColor.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.lineColor != lineColor;
}

// ---------------------------------------------------------------------------
// Progress bar (budgets)
// ---------------------------------------------------------------------------

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.height = 8,
  });

  final double progress; // 0..1 (already clamped)
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(
              color: s.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.07),
            ),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
