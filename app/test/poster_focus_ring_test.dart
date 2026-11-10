import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/tv/tv_focus_ring.dart';
import 'package:onyx/widgets/global/poster_card.dart';

import 'support/tv_nav_harness.dart';

/// L'anneau blanc de focus (ADR-0111), où qu'il soit dessiné.
Finder _ring() => find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.border is Border &&
          (decoration.border! as Border).top.color == AppColors.focus;
    });

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets(
        'l’anneau d’une affiche focalisée l’entoure sans mordre sur l’image',
        (tester) async {
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              height: 225,
              child: PosterCard(
                posterUrl: null,
                title: 'Titre',
                showMeta: false,
                autofocus: true,
                onTap: () {},
              ),
            ),
          ),
        ),
        engine: engine,
      );
      await tester.pumpAndSettle();

      expect(_ring(), findsOneWidget,
          reason: 'un seul anneau : pas de liseré dans l’affiche en plus');
      final poster = tester.getRect(find.byType(ClipRRect).first);
      final ring = tester.getRect(_ring());
      expect(ring.left, lessThan(poster.left));
      expect(ring.right, greaterThan(poster.right));
      expect(ring.top, lessThan(poster.top));
      expect(ring.bottom, greaterThan(poster.bottom));
    });
  });

  testWidgets(
      'une rangée de téléviseur réserve la place de l’anneau en haut et en bas',
      (tester) async {
    await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Builder(builder: (context) {
          final room = PosterCard.railRoom(context);
          // L'affiche grandit vers le haut depuis son pied : le soulèvement et
          // l'anneau au-dessus, l'anneau seul en dessous.
          expect(room.bottom, greaterThanOrEqualTo(TvFocusRing.reach));
          expect(
              room.top,
              greaterThanOrEqualTo(
                  TvFocusRing.reach + PosterCard.liftHeadroom));
          return const SizedBox();
        }),
      ),
    );
  });
}
