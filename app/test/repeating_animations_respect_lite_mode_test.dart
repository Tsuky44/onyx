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

/// Les animations sans fin qui continuent en mode léger, et pourquoi. Chacune
/// doit s'y alléger autrement ([_lightens]) : la liste n'excuse pas l'oubli.
const Map<String, String> _keepsMoving = {
  'lib/screens/player/widgets/onyx/onyx_loading_ring.dart':
      'l’attente du lecteur : immobile, elle se lit comme un plantage (Apple '
          'TV HD). Elle perd son flou au lieu de s’arrêter, ne dure que le '
          'temps d’attendre, et ne repeint que ses 52 points '
          '(docs/adr/2026-11-23-fytroz-l-attente-du-lecteur-vit-et-s-annule.md)',
};

/// Ce par quoi une exception de [_keepsMoving] demande le mode léger.
const String _lightens = 'glassBlurs(';

void main() {
  test('chaque animation sans fin s’arrête en mode léger', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('.repeat(')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final asksLite = source.contains('AppMotion.reduced(') ||
          source.contains('LiteScope.of(') ||
          (_keepsMoving.containsKey(path) && source.contains(_lightens));
      if (!asksLite) offenders.add(path);
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

  test('la liste des exceptions ne contient que des animations sans fin', () {
    // Une exception qui survit à son animation est une porte laissée ouverte
    // pour la suivante.
    for (final path in _keepsMoving.keys) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path n’existe plus');
      expect(file.readAsStringSync(), contains('.repeat('),
          reason: '$path n’a plus d’animation sans fin : retirez-le de la '
              'liste.');
    }
  });
}
