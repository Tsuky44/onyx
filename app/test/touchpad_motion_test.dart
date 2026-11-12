import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/touchpad_motion.dart';

const ms = Duration(milliseconds: 1);

bool _always(TraversalDirection direction) => true;

/// Un glissé de [distance] unités en [duration], échantillonné toutes les
/// 16 ms comme le rapporte le moteur. Rend les pas que le trajet a faits, et
/// l'instant du dernier point.
({List<TraversalDirection> steps, Duration at}) swipe(
  TouchpadMotion motion, {
  required double distance,
  required Duration duration,
  Duration start = Duration.zero,
  bool vertical = false,
  double drift = 0,
  bool Function(TraversalDirection direction)? accelerates = _always,
}) {
  final steps = <TraversalDirection>[];
  motion.add(TouchpadPhase.began, 0, 0, start);
  final frames = (duration.inMilliseconds / 16).ceil();
  var at = start;
  for (var i = 1; i <= frames; i++) {
    at = start + Duration(milliseconds: 16 * i);
    final travelled = distance * i / frames;
    final across = drift * i / frames;
    motion.add(
      TouchpadPhase.moved,
      vertical ? across : travelled,
      vertical ? travelled : across,
      at,
      accelerates: accelerates,
    );
    final step = motion.takeStep(at);
    if (step != null) steps.add(step);
  }
  return (steps: steps, at: at);
}

/// Les délais d'une lancée, jusqu'à ce qu'elle s'arrête.
List<Duration> coastOf(TraversalDirection direction, double speed) {
  final coast = TouchpadCoast((direction: direction, speed: speed, flick: false));
  final delays = <Duration>[];
  for (var delay = coast.next(); delay != null; delay = coast.next()) {
    delays.add(delay);
  }
  return delays;
}

