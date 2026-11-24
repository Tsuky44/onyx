@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/hooks/use_player_controller.dart';
import 'package:onyx/screens/player/playback/playback_intent.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';

/// L'intention de lecture est retenue, jamais relue du moteur.
///
/// La panne, sur une Apple TV : « des fois quand je mets Play ou que je change
/// la qualité, ça reste bloqué en mode pause ». AetherEngine ne dit « je lis »
/// que lorsque l'image défile ; pendant un chargement, une recherche, une
/// remise en tampon ou une bascule de qualité, il rapporte `isPlaying = false`.
/// Le lecteur recopiait ce rapport, y lisait une pause, et en tirait le sens
/// de l'appui suivant comme l'état dans lequel rouvrir une source.

/// Un moteur qui rapporte ce qu'on lui dit de rapporter, et note ce qu'on
/// lui demande.
class _Engine implements PlaybackSession {
  @override
  bool isPlaying = false;

  @override
  bool isBuffering = false;

  final List<String> asked = [];

  @override
  Future<void> play() async => asked.add('play');

  @override
  Future<void> pause() async => asked.add('pause');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Le moteur charge, cherche ou remplit son tampon : il ne lit pas, et
/// personne ne l'a mis en pause.
void _wait(_Engine engine) {
  engine
    ..isPlaying = false
    ..isBuffering = true;
}

void main() {
  group('un appui sur lecture/pause', () {
    test('pendant que le moteur attend, inverse la demande, pas son rapport',
        () {
      // Le moteur dit « je ne lis pas » : il charge. Lire ce rapport comme une
      // pause envoyait « lecture » à qui voulait mettre en pause, puis
      // « pause » à l'appui suivant, sur un film qui n'avait jamais démarré.
      final intent = PlaybackIntent();

      expect(intent.toggle(EngineActivity.waiting), isFalse,
          reason: 'On voulait lire : l’appui met en pause, même si le moteur '
              'ne lisait pas encore.');
      expect(intent.wantsPlay, isFalse);
      expect(intent.toggle(EngineActivity.waiting), isTrue,
          reason: 'L’appui suivant relance, pendant la même attente.');
    });

    test('devant un moteur stable, fait ce que l’écran montre', () {
      final intent = PlaybackIntent();
      expect(intent.toggle(EngineActivity.playing), isFalse);
      expect(intent.toggle(EngineActivity.atRest), isTrue);

      // Une lecture que le système a arrêtée sans prévenir (appel, sortie
      // audio perdue) : l'image est figée, l'appui relance au lieu de
      // demander une pause que personne ne verrait.
      expect(intent.wantsPlay, isTrue);
      expect(intent.toggle(EngineActivity.atRest), isTrue);
    });

    test('lit l’activité du moteur sans y lire une pause', () {
      final engine = _Engine();
      expect(EngineActivity.of(engine), EngineActivity.atRest);
      _wait(engine);
      expect(EngineActivity.of(engine), EngineActivity.waiting);
      engine.isPlaying = true;
      expect(EngineActivity.of(engine), EngineActivity.playing);
    });
  });

  group('le contrôleur', () {
    test('garde « lire » pendant une bascule de qualité', () {
      final engine = _Engine()..isPlaying = true;
      final controller = PlayerController(session: engine);
      addTearDown(controller.cancelStreams);

      // La bascule rouvre la source : le moteur passe en chargement et
      // rapporte qu'il ne lit plus.
      _wait(engine);

      expect(controller.wantsPlay, isTrue,
          reason: 'Un chargement n’est pas une pause : la source doit se '
              'rouvrir en lecture, et le bouton montrer « pause ».');
    });

    test('met en pause sur un appui pendant une remise en tampon', () {
      final engine = _Engine();
      final controller = PlayerController(session: engine);
      addTearDown(controller.cancelStreams);
      _wait(engine);

      controller.togglePlayPause();

      expect(engine.asked, ['pause'],
          reason: 'L’appui partait en « lecture » : le film reprenait seul '
              'à la fin du chargement, derrière qui voulait l’arrêter.');
      expect(controller.wantsPlay, isFalse);

      controller.togglePlayPause();
      expect(engine.asked, ['pause', 'play']);
      expect(controller.wantsPlay, isTrue);
    });

    test('relance en un appui un moteur resté au repos', () {
      // Après un appui sur lecture, le moteur n'a pas bougé (session démontée
      // par l'Apple TV en arrière-plan, pause du système). L'appui suivant
      // partait en « pause » et le film restait bloqué.
      final engine = _Engine();
      final controller = PlayerController(session: engine, wantsPlay: false);
      addTearDown(controller.cancelStreams);

      controller.togglePlayPause();
      controller.togglePlayPause();

      expect(engine.asked, ['play', 'play']);
      expect(controller.wantsPlay, isTrue);
    });

    test('porte une pause voulue même quand le moteur ne lit pas', () {
      // La minuterie de veille, un autre appareil ou la séance partagée
      // demandent la pause pendant un chargement : sans l'envoyer, le moteur
      // repartait seul une fois chargé.
      final engine = _Engine();
      final controller = PlayerController(session: engine);
      addTearDown(controller.cancelStreams);
      _wait(engine);

      controller.pause();

      expect(engine.asked, ['pause']);
      expect(controller.wantsPlay, isFalse);
    });

    test('s’ouvre en pause quand on le lui demande', () {
      final controller =
          PlayerController(session: _Engine(), wantsPlay: false);
      addTearDown(controller.cancelStreams);
      expect(controller.wantsPlay, isFalse);
    });
  });

  group('garde : personne ne relit l’intention du moteur', () {
    const hooks = 'lib/screens/player/hooks';

    test('une source se rouvre dans l’état demandé, jamais en lecture forcée',
        () {
      // Changement de qualité, recherche hors de la session HLS, reprise
      // après une coupure : rouvrir avec `play: true` relançait un film en
      // pause, et rouvrir sur ce que le moteur rapportait le laissait en
      // pause derrière un chargement.
      final forced = <String>[];
      for (final file in Directory(hooks).listSync().whereType<File>()) {
        final source = file.readAsStringSync();
        final opens =
            RegExp(r'session\.open\((.*?)\);', dotAll: true).allMatches(source);
        for (final open in opens) {
          if (open.group(1)!.contains('play: true')) forced.add(file.path);
        }
      }
      expect(forced, isEmpty,
          reason: 'Ouvrir avec `play: wantsPlay` : l’intention retenue par '
              '`PlaybackIntent`, pas une lecture d’office.');
    });

    test('l’écran et ses hooks décident sur `wantsPlay`, pas sur `isPlaying`',
        () {
      // `PlayerController.isPlaying` recopie le moteur : faux pendant tout
      // chargement. Le lire pour décider (pause voulue, reprise, séance
      // partagée, bouton) est la panne que cette intention retenue corrige.
      final readers = <String>[];
      final files = [
        ...Directory('lib/screens/player')
            .listSync()
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.startsWith('player_screen')),
        ...Directory(hooks).listSync().whereType<File>().where((f) {
          final name = f.uri.pathSegments.last;
          return name.startsWith('use_') && name != 'use_player_controller.dart';
        }),
      ];
      expect(files, isNotEmpty);
      final reads = RegExp(r'[cC]ontroller\.isPlaying\b');
      for (final file in files) {
        if (reads.hasMatch(file.readAsStringSync())) readers.add(file.path);
      }
      expect(readers, isEmpty,
          reason: 'Lire `wantsPlay`, et demander par `play()`, `pause()` ou '
              '`togglePlayPause()` du contrôleur.');
    });
  });
}
