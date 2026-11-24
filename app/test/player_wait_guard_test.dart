@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ce que l'écran du lecteur doit à son attente, et qu'aucun test ne peut lui
/// faire jouer : `PlayerScreen` ne se monte pas sans moteur ni serveur.
///
/// Les règles elles-mêmes sont éprouvées là où elles vivent (`PlayerExit`
/// dans `player_exit_test.dart`, l'anneau dans le sien). Ce fichier vérifie
/// seulement que l'écran passe bien par elles : c'est ce qu'une fusion défait
/// sans rien casser d'autre (ADR du 2026-11-23).
const _screen = 'lib/screens/player/player_screen.dart';
const _flow = 'lib/screens/player/player_screen_flow.dart';

void main() {
  test('l’écran ne pose l’anneau d’attente qu’une fois', () {
    final posed =
        '_buildLoadingRing(isTv)'.allMatches(File(_screen).readAsStringSync());

    expect(
      posed,
      hasLength(1),
      reason: 'Posé une fois pour la première image et une fois pour le '
          'tampon, l’anneau était là deux fois au démarrage, où le moteur se '
          'dit aussi « en tampon » : deux têtes décalées qui tournent l’une '
          'sur l’autre. Une seule couche, sous `_awaitingPicture` ($_screen).',
    );
  });

  test('quitter le lecteur passe par PlayerExit', () {
    final source = File(_flow).readAsStringSync();

    expect(
      source,
      contains('Future<void> _leavePlayer() => _exit.leave();'),
      reason: 'Hors de PlayerExit, la sortie attend de nouveau la réponse du '
          'serveur avant de dépiler, et un second Retour dépile deux écrans '
          '($_flow).',
    );
    expect(
      source,
      contains('cancelPending: _playerController.cancelStreams'),
      reason: 'Sans cette annulation, ce qui est en vol aboutit après le '
          'Retour : une session HLS s’ouvre et joue, du son sans image '
          '($_flow).',
    );
  });
}
