@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Toute animation qui tourne sans fin demande `AppMotion.reduced` ou
/// `LiteScope` (ADR-0101).
///
/// Une animation sans fin redessine sa zone à chaque image, aussi longtemps
/// que l'écran reste ouvert : c'est la dépense qu'un ordinateur sans
/// processeur graphique paie en continu, même quand l'utilisateur ne regarde
/// rien. Le mode léger les arrête ; un `repeat` qui ne le demande pas
/// reviendrait sur ces machines sans que rien ne le signale.
void main() {
  test('chaque animation sans fin s’arrête en mode léger', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('.repeat(')) continue;
      final asksLite = source.contains('AppMotion.reduced(') ||
          source.contains('LiteScope.of(');
      if (!asksLite) offenders.add(entity.path.replaceAll('\\', '/'));
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Ces fichiers lancent une animation sans fin sans demander '
          'AppMotion.reduced(context) ni LiteScope.of(context) : elle '
          'tournerait en mode léger. Voir '
          'docs/adr/0101-le-mode-leger-reconnait-les-ordinateurs-modestes.md.',
    );
  });
}
