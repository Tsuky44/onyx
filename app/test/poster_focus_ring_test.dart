import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/lite_mode.dart';
import 'package:onyx/tv/tv_focus_ring.dart';
import 'package:onyx/utils/responsive.dart';
import 'package:onyx/widgets/global/poster_card.dart';

import 'support/tv_nav_harness.dart';

/// Le focus d'une affiche sur téléviseur (ADR-0118, qui remplace l'ADR-0111) :
/// elle se soulève, sans anneau ; l'anneau ne revient qu'en mode léger.
Finder _ring() => find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.border is Border &&
          (decoration.border! as Border).top.color == AppColors.focus;
    });

Widget _poster({bool lite = false}) => LiteScope(
      isLite: lite,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 176,
            height: 264,
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
    );

/// Le soulèvement de l'affiche : l'`AnimatedScale` de `PosterLift`.
AnimatedScale _lift(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.descendant(
      of: find.byType(PosterLift),
      matching: find.byType(AnimatedScale),
    ).first);

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets(
        'une affiche focalisée se soulève de 10 % depuis son pied, sans anneau',
        (tester) async {
      await TvNavHarness.pump(tester, _poster(), engine: engine);
      await tester.pumpAndSettle();

      expect(_ring(), findsNothing);
      expect(_lift(tester).scale, PosterCard.tvLift);
      expect(_lift(tester).alignment, Alignment.bottomCenter);
      final lifted = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byType(PosterLift),
        matching: find.byType(AnimatedContainer),
      ).first);
      expect((lifted.decoration! as BoxDecoration).boxShadow, isNotEmpty,
          reason: 'c’est l’ombre qui détache l’affiche de la rangée');
    });

    testWidgets(
        'en mode léger, sans ombre, l’anneau revient autour de l’affiche',
        (tester) async {
      await TvNavHarness.pump(tester, _poster(lite: true), engine: engine);
      await tester.pumpAndSettle();

      expect(_ring(), findsOneWidget);
      final poster = tester.getRect(find.byType(ClipRRect).first);
      final ring = tester.getRect(_ring());
      expect(ring.left, lessThan(poster.left));
      expect(ring.right, greaterThan(poster.right));
      expect(ring.top, lessThan(poster.top));
      expect(ring.bottom, greaterThan(poster.bottom));
    });
  });

  testWidgets(
      'une rangée de téléviseur réserve la place du soulèvement au-dessus',
      (tester) async {
    await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Builder(builder: (context) {
          final room = PosterCard.railRoom(context);
          final height = AppLayout.mediaRowCardWidth(context) /
              AppLayout.posterOnlyAspectRatio;
          // L'affiche grandit vers le haut depuis son pied : tout le
          // soulèvement au-dessus, l'anneau du mode léger en dessous.
          expect(room.top,
              greaterThanOrEqualTo(height * (PosterCard.tvLift - 1)));
          expect(room.bottom, greaterThanOrEqualTo(TvFocusRing.reach));
          return const SizedBox();
        }),
      ),
    );
  });

  testWidgets('sur téléviseur, six affiches tiennent dans une rangée',
      (tester) async {
    await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Builder(builder: (context) {
          final step = AppLayout.mediaRowCardWidth(context) +
              AppLayout.mediaRowGap(context);
          // La page d'un téléviseur fait 1280 px de large (`TvUiScale`).
          final visible = (1280 - AppLayout.pagePadding(context)) / step;
          expect(visible, greaterThanOrEqualTo(6));
          expect(visible, lessThan(7));
          return const SizedBox();
        }),
      ),
    );
  });
}
