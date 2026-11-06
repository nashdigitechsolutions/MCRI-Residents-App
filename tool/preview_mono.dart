// Preview: monochrome mark on black, plus a 48px (xxhdpi status bar) copy.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final mono = img.decodePng(
    File('assets/branding/monochrome.png').readAsBytesSync(),
  )!;
  final canvas = img.Image(width: 1024 + 220, height: 1024);
  img.fill(canvas, color: img.ColorRgb8(20, 20, 20));
  img.compositeImage(canvas, mono);
  final small = img.copyResize(
    img.copyCrop(mono, x: 160, y: 160, width: 704, height: 704),
    width: 48,
    height: 48,
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(canvas, small, dstX: 1100, dstY: 100);
  img.compositeImage(
    canvas,
    img.copyResize(
      small,
      width: 96,
      height: 96,
      interpolation: img.Interpolation.nearest,
    ),
    dstX: 1080,
    dstY: 200,
  );
  File('build/mono_preview.png').writeAsBytesSync(img.encodePng(canvas));
}
