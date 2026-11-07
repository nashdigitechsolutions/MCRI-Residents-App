import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcri_residents_app/widgets/app_loader.dart';
import 'package:mcri_residents_app/widgets/app_refresh.dart';

void main() {
  for (final physics in [
    const ClampingScrollPhysics(),
    const BouncingScrollPhysics(),
  ]) {
    testWidgets(
      'pull to refresh shows AppLoader and calls onRefresh (${physics.runtimeType})',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppRefreshIndicator(
                onRefresh: () async {
                  calls++;
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                },
                child: ListView(
                  physics: AlwaysScrollableScrollPhysics(parent: physics),
                  children: [
                    for (var i = 0; i < 3; i++) ListTile(title: Text('Row $i')),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.byType(AppLoader), findsNothing);
        await tester.fling(find.text('Row 0'), const Offset(0, 300), 1000);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, 1);
        expect(find.byType(AppLoader), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.byType(AppLoader), findsNothing);
      },
    );
  }

  testWidgets('a small pull does not refresh', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppRefreshIndicator(
            onRefresh: () async => calls++,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [ListTile(title: Text('Row'))],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('Row'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
