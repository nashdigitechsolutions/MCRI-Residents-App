// Renders a contact sheet of the new UI bits to build/ui_preview.png:
// loader (several sizes / moments), switches (all states, light + dark),
// and the in-app drop-down banner.
//   flutter test tool/ui_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcri_residents_app/navigation/app_navigator.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:mcri_residents_app/widgets/app_loader.dart';
import 'package:mcri_residents_app/widgets/in_app_banner.dart';

Future<void> _fonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

Widget _switches(bool dark) => Theme(
      data: dark ? AppTheme.dark() : AppTheme.light(),
      child: Builder(
        builder: (context) => Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: true, onChanged: (_) {}),
              Switch(value: false, onChanged: (_) {}),
              const Switch(value: true, onChanged: null),
              const Switch(value: false, onChanged: null),
              Checkbox(value: true, onChanged: (_) {}),
              Checkbox(value: false, onChanged: (_) {}),
              OutlinedButton(onPressed: () {}, child: const Text('Outline')),
            ],
          ),
        ),
      ),
    );

void main() {
  setUpAll(_fonts);

  testWidgets('ui preview', (tester) async {
    tester.view.physicalSize = const Size(700, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final appKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: appKey,
        child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 120, left: 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Loader — 16 / 24 / 40 / 72 px, plus white on orange'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const AppLoader(size: 16),
                      const SizedBox(width: 16),
                      const AppLoader(size: 24),
                      const SizedBox(width: 16),
                      const AppLoader(size: 40),
                      const SizedBox(width: 16),
                      const AppLoader(size: 72),
                      const SizedBox(width: 16),
                      Container(
                        width: 120,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const SizedBox(width: 22, height: 22, child: AppLoader(color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('Switches (on / off / disabled on / disabled off), checkboxes, outline — light'),
                  const SizedBox(height: 6),
                  _switches(false),
                  const SizedBox(height: 10),
                  const Text('…and dark'),
                  const SizedBox(height: 6),
                  _switches(true),
                  const SizedBox(height: 18),
                  const Text('Full-page loading view'),
                  const SizedBox(height: 8),
                  const SizedBox(height: 150, child: AppLoadingView(message: 'Loading messages…')),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );

    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/branding/splash_badge.png'),
        tester.element(find.byType(Scaffold)),
      );
    });
    InAppBanner.show(
      title: 'Sipho Ndlovu',
      body: 'Are you coming to the braai tonight? Bring the speaker 🔊',
      data: const {'screen': 'conversation', 'conversation_id': 3},
      icon: Icons.chat_bubble_rounded,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await tester.runAsync(() async {
      // Capture the whole app, including the Overlay the banner lives in.
      final image = await (appKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/ui_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // Let the banner's auto-dismiss timer finish cleanly.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentContext, isNotNull);
  });
}
