@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un lecteur ne se remplace par un autre lecteur qu'à un endroit.
///
/// L'écran de lecture rend l'orientation, les barres du système et la
/// luminosité en partant — sauf quand c'est un autre lecteur qui prend sa
/// place : celui-là est déjà construit, paysage demandé, quand l'ancien est
/// détruit, et les lui reprendre le laisse en portrait. Trois chemins
/// remplacent un lecteur par un lecteur (l'épisode suivant, le relais par un
/// autre serveur, « Réessayer ») ; le troisième l'avait oublié, et un film
/// relancé après un démarrage raté jouait en portrait sur iPhone (1.1.52).
///
/// La règle tient donc dans une fonction, `_replaceWithPlayer`, et ce test
/// refuse qu'on la contourne.
const _seam = 'lib/screens/player/player_screen_flow.dart';

void main() {
  test('dans le lecteur, seul _replaceWithPlayer remplace l’écran', () {
    final offenders = <String>[];

    for (final entity
        in Directory('lib/screens/player').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Windows rend des barres inverses.
      final path = entity.path.replaceAll('\\', '/');
      final source = entity.readAsStringSync();
      final calls = '.pushReplacement('.allMatches(source).length;
      final allowed = path == _seam ? 1 : 0;
      if (calls > allowed) offenders.add('$path : $calls appel(s)');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Un lecteur remplacé par un lecteur hors de _replaceWithPlayer '
          'rend l’orientation et les barres du système à l’écran qui vient '
          'de les demander : le film suivant joue en portrait.\n\n'
          '${offenders.join('\n')}\n\n'
          'Passer par _replaceWithPlayer ($_seam).',
    );
  });

  test('_replaceWithPlayer annonce la relève avant de naviguer', () {
    final source = File(_seam).readAsStringSync();
    final body = RegExp(
      r'void _replaceWithPlayer\(PlayerScreen next\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(source)?.group(1);

    expect(body, isNotNull,
        reason: '_replaceWithPlayer a disparu de $_seam : les trois chemins '
            'qui remplacent un lecteur par un lecteur n’ont plus de règle '
            'commune.');
    final announced = body!.indexOf('_isEpisodeTransition = true');
    final pushed = body.indexOf('.pushReplacement(');
    expect(announced, isNonNegative,
        reason: 'Sans ce drapeau, `dispose` rend l’orientation au système '
            'alors que le lecteur suivant vient de la prendre.');
    expect(pushed, greaterThan(announced),
        reason: 'Le drapeau se pose avant la navigation : `dispose` le lit.');
  });
}
