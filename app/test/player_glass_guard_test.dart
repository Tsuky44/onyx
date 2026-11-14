@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ce que le lecteur pose sur le film ne floute qu'à un seul endroit
/// (ADR-0130).
///
/// Un flou sur une image qui joue se refait à chaque image du film. Il est
/// admis pour les panneaux ouverts à la demande — un menu, une fenêtre de
/// question, le volet des onglets —, et tous passent par `OnyxGlassPanel`, qui
/// le retire en mode léger et sur les téléviseurs LG et densifie alors son
/// fond. Un flou posé à la main ailleurs oublie l'un des deux : il coûte sur
/// l'appareil qui ne le tient pas, ou il laisse un texte illisible là où il
/// s'efface. Le chrome au repos, lui, n'en a pas du tout (ADR-0048).
const Map<String, String> _allowed = {
  'lib/screens/player/widgets/onyx/onyx_glass_panel.dart':
      'le verre du lecteur : le seul qui floute le film',
  'lib/screens/player/widgets/video_zoom_hint.dart':
      'l’indice de cadrage, une pastille d’une seconde sous le pincement',
  'lib/screens/player/widgets/end_card_chrome.dart':
      'floute une affiche derrière une page de fin, pas le film, et s’en passe '
          'en mode léger',
};

final RegExp _blur =
    RegExp(r'\b(BackdropFilter|GlassBlur)\(|ImageFilter\.blur\(');

void main() {
  test('le lecteur ne floute le film que par OnyxGlassPanel', () {
    final offenders = <String>[];
    for (final entity
        in Directory('lib/screens/player').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!_blur.hasMatch(entity.readAsStringSync())) continue;
      // La liste blanche est écrite en barres obliques ; Windows rend des
      // barres inverses.
      final path = entity.path.replaceAll('\\', '/');
      if (_allowed.containsKey(path)) continue;
      offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Ces fichiers du lecteur posent leur propre flou. Un panneau '
          'sur le film passe par OnyxGlassPanel '
          '(lib/screens/player/widgets/onyx/onyx_glass_panel.dart), qui sait '
          'quand ne pas flouter et garde le texte lisible sans lui. Voir '
          'docs/adr/0130-le-lecteur-a-un-bouton-par-reglage-des-menus-de-verre-'
          'et-un-volet-d-onglets.md.',
    );
  });

  test('la liste d’exceptions ne contient que des fichiers qui floutent', () {
    // Une exception qui survit à la disparition de son flou est une porte
    // laissée ouverte pour le suivant.
    for (final path in _allowed.keys) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path n’existe plus');
      expect(_blur.hasMatch(file.readAsStringSync()), isTrue,
          reason: '$path ne floute plus rien : retire-le de la liste');
    }
  });
}
