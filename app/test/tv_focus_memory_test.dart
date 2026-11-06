import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_entry.dart';
import 'package:onyx/tv/tv_focus_memory.dart';
import 'package:onyx/tv/tv_mode.dart';

/// La politique de l'app, posée au-dessus de la page comme `main.dart` le fait.
Widget _withPolicy(BuildContext context, Widget? child) =>
    FocusTraversalGroup(policy: TvTraversalPolicy(), child: child!);

/// Deux rangées de cartes l'une sous l'autre, chacune avec sa mémoire.
Widget _rows({required List<FocusNode> top, required List<FocusNode> bottom}) {
  Widget row(List<FocusNode> nodes) => TvFocusMemory(
        child: Row(
          children: [
            for (final node in nodes)
              Padding(
                padding: const EdgeInsets.all(8),
                child: TvFocusable(
                  focusNode: node,
                  onSelect: () {},
                  focusScale: 1.0,
                  child: const SizedBox(width: 80, height: 80),
                ),
              ),
          ],
        ),
      );

  return TvScope(
    isTv: true,
    child: MaterialApp(
      builder: _withPolicy,
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [row(top), row(bottom)],
        ),
      ),
    ),
  );
}

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

void main() {
  setUp(() => TvMode.enabled.value = true);
  tearDown(() => TvMode.enabled.value = false);

  testWidgets('remonter sur une rangée ramène à la carte où l’on était',
      (tester) async {
    final top = _nodes('top', 5);
    final bottom = _nodes('bottom', 5);
    await tester.pumpWidget(_rows(top: top, bottom: bottom));

    top[0].requestFocus();
    await tester.pump();

    // Quatre cartes vers la droite dans la rangée du haut.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(top[4].hasFocus, isTrue);

    // Descendre, revenir tout à gauche dans la rangée du bas, remonter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(bottom[0].hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(top[4].hasFocus, isTrue,
        reason: 'la rangée du haut doit rendre la carte mémorisée, pas celle '
            'qui se trouve géométriquement au-dessus');
  });

  testWidgets(
      'la mémoire route le focus en une passe, sans le poser d’abord ailleurs',
      (tester) async {
    final top = _nodes('top', 5);
    final bottom = _nodes('bottom', 5);
    await tester.pumpWidget(_rows(top: top, bottom: bottom));

    top[0].requestFocus();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(bottom[0].hasFocus, isTrue);

    // Haut mène géométriquement à top[0], pas à top[3] : il ne doit jamais
    // l'avoir, même une frame.
    var landedOnGeometricNeighbour = false;
    void spy() => landedOnGeometricNeighbour |= top[0].hasPrimaryFocus;
    top[0].addListener(spy);
    addTearDown(() => top[0].removeListener(spy));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(top[3].hasFocus, isTrue);
    expect(landedOnGeometricNeighbour, isFalse,
        reason: 'un focus posé puis déplacé coûte deux défilements');
  });

  testWidgets('la première visite laisse le parcours directionnel choisir',
      (tester) async {
    final top = _nodes('top', 3);
    final bottom = _nodes('bottom', 3);
    await tester.pumpWidget(_rows(top: top, bottom: bottom));

    top[2].requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(bottom[2].hasFocus, isTrue);
  });

  testWidgets('hors téléviseur, la mémoire ne redirige rien', (tester) async {
    TvMode.enabled.value = false;
    final top = _nodes('top', 3);
    final bottom = _nodes('bottom', 3);
    await tester.pumpWidget(_rows(top: top, bottom: bottom));

    top[2].requestFocus();
    await tester.pump();
    bottom[0].requestFocus();
    await tester.pump();
    top[0].requestFocus();
    await tester.pump();

    expect(top[0].hasFocus, isTrue);
  });

  testWidgets('une carte retirée de l’arbre est oubliée', (tester) async {
    final key = GlobalKey<TvFocusMemoryState>();
    final outside = FocusNode(debugLabel: 'outside');
    final card = FocusNode(debugLabel: 'card');
    addTearDown(outside.dispose);
    addTearDown(card.dispose);

    Widget build({required bool withCard}) => TvScope(
          isTv: true,
          child: MaterialApp(
            builder: _withPolicy,
            home: Column(
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
            ),
          ),
        );

    await tester.pumpWidget(build(withCard: true));
    card.requestFocus();
    await tester.pump();
    expect(key.currentState!.remembered, same(card));

    outside.requestFocus();
    await tester.pump();
    await tester.pumpWidget(build(withCard: false));

    expect(key.currentState!.remembered, isNull);
  });

  testWidgets(
      'un onglet visité pour la première fois s’ouvre en haut, pas sous '
      'l’élément quitté', (tester) async {
    final header = _nodes('header', 1);
    final content = _nodes('content', 2);
    await tester.pumpWidget(TvScope(
      isTv: true,
      child: MaterialApp(
        builder: _withPolicy,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // La recherche, à droite de l'en-tête.
              Focus(
                focusNode: header[0],
                child: const SizedBox(width: 80, height: 40),
              ),
              Expanded(
                child: TvFocusMemory(
                  entersAtTop: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Le bouton du bandeau, à gauche.
                      Focus(
                        focusNode: content[0],
                        child: const SizedBox(width: 80, height: 40),
                      ),
                      const SizedBox(height: 200),
                      // « Voir tout », à droite, sous la recherche.
                      Align(
                        alignment: Alignment.centerRight,
                        child: Focus(
                          focusNode: content[1],
                          child: const SizedBox(width: 80, height: 40),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    header[0].requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(content[0].hasFocus, isTrue);
  });
  testWidgets(
      'un onglet s’ouvre sur la première affiche, pas sur le bouton posé à '
      'droite du titre', (tester) async {
    final header = _nodes('header', 1);
    final content = _nodes('content', 2);
    await tester.pumpWidget(TvScope(
      isTv: true,
      child: MaterialApp(
        builder: _withPolicy,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // L'onglet « Films », à gauche de l'en-tête.
              Focus(
                focusNode: header[0],
                child: const SizedBox(width: 80, height: 40),
              ),
              Expanded(
                child: TvFocusMemory(
                  entersAtTop: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Le tri « Récents », à droite du titre de la page.
                      Align(
                        alignment: Alignment.centerRight,
                        child: Focus(
                          focusNode: content[0],
                          child: const SizedBox(width: 80, height: 30),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // La première affiche de la grille, à gauche.
                      Focus(
                        focusNode: content[1],
                        child: const SizedBox(width: 80, height: 120),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    header[0].requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(content[1].hasFocus, isTrue);
  });
}
