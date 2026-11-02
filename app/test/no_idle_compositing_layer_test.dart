@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un filtre de couleur neutre n'est jamais posé (ADR-0101).
///
/// `ColorFiltered` ouvre un calque hors écran même quand son filtre ne change
/// rien. Posé sur chaque ligne d'une liste ou chaque carte d'une grille, il
/// coûte un calque par élément à chaque image d'un défilement. Le filtre se
/// pose seulement là où il a un effet.
void main() {
  test('aucun ColorFilter neutre (BlendMode.dst)', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('BlendMode.dst)')) {
        offenders.add(entity.path.replaceAll('\\', '/'));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Ces fichiers posent un ColorFilter qui ne change rien : '
          'le calque reste. Ne pas envelopper quand il n’y a rien à filtrer. '
          'Voir docs/adr/0101-le-mode-leger-reconnait-les-ordinateurs-modestes.md.',
    );
  });
}
