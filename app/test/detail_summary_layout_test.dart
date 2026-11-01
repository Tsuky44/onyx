import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/detail_summary_section.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DetailSummarySection(
          credits: [],
          infoTable: SizedBox(key: Key('card'), height: 200),
          extra: SizedBox(key: Key('left'), height: 300),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets(
      'sur grand écran, la card d\'infos reste en haut, à droite du corps',
      (tester) async {
    await _pump(tester, 1400);
    final card = tester.getTopLeft(find.byKey(const Key('card')));
    final left = tester.getTopLeft(find.byKey(const Key('left')));
    expect(card.dy, left.dy);
    expect(card.dx, greaterThan(left.dx));
  });

  testWidgets('sur petit écran, la card passe sous le corps', (tester) async {
    await _pump(tester, 600);
    final card = tester.getTopLeft(find.byKey(const Key('card')));
    final left = tester.getBottomLeft(find.byKey(const Key('left')));
    expect(card.dy, greaterThanOrEqualTo(left.dy));
  });
}
