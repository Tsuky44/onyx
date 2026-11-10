import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_focus.dart';

import 'support/tv_nav_harness.dart';

/// Une rangée de l'accueil, défilante, de [count] cartes de 200 px.
Widget _rail(String prefix, int count) => TvRegion.rail(
      id: 'test/$prefix',
      child: SizedBox(
        height: 120,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          itemCount: count,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 200,
              child: TvFocusable(
                autofocus: prefix == 'a' && i == 0,
                onSelect: () {},
                child: TvTestTile('$prefix$i'),
              ),
            ),
          ),
        ),
      ),
    );

/// ADR-0113 : changer de rangée ramène à sa première carte.
void main() {
  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> pump(WidgetTester tester, {int count = 6}) =>
        TvNavHarness.pump(
          tester,
          Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_rail('a', count), _rail('b', count)],
            ),
          ),
          engine: engine,
        );

    testWidgets(
        'descendre depuis la quatrième carte tombe sur la première de la '
        'rangée suivante', (tester) async {
      final nav = await pump(tester);
      expect(nav.focusedLabel, 'a0');
      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(nav.focusedLabel, 'a3');

      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'b0');
    });

    testWidgets('remonter ne rend pas la carte quittée, mais la première',
        (tester) async {
      final nav = await pump(tester);
      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.right);
      }
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.right);
      expect(nav.focusedLabel, 'b1');

      await nav.press(TraversalDirection.up);
      expect(nav.focusedLabel, 'a0');
    });

    testWidgets(
        'une rangée défilée loin revient à son début et à sa première carte',
        (tester) async {
      final nav = await pump(tester, count: 40);
      await nav.press(TraversalDirection.down);
      // Bien au-delà de ce que la liste garde construit à gauche.
      for (var i = 0; i < 30; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(nav.focusedLabel, 'b30');

      await nav.press(TraversalDirection.up);
      await nav.press(TraversalDirection.down);
      await tester.pumpAndSettle();
      expect(nav.focusedLabel, 'b0');
    });
  });
}
