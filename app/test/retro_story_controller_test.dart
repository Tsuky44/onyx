import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/screens/retro/hooks/retro_story_controller.dart';

void main() {
  const slide = Duration(seconds: 10);
  RetroStoryController story() =>
      RetroStoryController(count: 3, slideDuration: slide);

  test('la story avance seule d’un écran à la fin de sa barre', () {
    final s = story();
    s.tick(const Duration(seconds: 4));
    expect(s.index, 0);
    expect(s.progress, closeTo(0.4, 1e-9));
    s.tick(const Duration(seconds: 6));
    expect((s.index, s.progress), (1, 0.0));
  });

  test('maintenir le doigt arrête la story, le relâcher la reprend', () {
    final s = story()..hold();
    s.tick(const Duration(seconds: 5));
    expect(s.paused, isTrue);
    expect(s.progress, 0);
    s.release();
    s.tick(const Duration(seconds: 5));
    expect(s.progress, closeTo(0.5, 1e-9));
  });

  test('la pause du bouton tient même après avoir relâché le doigt', () {
    final s = story()
      ..togglePause()
      ..hold()
      ..release();
    s.tick(const Duration(seconds: 5));
    expect(s.paused, isTrue);
    expect(s.progress, 0);
  });

  test('le dernier écran attend au bout de sa barre, sans boucler', () {
    final s = story()..goTo(2);
    s.tick(const Duration(seconds: 30));
    expect((s.index, s.progress, s.finished), (2, 1.0, true));
    s.next();
    expect(s.index, 2);
  });

  test('l’écran s’ouvre depuis le point touché, sinon depuis un bord', () {
    final s = story()..next(from: const Offset(0.3, 0.7));
    expect(s.origin, const Offset(0.3, 0.7));
    s.previous();
    expect(s.origin.dx, lessThan(0.5), reason: 'reculer part de la gauche');
    s.tick(const Duration(seconds: 10));
    expect(s.origin.dx, greaterThan(0.5), reason: 'avancer seul part de la droite');
  });

  test('« précédent » au premier écran le reprend du début', () {
    final s = story();
    s.tick(const Duration(seconds: 5));
    s.previous();
    expect((s.index, s.progress), (0, 0.0));
    s
      ..next()
      ..next()
      ..previous();
    expect(s.index, 1);
  });
}
