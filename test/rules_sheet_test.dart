import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/features/rules/rules_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('rules open, show every tab and close at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: WithRulesButton(child: SizedBox.expand())),
      ));

      await tester.tap(find.byTooltip('How to play'));
      await tester.pumpAndSettle();
      expect(find.text('How to play'), findsOneWidget);
      expect(find.textContaining('lowest total points'), findsWidgets);

      for (final tab in ['Powers', 'Slapping', 'Winning', 'Basics']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        // Scroll to the end of the tab so every part gets laid out
        await tester.drag(find.byType(ListView).hitTestable(), const Offset(0, -3000));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('How to play'), findsNothing);
    });
  }
}
