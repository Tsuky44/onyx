import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_scroll.dart';
import 'package:onyx/tv/tv_key_repeat.dart';
import 'package:onyx/tv/tv_mode.dart';

void main() {
  setUp(() {
    TvMode.enabled.value = true;
    TvKeyRepeat.debugReset();
  });
  tearDown(() => TvMode.enabled.value = false);

  /// Une liste verticale montée comme dans l'app : la politique de parcours
  /// passe par [TvFocusScroll.requestFocus].
  Future<(List<FocusNode>, ScrollController)> pumpList(
    WidgetTester tester, {
    required bool tvFocusable,
    bool keepAll = false,
  }) async {
    final nodes = [for (var i = 0; i < 6; i++) FocusNode(debugLabel: 'row$i')];
    final controller = ScrollController();
    addTearDown(() {
      controller.dispose();
      for (final node in nodes) {
        node.dispose();
      }
    });
    await tester.pumpWidget(TvScope(
      isTv: true,
      child: MaterialApp(
        actions: <Type, Action<Intent>>{
          ...WidgetsApp.defaultActions,
          DirectionalFocusIntent: TvDirectionalFocusAction(),
        },
        builder: (context, child) => FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(
            requestFocusCallback: TvFocusScroll.requestFocus,
          ),
          child: child!,
        ),
        home: Align(
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
                          child: const SizedBox(height: 200),
                        )
                      : Focus(
                          focusNode: node,
                          child: const SizedBox(height: 200),
                        ),
              ],
            ),
          ),
        ),
      ),
    ));
    nodes.first.requestFocus();
    await tester.pumpAndSettle();
    return (nodes, controller);
  }

  testWidgets('une flèche fait défiler une seule fois, sans saut',
      (tester) async {
    final (nodes, controller) = await pumpList(tester, tvFocusable: true);
    final start = controller.offset;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // Le parcours de Flutter aurait déjà sauté pour montrer la cible au bord ;
    // seule l'animation de la carte doit déplacer la liste.
    expect(nodes[2].hasFocus, isTrue);
    expect(controller.offset, start);

    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(start));
  });

  testWidgets('un élément ordinaire défile aussi en douceur', (tester) async {
    final (nodes, controller) = await pumpList(tester, tvFocusable: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(nodes[2].hasFocus, isTrue);
    final midway = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(midway));
  });

  testWidgets('hors téléviseur, Flutter garde son défilement', (tester) async {
    TvMode.enabled.value = false;
    final (nodes, controller) = await pumpList(tester, tvFocusable: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(nodes[2].hasFocus, isTrue);
    expect(controller.offset, greaterThan(0));
  });

  testWidgets(
      'Haut sur le premier élément resté hors de l’écran le ramène, au lieu '
      'de défiler d’un demi-écran', (tester) async {
    final (nodes, controller) =
        await pumpList(tester, tvFocusable: false, keepAll: true);
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
    final (nodes, controller) =
        await pumpList(tester, tvFocusable: false, keepAll: true);
    nodes[1].requestFocus();
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(nodes[2].hasFocus, isTrue);
    // La rangée 2 occupe 400 à 600 : elle doit être dans la fenêtre de 300.
    expect(controller.offset, lessThanOrEqualTo(400));
    expect(controller.offset, greaterThanOrEqualTo(300));
  });
}