void main() {
  group('le trajet fait les pas', () {
    test('un balayage lent d’un bord à l’autre avance de cinq affiches', () {
      // 2 unités en 1 s : sous la vitesse où le trajet compte double. Le
      // premier pas à 0,22, puis un tous les 0,40.
      final result =
          swipe(TouchpadMotion(), distance: 2, duration: ms * 1000);
      expect(result.steps, List.filled(5, TraversalDirection.right));
    });

    test('un petit trajet ne fait aucun pas, le suivant en fait un', () {
      final motion = TouchpadMotion();
      expect(swipe(motion, distance: 0.2, duration: ms * 400).steps, isEmpty);
      expect(
        swipe(motion, distance: 0.3, duration: ms * 400).steps,
        [TraversalDirection.right],
      );
    });

    test('le même trajet parcouru vite vaut plus de pas', () {
      final slow = swipe(TouchpadMotion(), distance: 1.6, duration: ms * 1000);
      final fast = swipe(TouchpadMotion(), distance: 1.6, duration: ms * 240);
      expect(fast.steps.length, greaterThan(slow.steps.length));
    });

    test('hors de ce qui défile, la vitesse ne change rien au trajet', () {
      // Une barre de boutons : sauter trois commandes d'un geste serait se
      // perdre. Le geste vif n'y fait que les pas que son temps lui laisse.
      final slow = swipe(
        TouchpadMotion(),
        distance: 1.6,
        duration: ms * 1000,
        accelerates: (_) => false,
      );
      final fast = swipe(
        TouchpadMotion(),
        distance: 1.6,
        duration: ms * 240,
        accelerates: (_) => false,
      );
      expect(fast.steps.length, lessThanOrEqualTo(slow.steps.length));
    });

    test('revenir en arrière défait les pas dans l’autre sens', () {
      final motion = TouchpadMotion();
      final steps = <TraversalDirection>[];
      motion.add(TouchpadPhase.began, 0, 0, Duration.zero);
      var at = Duration.zero;
      for (final x in <double>[0.3, 0.6, 0.9, 0.6, 0.3, 0.0, -0.3]) {
        at += ms * 100;
        motion.add(TouchpadPhase.moved, x, 0, at);
        final step = motion.takeStep(at);
        if (step != null) steps.add(step);
      }
      expect(steps.take(2), everyElement(TraversalDirection.right));
      expect(steps.last, TraversalDirection.left);
    });

    test('deux pas ne se suivent jamais à moins de 40 ms', () {
      final motion = TouchpadMotion();
      final times = <Duration>[];
      motion.add(TouchpadPhase.began, -1, 0, Duration.zero);
      for (var i = 1; i <= 12; i++) {
        final at = ms * (8 * i);
        motion.add(TouchpadPhase.moved, -1 + 0.16 * i, 0, at,
            accelerates: _always);
        if (motion.takeStep(at) != null) times.add(at);
      }
      expect(times.length, greaterThan(1));
      for (var i = 1; i < times.length; i++) {
        expect(times[i] - times[i - 1],
            greaterThanOrEqualTo(TouchpadAxisTuning.horizontal.minStepInterval));
      }
    });
  });

  group('la verticale', () {
    test('un balayage lent d’un bord à l’autre descend de quatre lignes', () {
      final result = swipe(TouchpadMotion(),
          distance: 2, duration: ms * 1000, vertical: true);
      expect(result.steps, List.filled(4, TraversalDirection.down));
    });

    test('un geste vif ne saute pas de rangées entières', () {
      // À l'essai (ADR-0039), une verticale accélérée traversait l'accueil.
      final result = swipe(TouchpadMotion(),
          distance: 1.2, duration: ms * 128, vertical: true);
      expect(result.steps.length, lessThanOrEqualTo(3));
      expect(coastOf(TraversalDirection.down, 30).length, lessThanOrEqualTo(2));
    });

    test('un geste horizontal un peu de travers ne change pas de rangée', () {
      final result = swipe(TouchpadMotion(),
          distance: 2, duration: ms * 1000, drift: 0.5);
      expect(result.steps, everyElement(TraversalDirection.right));
    });
  });

  group('les flèches du moteur', () {
    test('pendant un glissé, la flèche qui arrive est celle du geste', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 0.6, duration: ms * 200);
      expect(motion.ownsArrowAt(result.at), isTrue);
    });

    test('un doigt posé qui ne glisse pas laisse la flèche au pavé', () {
      // Le clic sur l'anneau de la télécommande : le doigt touche la
      // surface, il ne la parcourt pas.
      final motion = TouchpadMotion();
      motion.add(TouchpadPhase.began, 0.8, 0, Duration.zero);
      motion.add(TouchpadPhase.moved, 0.81, 0, ms * 16);
      motion.add(TouchpadPhase.moved, 0.82, 0, ms * 32);
      expect(motion.ownsArrowAt(ms * 40), isFalse);
    });

    test('un doigt arrêté depuis 150 ms ne glisse plus', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 0.6, duration: ms * 200);
      expect(motion.ownsArrowAt(result.at + ms * 200), isFalse);
    });

    test('la flèche tirée juste après le lâcher est encore celle du geste',
        () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 0.6, duration: ms * 200);
      motion.add(TouchpadPhase.ended, 0.6, 0, result.at);
      expect(motion.ownsArrowAt(result.at + ms * 80, grace: ms * 120), isTrue);
      expect(motion.ownsArrowAt(result.at + ms * 200, grace: ms * 120), isFalse);
    });

    test('un clic n’est jamais un glissé', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 0.6, duration: ms * 200);
      motion.add(TouchpadPhase.clickDown, 0.6, 0, result.at);
      expect(motion.ownsArrowAt(result.at), isFalse);
      expect(motion.takeStep(result.at + ms * 100), isNull);
      expect(motion.add(TouchpadPhase.ended, 0.6, 0, result.at), isNull);
    });

    test('sans aucun geste, rien n’est retenu', () {
      expect(TouchpadMotion().ownsArrowAt(Duration.zero, grace: ms * 120),
          isFalse);
    });
  });

  group('le lâcher', () {
    test('un geste posé s’arrête où le doigt s’arrête', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 1.2, duration: ms * 800);
      expect(motion.add(TouchpadPhase.ended, 1.2, 0, result.at), isNull);
    });

    test('un geste lâché vif rend sa direction et sa vitesse', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 1.6, duration: ms * 160);
      final release = motion.add(TouchpadPhase.ended, 1.6, 0, result.at)!;
      expect(release.direction, TraversalDirection.right);
      expect(release.speed, closeTo(10, 0.5));
      expect(release.flick, isFalse);
    });

    test('un coup de pouce trop court pour un pas en vaut quand même un', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 0.18, duration: ms * 64);
      expect(result.steps, isEmpty);
      final release = motion.add(TouchpadPhase.ended, 0.18, 0, result.at)!;
      expect(release.flick, isTrue);
      expect(release.direction, TraversalDirection.right);
    });

    test('un doigt qui s’arrête avant de se lever ne lance rien', () {
      final motion = TouchpadMotion();
      final result = swipe(motion, distance: 1.6, duration: ms * 160);
      expect(
        motion.add(TouchpadPhase.ended, 1.6, 0, result.at + ms * 300),
        isNull,
      );
    });
  });

  group('la lancée', () {
    test('ralentit : chaque pas vient plus tard que le précédent', () {
      final delays = coastOf(TraversalDirection.right, 8);
      expect(delays.length, greaterThan(3));
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThanOrEqualTo(delays[i - 1]));
      }
    });

    test('va plus loin quand le doigt est parti plus vite', () {
      final gentle = coastOf(TraversalDirection.right, 5).length;
      final brisk = coastOf(TraversalDirection.right, 9).length;
      final hard = coastOf(TraversalDirection.right, 16).length;
      expect(gentle, greaterThan(0));
      expect(brisk, greaterThan(gentle));
      expect(hard, greaterThan(brisk));
    });

    test('ne dépasse jamais son plafond', () {
      expect(
        coastOf(TraversalDirection.right, 200).length,
        TouchpadAxisTuning.horizontal.maxCoastSteps,
      );
    });

    test('sous la vitesse de lancée, la liste ne bouge pas', () {
      expect(coastOf(TraversalDirection.right, 3), isEmpty);
      expect(coastOf(TraversalDirection.down, 5), isEmpty);
    });

    test('ne fait jamais deux pas à moins de 40 ms', () {
      for (final delay in coastOf(TraversalDirection.left, 40)) {
        expect(delay,
            greaterThanOrEqualTo(TouchpadAxisTuning.horizontal.minStepInterval));
      }
      for (final delay in coastOf(TraversalDirection.down, 40)) {
        expect(delay,
            greaterThanOrEqualTo(TouchpadAxisTuning.vertical.minStepInterval));
      }
    });
  });
}
