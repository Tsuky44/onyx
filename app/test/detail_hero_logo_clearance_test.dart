import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/detail_hero.dart';
import 'package:onyx/widgets/global/overlay_back_button.dart';

/// Le surtitre (FILM / SÉRIE) ne passe jamais sous la barre du haut : le texte
/// de l'en-tête est ancré en bas, et un logo haut le faisait remonter sans
/// borne. C'est le logo qui rétrécit.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (_) => DetailHero(
              backdropUrl: null,
              posterUrl: null,
              logoUrl: 'https://image.tmdb.org/t/p/w500/logo.png',
              title: 'Un titre',
              playKey: 'x',
              eyebrow: const Text('FILM'),
              tagline: 'Une accroche',
              overview: 'Un synopsis. ' * 40,
              actions: const SizedBox(height: 120),
            ),
          ),
        ),
      ),
    ));
  }

  for (final size in const [Size(1400, 900), Size(390, 700)]) {
    testWidgets('le surtitre reste sous la barre à ${size.width.toInt()} px',
        (tester) async {
      await pump(tester, size);
      final context = tester.element(find.byType(DetailHero));
      final bar = OverlayBackButton.toolbarHeightFor(context);

      expect(
          tester.getTopLeft(find.text('FILM')).dy, greaterThanOrEqualTo(bar));
      expect(tester.takeException(), isNull);
    });
  }
}
