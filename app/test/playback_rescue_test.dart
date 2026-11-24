import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/screens/player/playback/playback_rescue.dart';

/// Une minuterie que le test déclenche lui-même.
class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// Un lecteur réduit à ce que [PlaybackRescue] en lit.
class _Player {
  bool waiting = false;
  bool busy = false;
  bool alive = true;
  int position = 0;

  /// Les échelons qui ne s'appliquent pas (rendent faux) ou qui échouent.
  final Set<RescueStep> skipped = {};
  final Set<RescueStep> failing = {};
  final List<(RescueStep, int)> ran = [];
  final List<_ManualTimer> timers = [];

  late final PlaybackRescue rescue = PlaybackRescue(
    waiting: () => waiting,
    busy: () => busy,
    positionSeconds: () => position,
    alive: () => alive,
    run: (step, seconds) async {
      ran.add((step, seconds));
      if (failing.contains(step)) throw StateError('serveur muet');
      return !skipped.contains(step);
    },
    schedule: (_, callback) {
      final timer = _ManualTimer(callback);
      timers.add(timer);
      return timer;
    },
  );

  /// Le délai en cours arrive à son terme.
  Future<void> elapse() async {
    timers.lastWhere((timer) => timer.isActive).fire();
    await pumpEventQueue();
  }

  bool get armed => timers.any((timer) => timer.isActive);
}

/// Vu sur une Apple TV : un retour en arrière figeait l'image, l'anneau
/// tournait sans fin, puis l'écran passait au noir.
void main() {
  test('une recherche qui se pose ne déclenche rien', () async {
    final player = _Player();
    player.rescue.noteSeek(600);
    player
      ..waiting = false
      ..position = 612;
    await player.elapse();
    expect(player.ran, isEmpty);
    expect(player.armed, isFalse);
  });

  test('une recherche encore en attente sur sa cible rouvre le flux là',
      () async {
    final player = _Player()
      ..waiting = true
      ..position = 600;
    player.rescue.noteSeek(600);
    await player.elapse();
    expect(player.ran, [(RescueStep.reopen, 600)]);
    expect(player.armed, isTrue, reason: 'on vérifie que l’image revient');
  });

  test('en pause sur la cible, sans tampon, ce n’est pas une lecture figée',
      () async {
    final player = _Player()..position = 600;
    player.rescue.noteSeek(600);
    await player.elapse();
    expect(player.ran, isEmpty);
  });

  test('toujours figée après la réouverture : transcodage, puis l’écran '
      'd’échec', () async {
    final player = _Player()
      ..waiting = true
      ..position = 600;
    player.rescue.noteSeek(600);
    await player.elapse();
    await player.elapse();
    await player.elapse();
    expect(player.ran, [
      (RescueStep.reopen, 600),
      (RescueStep.transcode, 600),
      (RescueStep.giveUp, 600),
    ]);
    expect(player.armed, isFalse, reason: 'tout a été essayé');
  });

  test('une lecture repartie remet l’échelle à zéro', () async {
    final player = _Player()
      ..waiting = true
      ..position = 600;
    player.rescue.noteSeek(600);
    await player.elapse();
    player
      ..waiting = false
      ..position = 640;
    await player.elapse();
    expect(player.rescue.nextStep, RescueStep.reopen);

    player
      ..waiting = true
      ..position = 100;
    player.rescue.noteSeek(100);
    await player.elapse();
    expect(player.ran.last, (RescueStep.reopen, 100));
  });

  test('un échelon qui ne s’applique pas ou qui échoue laisse la place au '
      'suivant', () async {
    final player = _Player()
      ..waiting = true
      ..position = 600
      ..failing.add(RescueStep.reopen)
      ..skipped.add(RescueStep.transcode);
    player.rescue.noteSeek(600);
    await player.elapse();
    expect(player.ran.map((entry) => entry.$1), RescueStep.values);
  });

  test('insister sur une lecture figée ne repousse pas le délai', () async {
    final player = _Player()
      ..waiting = true
      ..position = 600;
    player.rescue.noteSeek(600);
    player.position = 590;
    player.rescue.noteSeek(590);
    expect(player.timers, hasLength(1));
    await player.elapse();
    expect(player.ran, [(RescueStep.reopen, 590)]);
  });

  test('une ouverture en cours est laissée finir avant de juger', () async {
    final player = _Player()
      ..waiting = true
      ..busy = true
      ..position = 600;
    player.rescue.noteSeek(600);
    await player.elapse();
    expect(player.ran, isEmpty);
    expect(player.armed, isTrue);
    player.busy = false;
    await player.elapse();
    expect(player.ran, [(RescueStep.reopen, 600)]);
  });

  test('une panne annoncée par le moteur rouvre tout de suite', () async {
    final player = _Player()..position = 1200;
    player.rescue.noteFailure(1200);
    await pumpEventQueue();
    expect(player.ran, [(RescueStep.reopen, 1200)]);
  });

  test('un fichier que l’appareil ne décode pas part droit au transcodage',
      () async {
    final player = _Player()..position = 1200;
    player.rescue.noteFailure(1200, undecodable: true);
    await pumpEventQueue();
    expect(player.ran, [(RescueStep.transcode, 1200)]);
  });

  test('un lecteur démonté ne rattrape plus rien', () async {
    final player = _Player()
      ..waiting = true
      ..position = 600;
    player.rescue.noteSeek(600);
    player.alive = false;
    await player.elapse();
    expect(player.ran, isEmpty);

    final other = _Player()..waiting = true;
    other.rescue.noteSeek(0);
    other.rescue.dispose();
    expect(other.armed, isFalse);
  });
}
