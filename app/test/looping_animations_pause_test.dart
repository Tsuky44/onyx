import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/skeleton.dart';

void main() {
  testWidgets('le squelette ne tourne plus quand son ticker est coupé',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TickerMode(
        enabled: false,
        child: SkeletonPulse(child: SizedBox(width: 20, height: 20)),
      ),
    ));
    // Une animation encore active ferait échouer pumpAndSettle (timeout).
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('le squelette pulse dans son propre calque', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SkeletonPulse(child: SizedBox(width: 20, height: 20)),
    ));
    expect(
      find.descendant(
        of: find.byType(SkeletonPulse),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(tester.hasRunningAnimations, isTrue);
  });
}
