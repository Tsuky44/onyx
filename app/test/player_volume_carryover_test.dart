@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/hooks/use_player_controller.dart';
import 'package:onyx/screens/player/player_playback_preferences.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';

/// Le volume tient d'un épisode à l'autre, tant qu'on reste dans le lecteur.
///
/// La panne : « quand je change d'épisode le son se remet à 100 % ». Chaque
/// épisode ouvre un moteur neuf ; ce qu'il hérite de l'épisode qu'on quitte
/// passe par [PlayerPlaybackPreferences], et le volume n'y était pas.
class _Engine implements PlaybackSession {
  _Engine(this.volume);

  @override
  final double volume;

  @override
  PlaybackTrack? get currentSubtitleTrack => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('l’épisode suivant hérite du volume de celui qu’on quitte', () {
    final controller = PlayerController(session: _Engine(35));
    addTearDown(controller.cancelStreams);

    expect(controller.exportPreferences().volume, 35,
        reason: 'Sans le volume, le moteur neuf repartait à 100 %.');
  });

  test('un son coupé reste coupé à l’épisode suivant', () {
    final controller = PlayerController(session: _Engine(0));
    addTearDown(controller.cancelStreams);

    expect(controller.exportPreferences().volume, 0);
  });

  test('la mémoire de la série ne porte pas de volume', () {
    // Le volume suit la séance, pas la série : un épisode repris un autre
    // jour s'ouvre au niveau du moteur, pas à celui d'une soirée passée.
    expect(
      PlayerPlaybackPreferences(audioIndex: -1, subtitlesOff: true).volume,
      isNull,
    );
  });
}
