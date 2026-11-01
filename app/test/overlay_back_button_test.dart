import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/overlay_back_button.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  testWidgets('le bouton retour rappelle onPressed au toucher', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_host(
      Positioned(
        top: 0,
        left: 0,
        child: OverlayBackButton(onPressed: () => pressed++),
      ),
    ));

    await tester.tap(find.byType(OverlayBackButton));
    expect(pressed, 1);
  });

  testWidgets('le disque se cale sur la marge de la page',
      (tester) async {
    const pad = 48.0;
    await tester.pumpWidget(_host(
      Positioned(
        top: 0,
        left: pad - OverlayBackButton.discInset,
        child: const OverlayBackButton(),
      ),
    ));

    final disc = find.descendant(
      of: find.byType(OverlayBackButton),
      matching: find.byType(Icon),
    );
    // Le disque fait 36 px, centré dans la zone tactile de 48 : l'icône est au
    // milieu, donc le bord gauche du disque tombe sur la marge.
    expect(tester.getCenter(disc).dx, pad + 18);
  });
}
