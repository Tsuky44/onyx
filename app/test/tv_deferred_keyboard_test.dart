import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/tv_deferred_keyboard.dart';
import 'package:onyx/tv/tv_focus.dart';

import 'support/tv_nav_harness.dart';

/// Ce que [TvDeferredKeyboard] promet à la télécommande, avec l'ancien système
/// de navigation et avec dpad : le clavier à l'écran ne s'ouvre que sur OK, et
/// la télécommande retrouve la navigation quand il se referme.
void main() {
  /// Le champ entouré de deux cibles, comme dans l'en-tête : les onglets
  /// avant, l'avatar du compte après.
  Future<({TvNavHarness harness, FocusNode field, FocusNode before})> pumpBar(
    WidgetTester tester,
    TvNavEngine engine, {
    bool isTv = true,
  }) async {
    final fieldNode = FocusNode();
    addTearDown(fieldNode.dispose);
    final beforeNode = FocusNode();
    addTearDown(beforeNode.dispose);
    final afterNode = FocusNode();
    addTearDown(afterNode.dispose);

    final harness = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Row(
          children: [
            TvFocusable(
              focusNode: beforeNode,
              onSelect: () {},
              child: const TvTestTile('Avant', width: 40),
            ),
            Expanded(
              child: TvDeferredKeyboard(
                fieldFocusNode: fieldNode,
                builder: (context, focusNode, canRequestFocus) => TextField(
                  focusNode: focusNode,
                  canRequestFocus: canRequestFocus,
                ),
              ),
            ),
            TvFocusable(
              focusNode: afterNode,
              onSelect: () {},
              child: const TvTestTile('Après', width: 40),
            ),
          ],
        ),
      ),
      engine: engine,
      isTv: isTv,
    );
    beforeNode.requestFocus();
    await tester.pump();
    return (harness: harness, field: fieldNode, before: beforeNode);
  }

  Future<void> reachBar(WidgetTester tester, TvNavHarness harness) async {
    for (var i = 0; i < 3 && !_barHasFocus(); i++) {
      await harness.press(TraversalDirection.right);
    }
    expect(_barHasFocus(), isTrue);
  }

  TvNavHarness.forEachEngine((engine) {
    testWidgets('sur téléviseur, traverser la barre n’ouvre pas le clavier',
        (tester) async {
      final bar = await pumpBar(tester, engine);

      // Le parcours s'arrête bien sur la barre — elle n'est pas sautée…
      await reachBar(tester, bar.harness);

      // …mais le champ lui-même ne prend jamais le focus tant qu'on n'a rien
      // demandé, et c'est ce qui empêche Android d'ouvrir son clavier plein
      // écran par-dessus tout ce qui suit dans l'en-tête.
      for (var i = 0; i < 3; i++) {
        await bar.harness.press(TraversalDirection.right);
        expect(bar.field.hasFocus, isFalse);
        await bar.harness.press(TraversalDirection.left);
        expect(bar.field.hasFocus, isFalse);
      }
    });

    testWidgets('OK sur la barre donne le focus au champ', (tester) async {
      final bar = await pumpBar(tester, engine);
      await reachBar(tester, bar.harness);

      await bar.harness.select();

      expect(bar.field.hasFocus, isTrue);
    });

    testWidgets('le champ ressort du parcours quand le clavier se referme',
        (tester) async {
      final bar = await pumpBar(tester, engine);
      await reachBar(tester, bar.harness);
      await bar.harness.select();
      expect(bar.field.hasFocus, isTrue);

      bar.field.unfocus();
      await tester.pumpAndSettle();

      // Sans ce retour en arrière, le passage suivant de la télécommande
      // rouvrirait le clavier tout seul.
      expect(bar.field.hasFocus, isFalse);
      // Le garde-fou de l'ancien système donne parfois le focus lâché à
      // l'élément suivant avant que le champ ne reprenne la barre ; sous dpad,
      // c'est toujours la barre.
      if (engine == TvNavEngine.dpad) expect(_barHasFocus(), isTrue);
      await bar.harness.press(TraversalDirection.right);
      expect(bar.field.hasFocus, isFalse);
    });

    testWidgets(
        'clavier refermé, champ encore focalisé : Retour rend la télécommande '
        'à la barre', (tester) async {
      final bar = await pumpBar(tester, engine);
      // Rien à relâcher tant que le champ n'a pas été ouvert.
      expect(TvDeferredKeyboardState.releaseFocused(), isFalse);

      await reachBar(tester, bar.harness);
      await bar.harness.select();
      expect(bar.field.hasFocus, isTrue);

      // Retour ferme le clavier d'Android TV sans retirer le focus au champ :
      // le Retour suivant proposait de quitter l'app, curseur toujours là.
      expect(TvDeferredKeyboardState.releaseFocused(), isTrue);
      await tester.pumpAndSettle();

      expect(bar.field.hasFocus, isFalse);
      expect(_barHasFocus(), isTrue);
    });

    testWidgets('hors téléviseur, le champ reste un champ ordinaire',
        (tester) async {
      final bar = await pumpBar(tester, engine, isTv: false);

      bar.field.requestFocus();
      await tester.pump();

      // Rien de tout cela ne s'applique à une souris ou à un doigt : le champ
      // prend le focus au clic, comme avant.
      expect(bar.field.hasFocus, isTrue);
    });
  });

  // La flèche qui sort du champ pose le focus sur le voisin, et le champ ne
  // le reprend pas : sans cela, sous dpad, la télécommande rebondissait sur la
  // barre qu'elle venait de quitter.
  group('dpad', () {
    testWidgets('Droite en fin de texte passe à la cible suivante, pour de bon',
        (tester) async {
      final bar = await pumpBar(tester, TvNavEngine.dpad);
      await reachBar(tester, bar.harness);
      await bar.harness.select();
      expect(bar.field.hasFocus, isTrue);

      await bar.harness.press(TraversalDirection.right);
      await tester.pumpAndSettle();

      expect(bar.field.hasFocus, isFalse);
      expect(bar.harness.focusedLabel, 'Après');
    });
  });
}

/// Le nœud du champ-bouton est celui de [TvDeferredKeyboard] : il détient le
/// focus sans que le champ ne l'ait.
bool _barHasFocus() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'tv-deferred-keyboard';
