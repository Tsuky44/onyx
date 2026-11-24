import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/hooks/use_player_exit.dart';

/// La sortie du lecteur (`PlayerExit`) : Retour pendant une attente quitte
/// tout de suite, sans rien laisser en vol ; hors attente, la position part
/// d'abord ; et dans tous les cas l'écran ne se dépile qu'une fois.
void main() {
  late List<String> steps;
  late Completer<void> server;
  late Completer<void> engine;

  PlayerExit exit({required bool waiting}) => PlayerExit(
        isWaiting: () => waiting,
        cancelPending: () => steps.add('annule ce qui est en vol'),
        stopEngine: () {
          steps.add('arrête le moteur');
          return engine.future;
        },
        onLeaving: () => steps.add('note le départ'),
        syncProgress: () {
          steps.add('envoie la position');
          return server.future;
        },
        pop: () => steps.add('dépile'),
      );

  setUp(() {
    steps = <String>[];
    server = Completer<void>();
    engine = Completer<void>();
  });

  group('pendant une attente', () {
    test('Retour quitte sans attendre ni le serveur ni le moteur', () {
      // Ni l'un ni l'autre ne répond : c'est le cas d'un lancement qui tarde.
      unawaited(exit(waiting: true).leave());

      expect(steps.last, 'dépile',
          reason: 'l’écran se dépile dans le geste même, pas à la réponse '
              'du serveur');
    });

    test('ce qui est en vol est annulé avant l’arrêt du moteur', () {
      unawaited(exit(waiting: true).leave());

      // Dans l'autre ordre, une session HLS demandée avant le Retour
      // s'ouvrirait derrière l'arrêt et lancerait la lecture : du son sans
      // image.
      expect(steps, [
        'annule ce qui est en vol',
        'arrête le moteur',
        'note le départ',
        'envoie la position',
        'dépile',
      ]);
    });

    test('un second Retour ne dépile pas l’écran d’en dessous', () async {
      final leaving = exit(waiting: true);
      unawaited(leaving.leave());
      unawaited(leaving.leave());
      server.complete();
      await pumpEventQueue();

      expect(steps.where((step) => step == 'dépile'), hasLength(1));
      expect(steps.where((step) => step == 'arrête le moteur'), hasLength(1));
    });
  });

  group('devant un film qui joue', () {
    test('la position part avant que l’écran se dépile', () async {
      unawaited(exit(waiting: false).leave());
      await pumpEventQueue();

      // L'accueil qu'on rejoint relit le serveur : il doit déjà savoir.
      expect(
          steps, ['arrête le moteur', 'note le départ', 'envoie la position']);

      server.complete();
      await pumpEventQueue();
      expect(steps.last, 'dépile');
    });

    test('rien n’est annulé : le contrôleur finit ce qu’il faisait', () async {
      server.complete();
      await exit(waiting: false).leave();

      expect(steps, isNot(contains('annule ce qui est en vol')));
    });

    test('un second Retour, donné pendant l’envoi, ne dépile qu’une fois',
        () async {
      final leaving = exit(waiting: false);
      unawaited(leaving.leave());
      unawaited(leaving.leave());
      server.complete();
      await pumpEventQueue();

      expect(steps.where((step) => step == 'dépile'), hasLength(1));
      expect(steps.where((step) => step == 'envoie la position'), hasLength(1));
    });
  });

  group('un échec ne retient pas la sortie', () {
    for (final waiting in [true, false]) {
      test(waiting ? 'pendant une attente' : 'devant un film qui joue',
          () async {
        final leaving = exit(waiting: waiting).leave();
        server.completeError(StateError('serveur injoignable'));
        engine.completeError(StateError('moteur déjà libéré'));
        await leaving;
        await pumpEventQueue();

        expect(steps.last, 'dépile');
      });
    }
  });

  group('ce qui ne peut pas attendre', () {
    bool cannotWait({
      bool startupDone = true,
      bool hasFirstFrame = true,
      bool awaitingPicture = false,
    }) =>
        playerExitCannotWait(
          startupDone: startupDone,
          hasFirstFrame: hasFirstFrame,
          awaitingPicture: awaitingPicture,
        );

    test('un film qui joue peut attendre sa position', () {
      expect(cannotWait(), isFalse);
    });

    test('un lancement, un changement de qualité, un tampon vide', () {
      expect(cannotWait(hasFirstFrame: false), isTrue);
      expect(cannotWait(awaitingPicture: true), isTrue);
    });

    test('un démarrage au délai dépassé, que plus aucun anneau ne signale',
        () {
      expect(cannotWait(hasFirstFrame: false, awaitingPicture: false), isTrue);
    });

    test('un démarrage inachevé, même sa première image déjà là', () {
      // Le moteur d'Apple l'annonce avant que la lecture ne parte : ce que le
      // démarrage a encore en vol ne doit pas aboutir derrière la sortie.
      expect(cannotWait(startupDone: false, hasFirstFrame: true), isTrue);
    });
  });
}
