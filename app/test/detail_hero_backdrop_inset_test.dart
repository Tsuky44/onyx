import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/detail_hero.dart';
import 'package:onyx/widgets/global/overlay_back_button.dart';

void main() {
  testWidgets(
      'sur grand écran, le fond de la fiche commence sous l’en-tête de verre',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late double expectedInset;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            padding: EdgeInsets.only(top: 100),
          ),
          child: Builder(builder: (context) {
            expectedInset = OverlayBackButton.topInsetFor(context);
            return const DetailHero(
              backdropUrl: 'https://example.com/backdrop.jpg',
              posterUrl: null,
              logoUrl: null,
              title: 'Titre',
              playKey: 'x',
            );
          }),
        ),
      ),
    ));

    final backdropFinder = find.byType(DetailBackdrop);
    expect(backdropFinder, findsOneWidget);

    final paddingWidget = tester.widget<Padding>(
      find.descendant(
        of: backdropFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Padding && w.padding == EdgeInsets.only(top: expectedInset),
        ),
      ),
    );
    expect((paddingWidget.padding as EdgeInsets).top, expectedInset);
  });

  testWidgets(
      'sur écran compact, le fond de la fiche reste en haut (sous la barre d’état)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 44),
          ),
          child: const DetailHero(
            backdropUrl: 'https://example.com/backdrop.jpg',
            posterUrl: null,
            logoUrl: null,
            title: 'Titre',
            playKey: 'x',
          ),
        ),
      ),
    ));

    final backdropFinder = find.byType(DetailBackdrop);
    expect(backdropFinder, findsOneWidget);

    final paddingWidget = tester.widget<Padding>(
      find.descendant(
        of: backdropFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Padding && w.padding == EdgeInsets.zero,
        ),
      ),
    );
    expect((paddingWidget.padding as EdgeInsets).top, 0.0);
  });
}
