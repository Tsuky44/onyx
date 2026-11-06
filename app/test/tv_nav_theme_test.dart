import 'package:dpad/dpad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_motion.dart';
import 'package:onyx/tv/nav/tv_nav_theme.dart';

void main() {
  test('la marge de défilement est la zone sûre latérale de tvOS (C12)', () {
    // 80 points sur 1920, ramenés à la page de 1280 pixels logiques.
    expect(TvNavTheme.scrollPadding, closeTo(53.33, 0.01));
  });

  test('le thème ne dessine rien : l’anneau reste celui d’Onyx (ADR-0008)', () {
    expect(TvNavTheme.data(lite: false).effects, isEmpty);
  });

  test('le défilement suit les durées d’Onyx, et saute en mode léger', () {
    final full = TvNavTheme.data(lite: false);
    expect(full.scrollDuration, AppMotion.standard);
    expect(full.scrollCurve, AppMotion.curve);
    expect(TvNavTheme.data(lite: true).scrollDuration, Duration.zero);
  });

  test('l’appui long dure ce qu’il dure sur Android TV', () {
    expect(TvNavTheme.data(lite: false).longSelectDuration,
        const Duration(milliseconds: 500));
  });

  test('le centre reste le centre, le reste se ramène au plus près', () {
    expect(TvNavTheme.alignmentFor(0.5), DpadRevealAlignment.center);
    expect(TvNavTheme.alignmentFor(0.2), DpadRevealAlignment.nearest);
    expect(TvNavTheme.alignmentFor(0), DpadRevealAlignment.nearest);
  });
}
