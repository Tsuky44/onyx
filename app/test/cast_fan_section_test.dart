import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/widgets/global/detail_cast_section.dart';

void main() {
  testWidgets('CastSection ne rend rien si la liste de casting est vide',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CastSection(cast: []),
        ),
      ),
    );

    expect(find.text('Distribution'), findsNothing);
  });

  testWidgets(
      'CastSection affiche l’éventail des acteurs et le cartouche sous l’éventail',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cast = [
      CastMember(
          tmdbId: 101, name: 'Timothée Chalamet', character: 'Paul Atreides'),
      CastMember(tmdbId: 102, name: 'Zendaya Coleman', character: 'Chani'),
      CastMember(
          tmdbId: 103, name: 'Rebecca Ferguson', character: 'Lady Jessica'),
    ];

    CastMember? tappedMember;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CastSection(
            cast: cast,
            onTapMember: (m) => tappedMember = m,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Distribution'), findsOneWidget);
    expect(find.text('Timothée'), findsOneWidget);
    expect(find.text('Zendaya'), findsOneWidget);
    expect(find.text('Rebecca'), findsOneWidget);

    // Par défaut, le premier acteur (Timothée) est sélectionné
    expect(find.text('Paul Atreides'), findsOneWidget);

    // Taper sur la carte de Zendaya la sélectionne
    await tester.tap(find.text('Zendaya'));
    await tester.pumpAndSettle();

    // Le cartouche affiche désormais Chani
    expect(find.text('Chani'), findsOneWidget);
    expect(tappedMember, isNull);

    // Un second appui sur la carte sélectionnée déclenche onTapMember
    await tester.tap(find.text('Zendaya'));
    await tester.pumpAndSettle();

    expect(tappedMember?.tmdbId, 102);
  });

  testWidgets('Les flèches changent la sélection dans l’éventail',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cast = [
      CastMember(tmdbId: 1, name: 'Bryan Cranston', character: 'Walter White'),
      CastMember(tmdbId: 2, name: 'Aaron Paul', character: 'Jesse Pinkman'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CastSection(cast: cast),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Walter White'), findsOneWidget);

    // Bouton suivant
    await tester.tap(find.byTooltip('Acteur suivant'));
    await tester.pumpAndSettle();

    expect(find.text('Jesse Pinkman'), findsOneWidget);

    // Bouton précédent
    await tester.tap(find.byTooltip('Acteur précédent'));
    await tester.pumpAndSettle();

    expect(find.text('Walter White'), findsOneWidget);
  });

  testWidgets(
      'Le survol à la souris soulève la carte (-10px) et le clic sélectionne l’acteur comme dans MediaHub',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cast = [
      CastMember(
          tmdbId: 101, name: 'Timothée Chalamet', character: 'Paul Atreides'),
      CastMember(tmdbId: 102, name: 'Zendaya Coleman', character: 'Chani'),
      CastMember(
          tmdbId: 103, name: 'Rebecca Ferguson', character: 'Lady Jessica'),
    ];

    CastMember? tappedMember;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CastSection(
            cast: cast,
            onTapMember: (m) => tappedMember = m,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Au départ, Timothée Chalamet (Paul Atreides) est sélectionné par défaut
    expect(find.text('Paul Atreides'), findsOneWidget);
    expect(find.text('Chani'), findsNothing);

    // Position verticale initiale de la carte de Zendaya
    final initialTop = tester
        .getTopLeft(find.widgetWithText(AnimatedPositioned, 'Zendaya'))
        .dy;

    // Survol à la souris sur Zendaya
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Zendaya')));
    await tester.pumpAndSettle();

    // La carte s'est soulevée de 10px (feed-back de survol à la MediaHub)
    final hoveredTop = tester
        .getTopLeft(find.widgetWithText(AnimatedPositioned, 'Zendaya'))
        .dy;
    expect(hoveredTop, closeTo(initialTop - 10.0, 0.5));

    // Mais la sélection reste stable : le cartouche n'a pas sauté
    expect(find.text('Paul Atreides'), findsOneWidget);
    expect(find.text('Chani'), findsNothing);
    expect(tappedMember, isNull);

    // Clic pour sélectionner Zendaya (sans passer par les flèches du haut)
    await tester.tap(find.text('Zendaya'));
    await tester.pumpAndSettle();

    // Maintenant Zendaya est sélectionnée et le cartouche affiche Chani
    expect(find.text('Chani'), findsOneWidget);
    expect(tappedMember, isNull);

    // Un second clic sur la carte sélectionnée ouvre la fiche
    await tester.tap(find.text('Zendaya'));
    await tester.pumpAndSettle();

    expect(tappedMember?.tmdbId, 102);
  });
}
