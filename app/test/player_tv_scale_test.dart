import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/player_popups.dart';
import 'package:onyx/screens/player/widgets/player_tv_scale.dart';

void main() {
  void setScreen(WidgetTester tester, Size logical) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = logical * 2.0;
    addTearDown(tester.view.reset);
  }

  Widget playerStack(Widget layer) => MaterialApp(
        home: Stack(children: [const SizedBox.expand(), layer]),
      );

  testWidgets(
      'un téléviseur Android de 960 px logiques dessine le chrome à '
      'l’échelle des pages', (tester) async {
    setScreen(tester, const Size(960, 540));
    Size? seen;

    await tester.pumpWidget(playerStack(PlayerTvScale.layer(
      isTv: true,
      child: Builder(builder: (context) {
        seen = MediaQuery.sizeOf(context);
        return const Stack(children: [
          Positioned(
            left: 1000,
            top: 600,
            width: 200,
            height: 100,
            child: SizedBox(key: ValueKey('button')),
          ),
        ]);
      }),
    )));

    expect(seen, const Size(1280, 720),
        reason: 'le lecteur se met en page sur la largeur des pages d’un '
            'téléviseur (ADR-0130) : ses tailles ont été dessinées pour elle');
    final drawn = tester.getRect(find.byKey(const ValueKey('button')));
    expect(drawn.left, closeTo(750, 0.01));
    expect(drawn.top, closeTo(450, 0.01));
    expect(drawn.width, closeTo(150, 0.01));
  });

  testWidgets(
      'l’Apple TV, qui annonce 1920 points, agrandit le chrome d’une fois et '
      'demie', (tester) async {
    setScreen(tester, const Size(1920, 1080));
    Size? seen;

    await tester.pumpWidget(playerStack(PlayerTvScale.layer(
      isTv: true,
      child: Builder(builder: (context) {
        seen = MediaQuery.sizeOf(context);
        return const Stack(children: [
          Positioned(
            left: 53,
            top: 40,
            width: 44,
            height: 44,
            child: SizedBox(key: ValueKey('button')),
          ),
        ]);
      }),
    )));

    expect(seen, const Size(1280, 720));
    final drawn = tester.getRect(find.byKey(const ValueKey('button')));
    // La marge de 53 retombe sur les 80 points de la zone sûre d'Apple, le
    // bouton de verre de 44 sur ses 66 points.
    expect(drawn.left, closeTo(79.5, 0.01));
    expect(drawn.top, closeTo(60, 0.01));
    expect(drawn.width, closeTo(66, 0.01));
    expect(PlayerTvScale.factorFor(1920, isTv: true), 1.5);
  });

  testWidgets('une couche Positioned garde sa place dans la couche réduite',
      (tester) async {
    setScreen(tester, const Size(960, 540));

    await tester.pumpWidget(playerStack(PlayerTvScale.layer(
      isTv: true,
      child: const Positioned.fill(child: SizedBox(key: ValueKey('panel'))),
    )));

    expect(tester.getRect(find.byKey(const ValueKey('panel'))),
        const Rect.fromLTWH(0, 0, 960, 540));
  });

  testWidgets('un écran déjà à 1280 points n’est pas touché', (tester) async {
    setScreen(tester, const Size(1280, 720));

    await tester.pumpWidget(playerStack(PlayerTvScale.layer(
      isTv: true,
      child: const SizedBox.expand(),
    )));

    expect(find.byType(FittedBox), findsNothing);
  });

  testWidgets('hors téléviseur, la couche est rendue telle quelle',
      (tester) async {
    setScreen(tester, const Size(960, 540));
    const child = SizedBox.expand(key: ValueKey('chrome'));

    expect(PlayerTvScale.layer(isTv: false, child: child), same(child));
    expect(PlayerTvScale.factorFor(960, isTv: false), 1);
    expect(PlayerTvScale.factorFor(960, isTv: true), 0.75);
  });

  testWidgets(
      'le menu des réglages se place sur le bouton dans la couche réduite',
      (tester) async {
    setScreen(tester, const Size(960, 540));
    final anchor = GlobalKey();

    await tester.pumpWidget(playerStack(PlayerTvScale.layer(
      isTv: true,
      child: Stack(children: [
        Positioned(
          left: 1000,
          top: 600,
          width: 80,
          height: 80,
          child: SizedBox(key: anchor),
        ),
      ]),
    )));

    const scale = 0.75;
    final atScale = placeSettingsPopup(
      anchor.currentContext,
      const Size(960, 540) / scale,
      scale: scale,
    );
    // Le même bouton dans un lecteur de 1280 sans réduction : le menu doit
    // tomber au même endroit de sa mise en page.
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        Positioned(
          left: 1000,
          top: 600,
          width: 80,
          height: 80,
          child: SizedBox(key: anchor),
        ),
      ]),
    ));
    setScreen(tester, const Size(1280, 720));
    await tester.pump();
    final unscaled =
        placeSettingsPopup(anchor.currentContext, const Size(1280, 720));

    expect(atScale.left, closeTo(unscaled.left, 0.01));
    expect(atScale.top, unscaled.top);
    expect(atScale.bottom, unscaled.bottom);
    expect(atScale.maxHeight, closeTo(unscaled.maxHeight, 0.01));
  });
}
