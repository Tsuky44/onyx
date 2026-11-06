import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_memory.dart';

import 'support/tv_nav_harness.dart';

/// Une rangée de cartes `<prefix>0` à `<prefix>N`, dans une zone. [entryFirst]
/// marque la première carte comme l'entrée de la zone (constat C8) : seul dpad
/// s'en sert.
Widget _rail(
  String prefix,
  int count, {
  List<FocusNode>? nodes,
  bool entryFirst = false,
  bool autofocusFirst = false,
  bool entersAtTop = false,
}) =>
    TvRegion.rail(
      entersAtTop: entersAtTop,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            TvFocusable(
              focusNode: nodes?[i],
              autofocus: autofocusFirst && i == 0,
              entry: entryFirst && i == 0,
              focusScale: 1.0,
              onSelect: () {},
              child: TvTestTile('$prefix$i', width: 120, height: 80),
            ),
        ],
      ),
    );

/// Deux rangées de cartes l'une sous l'autre, chacune avec sa mémoire, le
/// focus d'abord sur la première carte du haut.
Widget _rows({
  required int top,
  required int bottom,
  List<FocusNode>? topNodes,
  List<FocusNode>? bottomNodes,
  bool entryFirst = false,
}) =>
    Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rail('top', top,
              nodes: topNodes, entryFirst: entryFirst, autofocusFirst: true),
          _rail('bottom', bottom, nodes: bottomNodes, entryFirst: entryFirst),
        ],
      ),
    );

List<FocusNode> _nodes(String prefix, int count) {
  final nodes = [
    for (var i = 0; i < count; i++) FocusNode(debugLabel: '$prefix$i'),
  ];
  addTearDown(() {
    for (final node in nodes) {
      node.dispose();
    }
  });
  return nodes;
}

