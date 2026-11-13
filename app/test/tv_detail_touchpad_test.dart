import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/touchpad_motion.dart';
import 'package:onyx/tv/tv_touchpad.dart';

import 'support/tv_detail_bench.dart';
import 'support/tv_nav_harness.dart';

/// Le pavé de la Siri Remote sur une fiche (ADR-0128) : un glissé vertical
/// avance d'une étape. Sur les vrais écrans, avec les deux systèmes de
/// navigation.
///
/// Avant, vu sur Apple TV : un glissé ordinaire menait de « Lecture » à
/// l'éventail de la distribution par-dessus son titre, un coup sec remontait
/// de trois sections jusqu'au bouton retour, et un long glissé sur les
/// épisodes finissait dans les titres similaires par-dessus la distribution.
void main() {
  var clock = Duration.zero;

  setUp(() {
    TvDetailBench.setUp();
    // Le banc d'essai vide les observateurs de touches après chaque test.
    TvTouchpad.debugInstallKeyObserver();
    TvTouchpad.debugReset();
    clock = Duration.zero;
    TvTouchpad.debugClock = () => clock;
  });
  tearDown(TvTouchpad.debugReset);

  /// Un glissé vertical de [distance] unités (la surface en fait 2) en
  /// [duration], un point toutes les 16 ms, doigt levé à la fin ; puis le
  /// temps qu'un élan ou des crans dus auraient mis à se jouer.
  Future<void> swipe(
    WidgetTester tester, {
    required double distance,
    required Duration duration,
    bool up = false,
  }) async {
    final sign = up ? -1.0 : 1.0;
    TvTouchpad.handleTouch(TouchpadPhase.began, 0, 0);
    final frames = (duration.inMilliseconds / 16).ceil();
    for (var i = 1; i <= frames; i++) {
      clock += const Duration(milliseconds: 16);
      TvTouchpad.handleTouch(
        TouchpadPhase.moved,
        0,
        sign * distance * i / frames,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    TvTouchpad.handleTouch(TouchpadPhase.ended, 0, sign * distance);
    for (var i = 0; i < 60; i++) {
      clock += const Duration(milliseconds: 10);
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
  }

  /// La moitié de la surface, posément.
  Future<void> ordinary(WidgetTester tester, {bool up = false}) => swipe(
        tester,
        distance: 1.0,
        duration: const Duration(milliseconds: 250),
        up: up,
      );

  /// Un coup sec : 1,6 unité en 160 ms, 10 unités par seconde.
  Future<void> flick(WidgetTester tester, {bool up = false}) => swipe(
        tester,
        distance: 1.6,
        duration: const Duration(milliseconds: 160),
        up: up,
      );

  /// D'un bord à l'autre de la surface.
  Future<void> long(WidgetTester tester, {bool up = false}) => swipe(
        tester,
        distance: 2.0,
        duration: const Duration(milliseconds: 500),
        up: up,
      );

  /// Le doigt glisse de [from] à [to] unités sans quitter la surface : il
  /// n'est ni posé avant, ni levé après.
  Future<void> drag(
    WidgetTester tester, {
    required double from,
    required double to,
    required Duration duration,
  }) async {
    final frames = (duration.inMilliseconds / 16).ceil();
    for (var i = 1; i <= frames; i++) {
      clock += const Duration(milliseconds: 16);
      TvTouchpad.handleTouch(
        TouchpadPhase.moved,
        0,
        from + (to - from) * i / frames,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
  }

  /// Le doigt reste posé, immobile.
  Future<void> rest(WidgetTester tester, Duration duration) async {
    clock += duration;
    await tester.pump(duration);
  }

  const focused = TvDetailBench.focused;
  const section = TvDetailBench.focusedSection;

  TvNavHarness.forEachEngine((engine) {
    testWidgets(
        'sur la fiche d’un film, chaque glissé descend d’une section, quelle '
        'que soit sa force', (tester) async {
      await TvDetailBench.pumpMovie(tester, engine: engine);
      expect(focused(), 'Reprendre');

      await ordinary(tester);
      expect(section(), 'info', reason: 'un glissé ordinaire');
      expect(focused(), 'A0');
      await flick(tester);
      expect(section(), 'collection', reason: 'un coup sec');
      await long(tester);
      expect(section(), 'similar', reason: 'un long glissé');
    });

    testWidgets(
        'en remontant, un coup sec s’arrête à la lecture au lieu de filer '
        'jusqu’au bouton retour', (tester) async {
      final nav = await TvDetailBench.pumpMovie(tester, engine: engine);
      await TvDetailBench.press(tester, nav, TraversalDirection.down);
      expect(section(), 'info');

      await flick(tester, up: true);
      expect(focused(), 'Reprendre');

      // Le bouton retour reste à un geste, pas plus.
      await long(tester, up: true);
      expect(focused(), 'Retour');
      await long(tester);
      expect(focused(), 'Reprendre');
    });

    testWidgets(
        'sur une série, les commandes vont cran par cran : saisons, '
        '« marquer vue », en-tête des épisodes', (tester) async {
      await TvDetailBench.pumpShow(tester, engine: engine);
      expect(focused(), 'Lecture S1 E1');

      await long(tester);
      expect(focused(), 'Saison 1');
      await long(tester);
      expect(focused(), 'Marquer la saison vue');
      await flick(tester);
      expect(focused(), 'Télécharger la saison');
      await long(tester);
      expect(focused(), 'Épisode 1');
    });

    testWidgets(
        'les épisodes se parcourent d’un trait, et la liste s’arrête à sa '
        'dernière ligne', (tester) async {
      await TvDetailBench.pumpShow(tester, engine: engine);
      await TvDetailBench.focusOn(tester, 'Épisode 1');

      await long(tester);
      expect(focused(), 'Épisode 3', reason: 'deux lignes d’un long glissé');

      await TvDetailBench.focusOn(
        tester,
        'Épisode ${TvDetailBench.episodeCount - 1}',
      );
      await long(tester);
      expect(
        focused(),
        'Épisode ${TvDetailBench.episodeCount}',
        reason: 'le même glissé ne déborde pas sur la distribution',
      );

      // La section suivante demande son propre geste.
      await ordinary(tester);
      expect(section(), 'info');
    });

    testWidgets(
        'en remontant les épisodes, le geste s’arrête au premier, sous '
        'l’en-tête de la liste', (tester) async {
      await TvDetailBench.pumpShow(tester, engine: engine);
      await TvDetailBench.focusOn(tester, 'Épisode 2');

      await long(tester, up: true);
      expect(focused(), 'Épisode 1');
      await long(tester, up: true);
      expect(focused(), 'Télécharger la saison');
    });

    testWidgets(
        'sans lever le doigt, un glissé continu ne franchit qu’une étape ; '
        'après une pause, le doigt qui repart en franchit une autre',
        (tester) async {
      await TvDetailBench.pumpShow(tester, engine: engine);
      expect(focused(), 'Lecture S1 E1');

      TvTouchpad.handleTouch(TouchpadPhase.began, 0, -1);
      await drag(
        tester,
        from: -1,
        to: 0.2,
        duration: const Duration(milliseconds: 400),
      );
      expect(focused(), 'Saison 1', reason: 'un seul cran pour tout ce trajet');

      await rest(tester, const Duration(milliseconds: 300));
      await drag(
        tester,
        from: 0.2,
        to: 0.8,
        duration: const Duration(milliseconds: 250),
      );
      expect(focused(), 'Marquer la saison vue');
      TvTouchpad.handleTouch(TouchpadPhase.ended, 0, 0.8);
      await tester.pumpAndSettle();
      expect(focused(), 'Marquer la saison vue');
    });
  });
}
