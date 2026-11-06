import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/tv_focus.dart';

import 'support/tv_nav_harness.dart';

/// Une liste verticale montée comme dans l'app, par le banc commun : la
/// politique de parcours de l'ancien système passe par
/// `TvFocusScroll.requestFocus`, dpad fait défiler la cible lui-même.
///
/// [tvFocusable] faux monte des `Focus` ordinaires, que seul l'ancien système
/// sait parcourir.
Future<(List<FocusNode>, ScrollController)> _pumpList(
  WidgetTester tester, {
  required TvNavEngine engine,
  required bool tvFocusable,
  bool keepAll = false,
  bool isTv = true,
  bool animated = false,
}) async {
  final nodes = [for (var i = 0; i < 6; i++) FocusNode(debugLabel: 'row$i')];
  final controller = ScrollController();
  addTearDown(() {
    controller.dispose();
    for (final node in nodes) {
      node.dispose();
    }
  });
  Widget list() => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 300,
          child: ListView(
            controller: controller,
            // Garde construites les rangées hors de l'écran, pour qu'une
            // rangée défilée hors de la vue garde son focus.
            scrollCacheExtent:
                keepAll ? const ScrollCacheExtent.pixels(2000) : null,
            children: [
              for (final node in nodes)
                tvFocusable
                    ? TvFocusable(
                        focusNode: node,
                        focusScale: 1,
                        onSelect: () {},
                        child: const SizedBox(height: 200),
                      )
                    : Focus(
                        focusNode: node, child: const SizedBox(height: 200)),
            ],
          ),
        ),
      );
  await TvNavHarness.pump(
    tester,
    animated
        ? Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: false),
              child: list(),
            ),
          )
        : list(),
    engine: engine,
    isTv: isTv,
  );
  nodes.first.requestFocus();
  await tester.pumpAndSettle();
  return (nodes, controller);
}

Future<void> _down(WidgetTester tester) =>
    tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets('une flèche fait défiler une seule fois, sans saut',
        (tester) async {
      // Animé : l'ancien système doit y déplacer la liste par animation, et
      // non d'un saut.
      final (nodes, controller) = await _pumpList(tester,
          engine: engine,
          tvFocusable: true,
          animated: engine == TvNavEngine.legacy);
      final start = controller.offset;

      await _down(tester);
      await _down(tester);
      await tester.pump();

      expect(nodes[2].hasFocus, isTrue);
      switch (engine) {
        case TvNavEngine.legacy:
          // Le parcours de Flutter aurait déjà sauté pour montrer la cible au
          // bord ; seule l'animation de la carte doit déplacer la liste.
          expect(controller.offset, start);
        case TvNavEngine.dpad:
          // dpad fait défiler la cible lui-même (autoScroll), sans animation
          // ici : la liste a déjà bougé.
          expect(controller.offset, greaterThan(start));
      }

      final afterKeys = controller.offset;
      await tester.pumpAndSettle();
      if (engine == TvNavEngine.legacy) {
        expect(controller.offset, greaterThan(start));
      } else {
        // Un seul défilement par flèche : rien ne reprend après coup.
        expect(controller.offset, afterKeys);
      }
    });

    testWidgets(
        'Haut sur le premier élément resté hors de l’écran le ramène, au lieu '
        'de défiler d’un demi-écran', (tester) async {
      final (nodes, controller) = await _pumpList(tester,
          engine: engine, tvFocusable: true, keepAll: true);
      // Le focus est en haut, mais la page est en bas : l'état où un second
      // appui arrivait pendant que la page montait vers le bouton retour.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(nodes[0].hasFocus, isTrue);
      expect(controller.offset, 0);
    });

    testWidgets(
        'Bas vers une cible restée au-dessus de l’écran la fait apparaître',
        (tester) async {
      final (nodes, controller) = await _pumpList(tester,
          engine: engine, tvFocusable: true, keepAll: true);
      nodes[1].requestFocus();
      await tester.pump();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      await _down(tester);
      await tester.pumpAndSettle();

      expect(nodes[2].hasFocus, isTrue);
      // La rangée 2 occupe 400 à 600 : elle doit être dans la fenêtre de 300.
      expect(controller.offset, lessThanOrEqualTo(400));
      expect(controller.offset, greaterThanOrEqualTo(300));
    });

    testWidgets('hors téléviseur, Flutter garde son défilement',
        (tester) async {
      final (nodes, controller) = await _pumpList(tester,
          engine: engine, tvFocusable: false, isTv: false);

      await _down(tester);
      await _down(tester);
      await tester.pump();

      expect(nodes[2].hasFocus, isTrue);
      expect(controller.offset, greaterThan(0));
    });
  });

  // Ces trois tests visent l'ancienne politique de parcours (`Focus`
  // ordinaires, `TvFocusScroll`) : dpad ne parcourt que ses propres cibles, et
  // l'ancien système disparaît en phase 8.
  group('legacy seulement', () {
    const legacy = TvNavEngine.legacy;

    testWidgets('un élément ordinaire défile aussi en douceur', (tester) async {
      final (nodes, controller) = await _pumpList(tester,
          engine: legacy, tvFocusable: false, animated: true);

      await _down(tester);
      await _down(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(nodes[2].hasFocus, isTrue);
      final midway = controller.offset;
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(midway));
    });

    testWidgets('Haut sur un élément ordinaire resté hors de l’écran le ramène',
        (tester) async {
      final (nodes, controller) = await _pumpList(tester,
          engine: legacy, tvFocusable: false, keepAll: true);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(nodes[0].hasFocus, isTrue);
      expect(controller.offset, 0);
    });

    testWidgets(
        'Bas vers un élément ordinaire resté au-dessus de l’écran le fait '
        'apparaître', (tester) async {
      final (nodes, controller) = await _pumpList(tester,
          engine: legacy, tvFocusable: false, keepAll: true);
      nodes[1].requestFocus();
      await tester.pump();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      await _down(tester);
      await tester.pumpAndSettle();

      expect(nodes[2].hasFocus, isTrue);
      expect(controller.offset, lessThanOrEqualTo(400));
      expect(controller.offset, greaterThanOrEqualTo(300));
    });
  });
}
