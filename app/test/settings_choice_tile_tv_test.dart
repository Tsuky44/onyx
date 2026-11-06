import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/settings/widgets/settings_ui.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';

import 'support/tv_nav_harness.dart';

/// Le défaut que ce fichier verrouille : sur un téléviseur, haut et bas depuis
/// un contrôle aligné à droite (un menu d'heure, un interrupteur) sautaient
/// une rangée de puces alignée à gauche, parce que le parcours directionnel
/// préfère les cibles qui chevauchent horizontalement. « Lecteur Apple TV »
/// (Natif / Onyx) n'était atteignable par aucune flèche.
///
/// Sous dpad, le parcours préfère aussi ce qui est dans le faisceau (constat
/// C9 du plan, « beam ») : c'est encore la porte d'entrée de la rangée
/// (`SettingsChoiceFocus`) qui l'y fait entrer.
void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets('bas depuis un contrôle à droite entre sur la puce choisie',
        (tester) async {
      await _pump(tester, engine);
      await _focusByLabel(tester, 'Haut');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(_focusedChip(tester), 'Onyx');
    });

    testWidgets('haut depuis un contrôle à droite entre sur la puce choisie',
        (tester) async {
      await _pump(tester, engine);
      await _focusByLabel(tester, 'Bas');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(_focusedChip(tester), 'Onyx');
    });

    testWidgets('dans la rangée, gauche et droite passent de puce en puce',
        (tester) async {
      await _pump(tester, engine);
      await _focusByLabel(tester, 'Haut');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedChip(tester), 'Natif');
    });

    testWidgets('quitter la rangée ne fait pas boucler le focus sur elle',
        (tester) async {
      await _pump(tester, engine);
      await _focusByLabel(tester, 'Haut');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusedLabel(), 'Haut');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusedLabel(), 'Bas');
    });
  });
}

enum _Mode { native, onyx }

Future<void> _pump(WidgetTester tester, TvNavEngine engine) async {
  // Un nœud par test : rattaché à l'arbre d'un test précédent, il garde sa
  // place dans l'historique de focus de cet arbre-là.
  _nodes.clear();
  await TvNavHarness.pump(
    tester,
    Scaffold(
      body: Column(
        children: [
          _RightButton('Haut'),
          SettingsChoiceTile<_Mode>(
            title: 'Lecteur Apple TV',
            value: _Mode.onyx,
            options: const [
              (_Mode.native, 'Natif'),
              (_Mode.onyx, 'Onyx'),
            ],
            onChanged: (_) {},
          ),
          _RightButton('Bas'),
        ],
      ),
    ),
    engine: engine,
  );
}

final Map<String, FocusNode> _nodes = {};

/// Un contrôle en bout de ligne, comme le menu d'heure de « Plage horaire ».
class _RightButton extends StatelessWidget {
  const _RightButton(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          focusNode:
              _nodes.putIfAbsent(label, () => FocusNode(debugLabel: label)),
          onPressed: () {},
          child: Text(label),
        ),
      );
}

Future<void> _focusByLabel(WidgetTester tester, String label) async {
  final button = tester.widget<TextButton>(
      find.ancestor(of: find.text(label), matching: find.byType(TextButton)));
  button.focusNode!.requestFocus();
  await tester.pumpAndSettle();
}

String? _focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

String? _focusedChip(WidgetTester tester) {
  ChoiceChip? chip;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    if (e.widget is ChoiceChip) {
      chip = e.widget as ChoiceChip;
      return false;
    }
    return true;
  });
  return (chip?.label as Text?)?.data;
}
