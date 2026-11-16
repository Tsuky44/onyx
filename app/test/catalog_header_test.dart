import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/library/widgets/catalog_header.dart';
import 'package:onyx/widgets/global/onyx_menu.dart';

void main() {
  testWidgets('le bouton Affichage reste collé au bord droit, le tri avant lui',
      (tester) async {
    for (final title in ['Films', 'Une bibliothèque au nom bien plus long']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: CatalogHeader<int>(
                title: title,
                countLabel: '28 titres',
                sortOptions: const {0: 'Récents', 1: 'A → Z'},
                sort: 0,
                onSortChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Le tri est le premier menu de la ligne, le bouton d'affichage le
      // dernier : celui-ci ferme la ligne, à droite.
      final menus = find.byType(OnyxMenuButton<int>);
      final sort = menus.first;
      final display = menus.last;
      final headerRight = tester.getTopRight(find.byType(CatalogHeader<int>));
      expect(tester.getTopRight(display).dx, headerRight.dx, reason: title);
      expect(
          tester.getTopRight(sort).dx, lessThan(tester.getTopLeft(display).dx),
          reason: title);
    }
  });
}
