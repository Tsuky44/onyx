import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/media_logo_display.dart';

/// Le titre ne paraît pas puis disparaît quand le logo arrive : un logo attendu
/// tient sa place vide, et seul un titre sans logo s'écrit.
void main() {
  Widget host(String? logoUrl) => MaterialApp(
        home: Scaffold(
          body: MediaLogoDisplay(
            title: 'Dune',
            logoUrl: logoUrl,
            maxHeight: 100,
            maxWidth: 300,
          ),
        ),
      );

  testWidgets('un logo en cours de chargement n’écrit pas le titre',
      (tester) async {
    await tester.pumpWidget(host('https://image.tmdb.org/t/p/w500/logo.png'));
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('sans logo, le titre s’écrit', (tester) async {
    await tester.pumpWidget(host(null));
    expect(find.text('Dune'), findsOneWidget);
  });
}
