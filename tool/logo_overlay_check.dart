// Draws LogoGeometry in red over the real logo to check the trace.
// Run: dart run tool/logo_overlay_check.dart  -> build/logo_overlay.png
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:mcri_residents_app/theme/logo_geometry.dart';

void main() {
  final logo = img.decodePng(File('lib/assets/logo.png').readAsBytesSync())!;
  final red = img.ColorRgba8(255, 0, 0, 150);
  final blue = img.ColorRgba8(0, 60, 255, 150);

  void poly(List<(double, double)> pts, img.Color c, num t) {
    for (var i = 0; i < pts.length - 1; i++) {
      img.drawLine(
        logo,
        x1: pts[i].$1.round(),
        y1: pts[i].$2.round(),
        x2: pts[i + 1].$1.round(),
        y2: pts[i + 1].$2.round(),
        color: c,
        thickness: t,
        antialias: true,
      );
    }
  }

  for (final p in LogoGeometry.house) {
    poly(p, blue, 6);
  }
  for (final p in LogoGeometry.m) {
    poly(p, red, 8);
  }
  Directory('build').createSync(recursive: true);
  File('build/logo_overlay.png').writeAsBytesSync(img.encodePng(logo));
  stdout.writeln('wrote build/logo_overlay.png');
}
