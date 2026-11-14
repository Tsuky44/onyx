import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_entry_focus.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_mode.dart';

/// `TvEntryFocus` : l'action principale d'une fiche, arrivée après son
/// ouverture, reprend le focus resté faute de mieux sur le bouton retour,
/// sans le prendre à qui s'est déjà déplacé (ADR-0128).
void main() {
  late FocusNode entry;
  late FocusNode back;
  late FocusNode elsewhere;

  setUp(() {
    TvMode.enabled.value = true;
    entry = FocusNode(debugLabel: 'Lecture');
    back = FocusNode(debugLabel: 'Retour');
    elsewhere = FocusNode(debugLabel: 'Saison 1');
  });
  tearDown(() {
    TvMode.enabled.value = false;
    entry.dispose();
    back.dispose();
    elsewhere.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvRegion.sections(
          child: Column(
            children: [
              TvRegion.section(
                id: 'hero',
                child: Column(
                  children: [
                    TextButton(
                      focusNode: back,
                      onPressed: () {},
                      child: const Text('Retour'),
                    ),
                    TextButton(
                      focusNode: entry,
                      onPressed: () {},
                      child: const Text('Lecture'),
                    ),
                  ],
                ),
              ),
              TvRegion.section(
                id: 'seasons',
                child: TextButton(
                  focusNode: elsewhere,
                  onPressed: () {},
                  child: const Text('Saison 1'),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> claim(WidgetTester tester) async {
    TvEntryFocus.claim(entry);
    // L'image dont la fin rend le focus, puis celle qui le pose.
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('le focus n’est nulle part : l’entrée le prend', (tester) async {
    await pumpPage(tester);
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());

    await claim(tester);
    expect(entry.hasPrimaryFocus, isTrue);
  });

  testWidgets(
      'le focus est resté dans la section de l’entrée, sur le bouton '
      'retour : l’entrée le reprend', (tester) async {
    await pumpPage(tester);
    back.requestFocus();
    await tester.pump();

    await claim(tester);
    expect(entry.hasPrimaryFocus, isTrue);
  });

  testWidgets(
      'la télécommande est déjà partie dans une autre section : elle y '
      'reste', (tester) async {
    await pumpPage(tester);
    elsewhere.requestFocus();
    await tester.pump();

    await claim(tester);
    expect(elsewhere.hasPrimaryFocus, isTrue);
  });

  testWidgets('sous un dialogue, il n’y a rien à reprendre', (tester) async {
    await pumpPage(tester);
    showDialog<void>(
      context: tester.element(find.text('Lecture')),
      builder: (_) => AlertDialog(
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {},
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await claim(tester);
    expect(entry.hasFocus, isFalse);
  });

  testWidgets('hors téléviseur, rien ne prend le focus', (tester) async {
    TvMode.enabled.value = false;
    await pumpPage(tester);

    await claim(tester);
    expect(entry.hasFocus, isFalse);
  });
}