Future<void> _times(
    TvNavHarness nav, TraversalDirection direction, int n) async {
  for (var i = 0; i < n; i++) {
    await nav.press(direction);
  }
}

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets('remonter sur une rangée ramène à la carte où l’on était',
        (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        _rows(top: 5, bottom: 5),
        engine: engine,
      );
      expect(nav.focusedLabel, 'top0');

      // Quatre cartes vers la droite dans la rangée du haut.
      await _times(nav, TraversalDirection.right, 4);
      expect(nav.focusedLabel, 'top4');

      // Descendre, revenir tout à gauche dans la rangée du bas, remonter.
      await nav.press(TraversalDirection.down);
      await _times(nav, TraversalDirection.left, 4);
      expect(nav.focusedLabel, 'bottom0');

      await nav.press(TraversalDirection.up);

      expect(nav.focusedLabel, 'top4',
          reason: 'la rangée du haut doit rendre la carte mémorisée, pas '
              'celle qui se trouve géométriquement au-dessus');
    });

    testWidgets(
        'la mémoire route le focus en une passe, sans le poser d’abord ailleurs',
        (tester) async {
      final top = _nodes('top', 5);
      final bottom = _nodes('bottom', 5);
      final nav = await TvNavHarness.pump(
        tester,
        _rows(top: 5, bottom: 5, topNodes: top, bottomNodes: bottom),
        engine: engine,
      );

      await _times(nav, TraversalDirection.right, 3);
      await nav.press(TraversalDirection.down);
      await _times(nav, TraversalDirection.left, 3);
      expect(nav.focusedLabel, 'bottom0');

      // Haut mène géométriquement à top[0], pas à top[3] : il ne doit jamais
      // l'avoir, même une frame.
      var landedOnGeometricNeighbour = false;
      void spy() => landedOnGeometricNeighbour |= top[0].hasPrimaryFocus;
      top[0].addListener(spy);
      addTearDown(() => top[0].removeListener(spy));

      await nav.press(TraversalDirection.up);

      expect(nav.focusedLabel, 'top3');
      expect(landedOnGeometricNeighbour, isFalse,
          reason: 'un focus posé puis déplacé coûte deux défilements');
    });

    testWidgets(
        'la première visite, sans carte d’entrée, va à la carte la plus proche',
        (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        _rows(top: 3, bottom: 3),
        engine: engine,
      );

      await _times(nav, TraversalDirection.right, 2);
      await nav.press(TraversalDirection.down);

      expect(nav.focusedLabel, 'bottom2');
    });

    testWidgets('hors téléviseur, la mémoire ne redirige rien', (tester) async {
      final top = _nodes('top', 3);
      final bottom = _nodes('bottom', 3);
      await TvNavHarness.pump(
        tester,
        _rows(top: 3, bottom: 3, topNodes: top, bottomNodes: bottom),
        engine: engine,
        isTv: false,
      );

      top[2].requestFocus();
      await tester.pump();
      bottom[0].requestFocus();
      await tester.pump();
      top[0].requestFocus();
      await tester.pump();

      expect(top[0].hasFocus, isTrue);
    });

    testWidgets('une carte retirée de l’arbre est oubliée', (tester) async {
      Widget page({required bool withCard}) => Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TvFocusable(
                  autofocus: true,
                  focusScale: 1.0,
                  onSelect: () {},
                  child: const TvTestTile('dehors', width: 120, height: 40),
                ),
                TvRegion.rail(
                  child: Row(
                    children: [
                      TvFocusable(
                        focusScale: 1.0,
                        onSelect: () {},
                        child: const TvTestTile('a', width: 120, height: 40),
                      ),
                      if (withCard)
                        TvFocusable(
                          focusScale: 1.0,
                          onSelect: () {},
                          child: const TvTestTile('b', width: 120, height: 40),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );

      final nav =
          await TvNavHarness.pump(tester, page(withCard: true), engine: engine);
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.right);
      expect(nav.focusedLabel, 'b');
      await nav.press(TraversalDirection.up);
      expect(nav.focusedLabel, 'dehors');

      // La carte mémorisée disparaît : revenir dans la rangée ne doit ni
      // échouer ni laisser le focus sur une carte morte.
      await tester.pumpWidget(TvNavHarnessApp(
        engine: engine,
        navigatorKey: nav.navigatorKey,
        profileKey: 'test-profile',
        home: page(withCard: false),
      ));
      await TvNavHarness.settle(tester);
      await nav.press(TraversalDirection.down);

      expect(nav.focusedLabel, 'a');
    });

    testWidgets(
        'un onglet visité pour la première fois s’ouvre en haut, pas sous '
        'l’élément quitté', (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // La recherche, à droite de l'en-tête.
              TvFocusable(
                autofocus: true,
                focusScale: 1.0,
                onSelect: () {},
                child: const TvTestTile('recherche', width: 80, height: 40),
              ),
              Expanded(
                child: TvRegion.list(
                  entersAtTop: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Le bouton du bandeau, à gauche : l'entrée de la zone.
                      TvFocusable(
                        entry: true,
                        focusScale: 1.0,
                        onSelect: () {},
                        child:
                            const TvTestTile('bandeau', width: 80, height: 40),
                      ),
                      const SizedBox(height: 200),
                      // « Voir tout », à droite, sous la recherche.
                      Align(
                        alignment: Alignment.centerRight,
                        child: TvFocusable(
                          focusScale: 1.0,
                          onSelect: () {},
                          child: const TvTestTile('voir tout',
                              width: 80, height: 40),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        engine: engine,
      );
      expect(nav.focusedLabel, 'recherche');

      await nav.press(TraversalDirection.down);

      expect(nav.focusedLabel, 'bandeau');
    });

    testWidgets(
        'un onglet s’ouvre sur la première affiche, pas sur le bouton posé à '
        'droite du titre', (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // L'onglet « Films », à gauche de l'en-tête.
              TvFocusable(
                autofocus: true,
                focusScale: 1.0,
                onSelect: () {},
                child: const TvTestTile('films', width: 80, height: 40),
              ),
              Expanded(
                child: TvRegion.grid(
                  entersAtTop: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Le tri « Récents », à droite du titre de la page.
                      Align(
                        alignment: Alignment.centerRight,
                        child: TvFocusable(
                          focusScale: 1.0,
                          onSelect: () {},
                          child: const TvTestTile('tri', width: 80, height: 30),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // La première affiche de la grille, à gauche : l'entrée.
                      TvFocusable(
                        entry: true,
                        focusScale: 1.0,
                        onSelect: () {},
                        child:
                            const TvTestTile('affiche', width: 80, height: 120),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        engine: engine,
      );
      expect(nav.focusedLabel, 'films');

      await nav.press(TraversalDirection.down);

      expect(nav.focusedLabel, 'affiche');
    });
  });

  group('dpad seulement', () {
    testWidgets(
        'à la première visite, la carte d’entrée prime sur la plus proche (C8)',
        (tester) async {
      // L'ancien système choisit la plus proche (bottom2) ; dpad entre par la
      // carte marquée `entry`, ici la première.
      final nav = await TvNavHarness.pump(
        tester,
        _rows(top: 3, bottom: 3, entryFirst: true),
      );

      await _times(nav, TraversalDirection.right, 2);
      await nav.press(TraversalDirection.down);

      expect(nav.focusedLabel, 'bottom0');
    });

    // « La mémoire d'une rangée ne passe pas d'un profil à l'autre » est déjà
    // gardé par `onyx_dpad_test.dart` (« changer de profil vide la mémoire »,
    // « le vidage atteint la table statique de dpad »).
  });

  group('legacy seulement', () {
    // Ces tests lisent l'état interne de `TvFocusMemory`, qui disparaît avec
    // l'ancien système en phase 8.
    testWidgets('une carte retirée de l’arbre n’est plus mémorisée',
        (tester) async {
      final key = GlobalKey<TvFocusMemoryState>();
      final outside = FocusNode(debugLabel: 'outside');
      final card = FocusNode(debugLabel: 'card');
      addTearDown(outside.dispose);
      addTearDown(card.dispose);

      Widget build({required bool withCard}) => Column(
            children: [
              Focus(focusNode: outside, child: const SizedBox(height: 10)),
              TvFocusMemory(
                key: key,
                child: withCard
                    ? TvFocusable(
                        focusNode: card,
                        child: const SizedBox(width: 10, height: 10),
                      )
                    : const SizedBox(width: 10, height: 10),
              ),
            ],
          );

      final nav = await TvNavHarness.pump(tester, build(withCard: true),
          engine: TvNavEngine.legacy);
      card.requestFocus();
      await tester.pump();
      expect(key.currentState!.remembered, same(card));

      outside.requestFocus();
      await tester.pump();
      await tester.pumpWidget(TvNavHarnessApp(
        engine: TvNavEngine.legacy,
        navigatorKey: nav.navigatorKey,
        profileKey: 'test-profile',
        home: build(withCard: false),
      ));
      await tester.pump();

      expect(key.currentState!.remembered, isNull);
    });
  });
}
