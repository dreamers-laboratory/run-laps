import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:laps/main.dart' as entry;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('About opens from Settings and keeps its company link visible', (tester) async {
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      // Capture the rendered frame; UIKit returned the launch screen in headless runs.
      final view = binding.renderViews.single;
      final layer = view.debugLayer! as OffsetLayer;
      final bytes = await tester.runAsync(() async {
        final frame = await layer.toImage(Offset.zero & view.flutterView.physicalSize);
        try {
          return (await frame.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        } finally {
          frame.dispose();
        }
      });
      final data = binding.reportData ??= <String, dynamic>{};
      final screenshots = (data['screenshots'] ??= <Map<String, Object>>[]) as List;
      screenshots.add({'screenshotName': name, 'bytes': bytes!});
    }

    await entry.main();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    final about = find.text('ABOUT');
    await tester.scrollUntilVisible(
      about,
      180,
      scrollable: find.descendant(
        of: find.byType(entry.ProfilePage),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    await tester.tap(about);
    await tester.pumpAndSettle();

    final credit = find.text('BUILT BY DREAMERS');
    expect(credit.hitTestable(), findsOneWidget);
    expect(find.textContaining('counts track laps').hitTestable(), findsOneWidget);
    await capture('run-laps-about');

    final source = find.text('Open source on GitHub');
    final footer = tester.getTopLeft(credit);
    await tester.scrollUntilVisible(source, 160);
    expect(source.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(credit), footer);
    await capture('run-laps-about-links');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(credit, findsNothing);
    expect(about, findsOneWidget);
  });
}
