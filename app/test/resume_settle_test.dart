import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/playback/resume_settle.dart';

/// Un flux déjà ouvert à la seconde connue ne reste pas en pause derrière un
/// serveur qui tarde à la confirmer : la lecture part, et la réponse tardive
/// corrige le point tant que personne n'a choisi sa place.
void main() {
  group('le point de départ', () {
    test('la réponse déjà arrivée l’emporte sur le point d’ouverture',
        () async {
      expect(
          await settledResumePoint(Future.value(1200), openedAt: 1190), 1200);
    });

    test('un serveur lent ne retient pas un flux ouvert à un point connu',
        () async {
      final server = Completer<int>();
      expect(await settledResumePoint(server.future, openedAt: 600), 600);
      // La réponse, quand elle vient, n'a plus personne à faire attendre.
      server.complete(900);
    });

    test('sans point connu, la réponse du serveur reste attendue', () async {
      // Partir du début puis sauter ferait entendre les premières secondes.
      final server = Completer<int>();
      int? settled;
      unawaited(settledResumePoint(server.future, openedAt: -1)
          .then((value) => settled = value));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(settled, isNull);
      server.complete(300);
      await Future<void>.delayed(Duration.zero);
      expect(settled, 300);
    });
  });

  group('la réponse tardive', () {
    bool corrects({
      required int startedAt,
      required int server,
      required int position,
    }) =>
        resumeNeedsLateCorrection(
          startedAt: startedAt,
          serverSeconds: server,
          positionSeconds: position,
        );

    test('confirme le point : rien à faire', () {
      expect(corrects(startedAt: 600, server: 600, position: 602), isFalse);
      expect(corrects(startedAt: 600, server: 604, position: 602), isFalse);
    });

    test('contredit le point juste après le départ : la lecture y saute', () {
      expect(corrects(startedAt: 600, server: 1800, position: 603), isTrue);
      expect(corrects(startedAt: 0, server: 1800, position: 2), isTrue);
    });

    test('ne déplace plus quelqu’un qui a choisi sa place', () {
      // Avancé loin, ou revenu en arrière : la télécommande a parlé depuis.
      expect(corrects(startedAt: 600, server: 1800, position: 2400), isFalse);
      expect(corrects(startedAt: 600, server: 1800, position: 120), isFalse);
    });
  });
}
