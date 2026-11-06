import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/onyx_dpad.dart';
import 'package:onyx/tv/tv_focus.dart';

import 'support/tv_nav_harness.dart';

/// Un téléviseur LG ouvre l'app web (ADR-0076), dont les raccourcis par défaut
/// sont ceux d'une page : les flèches y font défiler, et le D-pad ne passait
/// plus d'une affiche à l'autre sur l'accueil.
///
/// - **Ancien système** : [webTvShortcuts] rend aux flèches et à OK leur sens
///   de télécommande.
/// - **dpad** : plus de `webTvShortcuts`. Les flèches et OK passent par le jeu
///   de touches d'`OnyxDpad`, posé plus près du focus que les raccourcis de la
///   page ; et le Retour de la télécommande LG, que `web/webos_remote.js`
///   nomme Échap avant Flutter, est dans le jeu `back` (ADR-0110, phase 4).
void main() {
  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> pumpCards(
      WidgetTester tester,
      List<Widget> cards,
    ) =>
        TvNavHarness.pump(
          tester,
          Scaffold(body: Row(children: cards)),
          engine: engine,
          browser: true,
        );

    testWidgets('la flèche droite passe à l\'affiche suivante', (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final harness = await pumpCards(tester, [
        TvFocusable(
          focusNode: first,
          onSelect: () {},
          child: const SizedBox(width: 100, height: 100),
        ),
        TvFocusable(
          focusNode: second,
          onSelect: () {},
          child: const SizedBox(width: 100, height: 100),
        ),
      ]);
      first.requestFocus();
      await tester.pump();

      await harness.press(TraversalDirection.right);
      expect(second.hasFocus, isTrue);
    });

    // Les cartes traitent OK elles-mêmes ; ce qui en dépend, ce sont les
    // contrôles qui ne sont pas des boutons — un interrupteur des réglages.
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.select]) {
      testWidgets('${key.keyLabel} bascule un interrupteur, qui n\'est pas un '
          'bouton', (tester) async {
        var on = false;
        final node = FocusNode();
        addTearDown(node.dispose);
        final harness = await pumpCards(tester, [
          StatefulBuilder(
            builder: (context, setState) => Switch(
              focusNode: node,
              value: on,
              onChanged: (value) => setState(() => on = value),
            ),
          ),
        ]);
        node.requestFocus();
        await tester.pump();

        await harness.select(key: key);
        expect(on, isTrue);
      });
    }

    // Retour de la télécommande LG : Échap, une fois `webos_remote.js` passé.
    // Un seul appui défait un seul écran.
    testWidgets('Retour (Échap) dépile un écran, un seul', (tester) async {
      final harness = await pumpCards(tester, [
        TvFocusable(onSelect: () {}, child: const TvTestTile('Accueil')),
      ]);
      final navigator = harness.navigatorKey.currentState!;
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () {},
            child: const TvTestTile('Fiche'),
          ),
        ),
      ));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () {},
            child: const TvTestTile('Lecteur'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Lecteur'), findsOneWidget);

      await harness.back();
      await tester.pumpAndSettle();

      expect(find.text('Lecteur'), findsNothing);
      expect(find.text('Fiche'), findsOneWidget);
    });
  });

  // Les noms que le moteur web peut donner au Retour d'un navigateur : Échap
  // (réécrit par `webos_remote.js` depuis le `keyCode` 461), `BrowserBack` ou
  // `GoBack` (le nom que lui donne le simulateur de LG, hors LG). Flutter web
  // ne lit que `key` et `code` : un 461 resté « Unidentified » n'est aucune
  // touche connue, d'où la réécriture avant Flutter. `flutter_test` ne sait
  // pas simuler `BrowserBack` ni `GoBack` : le test de bout en bout est celui
  // d'Échap (ci-dessus), ces trois-ci épinglent l'appartenance au jeu `back`
  // que dpad lit pour toutes.
  group('dpad : le jeu de touches du Retour sur un navigateur', () {
    for (final key in [
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.browserBack,
      LogicalKeyboardKey.goBack,
    ]) {
      test('${key.keyLabel.isEmpty ? key.debugName : key.keyLabel} est un Retour',
          () {
        final keys = OnyxDpad.keySetFor(isTv: true, isAndroid: false);
        expect(keys.isBack(key), isTrue);
      });
    }

    // Android envoie son Retour en touche *et* en popRoute (constat C2).
    test('goBack n\'est pas un Retour sur Android', () {
      final keys = OnyxDpad.keySetFor(isTv: true, isAndroid: true);
      expect(keys.isBack(LogicalKeyboardKey.goBack), isFalse);
      expect(keys.isBack(LogicalKeyboardKey.escape), isTrue);
    });
  });
}
