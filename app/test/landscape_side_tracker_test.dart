import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/hooks/use_landscape_side.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  const left = DeviceOrientation.landscapeLeft;
  const right = DeviceOrientation.landscapeRight;

  group('LandscapeSideTracker', () {
    test('la première mesure franche donne le côté tout de suite', () {
      final t = LandscapeSideTracker();
      expect(t.add(9.5, 0.5, 1, ms(0)), left);
      expect(t.side, left);
    });

    test('le haut à droite donne landscapeRight', () {
      final t = LandscapeSideTracker();
      expect(t.add(-9.5, 0.5, 1, ms(0)), right);
    });

    test('un retournement ne bascule qu’après le délai de stabilisation', () {
      final t = LandscapeSideTracker()..add(9.5, 0, 1, ms(0));
      expect(t.add(-9.5, 0, 1, ms(100)), isNull);
      expect(t.add(-9.5, 0, 1, ms(500)), isNull);
      expect(t.add(-9.5, 0, 1, ms(800)), right);
      expect(t.side, right);
    });

    test('un geste bref vers l’autre côté ne retourne pas l’image', () {
      final t = LandscapeSideTracker()..add(9.5, 0, 1, ms(0));
      t.add(-9.5, 0, 1, ms(100));
      // Retour du côté de départ : le compte à rebours repart de zéro.
      t.add(9.5, 0, 1, ms(300));
      expect(t.add(-9.5, 0, 1, ms(900)), isNull);
      expect(t.add(-9.5, 0, 1, ms(1700)), right);
    });

    test('une inclinaison légère ne compte pas comme paysage', () {
      final t = LandscapeSideTracker()..add(9.5, 0, 1, ms(0));
      for (var i = 1; i < 20; i++) {
        expect(t.add(-4, 8, 2, ms(i * 100)), isNull);
      }
      expect(t.side, left);
    });

    test('un téléphone posé à plat garde son côté', () {
      final t = LandscapeSideTracker()..add(9.5, 0, 1, ms(0));
      for (var i = 1; i < 20; i++) {
        expect(t.add(-6.6, 0, 9, ms(i * 100)), isNull);
      }
      expect(t.side, left);
    });

    test('annuler oublie le retournement en cours', () {
      final t = LandscapeSideTracker()..add(9.5, 0, 1, ms(0));
      t.add(-9.5, 0, 1, ms(100));
      t.cancelPending();
      expect(t.add(-9.5, 0, 1, ms(900)), isNull);
    });
  });
}
