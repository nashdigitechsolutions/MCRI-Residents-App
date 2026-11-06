// Renders frames of the launch animation to build/splash_frames.png.
//   flutter test tool/splash_frames_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:mcri_residents_app/widgets/animated_splash.dart';

void main() {
  testWidgets('splash frames', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AnimatedSplash(onFinished: () {}),
        ),
      ),
    );
    // Make sure the badge image is decoded before capturing.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/branding/splash_badge.png'),
        tester.element(find.byType(AnimatedSplash)),
      );
    });

    const stamps = [0, 300, 700, 1000, 1400, 1800, 2200, 2600];
    final frames = <ui.Image>[];
    var elapsed = 0;
    for (final ms in stamps) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        frames.add(await boundary.toImage());
      });
    }

    await tester.runAsync(() async {
      const w = 360.0, h = 640.0;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      for (var i = 0; i < frames.length; i++) {
        final dx = (i % 4) * w, dy = (i ~/ 4) * h;
        c.drawImage(frames[i], Offset(dx, dy), Paint());
        c.drawRect(Rect.fromLTWH(dx, dy, w, h), Paint()..style = PaintingStyle.stroke..color = Colors.black26);
      }
      final sheet = await rec.endRecording().toImage((w * 4).toInt(), (h * 2).toInt());
      final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/splash_frames.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
