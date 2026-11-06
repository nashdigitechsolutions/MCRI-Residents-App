// Renders the Android 13+ themed (monochrome) icon with Flutter's canvas so
// diagonal strokes are properly anti-aliased.
//
//   flutter test tool/render_monochrome_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcri_residents_app/theme/logo_geometry.dart';

void main() {
  testWidgets('render monochrome icon', (tester) async {
    await tester.runAsync(() async {
      const size = 1024.0;
      // Fit the mark inside the adaptive-icon safe zone (66/108).
      const scale = 0.60;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..translate(size / 2, size / 2)
        ..scale(scale)
        ..translate(-size / 2, -size / 2 + 20); // optical centring

      Path path(List<(double, double)> pts) {
        final p = Path()..moveTo(pts.first.$1, pts.first.$2);
        for (final q in pts.skip(1)) {
          p.lineTo(q.$1, q.$2);
        }
        return p;
      }

      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.miter
        ..isAntiAlias = true;
      for (final p in LogoGeometry.house) {
        canvas.drawPath(
          path(p),
          paint
            ..strokeWidth = 40
            ..strokeCap = StrokeCap.square,
        );
      }
      for (final p in LogoGeometry.m) {
        canvas.drawPath(
          path(p),
          paint
            ..strokeWidth = 64
            ..strokeCap = StrokeCap.butt,
        );
      }

      final image = await recorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('assets/branding/monochrome.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
