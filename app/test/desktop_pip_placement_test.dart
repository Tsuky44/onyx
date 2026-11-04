import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/services/desktop_pip_placement.dart';

void main() {
  const screen = Rect.fromLTWH(0, 0, 1920, 1040);

  group('la petite fenêtre du film', () {
    test('se cale en bas à droite, à la marge du bord', () {
      final rect =
          DesktopPipPlacement.cornerRect(screen: screen, aspect: 16 / 9);
      expect(rect.right, screen.right - DesktopPipPlacement.margin);
      expect(rect.bottom, screen.bottom - DesktopPipPlacement.margin);
    });

    test('garde le rapport du film', () {
      for (final aspect in [16 / 9, 4 / 3, 2.39, 1.0]) {
        final rect =
            DesktopPipPlacement.cornerRect(screen: screen, aspect: aspect);
        expect(rect.width / rect.height, closeTo(aspect, 0.001));
      }
    });

    test('un film vertical reste dans la hauteur maximale', () {
      final rect = DesktopPipPlacement.cornerRect(screen: screen, aspect: 0.56);
      expect(rect.height, lessThanOrEqualTo(DesktopPipPlacement.maxHeight));
      expect(rect.width / rect.height, closeTo(0.56, 0.001));
    });

    test('un rapport inconnu retombe sur 16:9', () {
      expect(DesktopPipPlacement.sanitizeAspect(0), 16 / 9);
      expect(DesktopPipPlacement.sanitizeAspect(double.nan), 16 / 9);
      expect(DesktopPipPlacement.sanitizeAspect(-1), 16 / 9);
    });

    test('suit l’écran visible d’un second moniteur', () {
      const second = Rect.fromLTWH(1920, 0, 1280, 720);
      final rect =
          DesktopPipPlacement.cornerRect(screen: second, aspect: 16 / 9);
      expect(second.contains(rect.topLeft), isTrue);
      expect(rect.right, second.right - DesktopPipPlacement.margin);
    });

    test(
        'un écran minuscule contient la fenêtre au lieu de la laisser déborder',
        () {
      const tiny = Rect.fromLTWH(0, 0, 300, 200);
      final rect = DesktopPipPlacement.cornerRect(screen: tiny, aspect: 16 / 9);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(tiny.right));
    });
  });
}
