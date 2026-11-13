import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/input/tv_dpad_log.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/touchpad_motion.dart';
import 'package:onyx/tv/tv_touchpad.dart';
import 'package:onyx/tv/tv_touchpad_pace.dart';

import 'support/tv_nav_harness.dart';

/// Le trackpad de la Siri Remote (ADR-0116), avec l'un et l'autre système de
/// navigation : le trajet du doigt fait les pas, le lâcher garde son élan, et
/// les flèches que le moteur tire du même geste sont retenues.
void main() {
  var clock = Duration.zero;

  setUp(() {
    // Le banc d'essai vide les observateurs de touches après chaque test.
    TvTouchpad.debugInstallKeyObserver();
    TvTouchpad.debugReset();
    clock = Duration.zero;
    TvTouchpad.debugClock = () => clock;
  });
  tearDown(TvTouchpad.debugReset);

  /// Un glissé de [distance] unités en [duration], un point toutes les 16 ms,
  /// vers la droite ou vers le bas. L'horloge du pavé et celle du test
  /// avancent ensemble.
  Future<void> swipe(
    WidgetTester tester, {
    required double distance,
    required Duration duration,
    bool lift = false,
    bool down = false,
  }) async {
    void touch(TouchpadPhase phase, double travel) => TvTouchpad.handleTouch(
          phase,
          down ? 0 : travel,
          down ? travel : 0,
        );
    touch(TouchpadPhase.began, 0);
    final frames = (duration.inMilliseconds / 16).ceil();
    for (var i = 1; i <= frames; i++) {
      clock += const Duration(milliseconds: 16);
      touch(TouchpadPhase.moved, distance * i / frames);
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (lift) touch(TouchpadPhase.ended, distance);
  }

  /// Un coup sec : 1,6 unité en 160 ms, 10 unités par seconde.
  Future<void> flick(WidgetTester tester,
          {bool lift = false, bool down = false}) =>
      swipe(
        tester,
        distance: 1.6,
        duration: const Duration(milliseconds: 160),
        lift: lift,
        down: down,
      );

  /// Laisse passer [duration], pour le pavé comme pour le test.
  Future<void> wait(WidgetTester tester, Duration duration) async {
    const slice = Duration(milliseconds: 10);
    for (var left = duration; left > Duration.zero; left -= slice) {
      clock += slice;
      await tester.pump(slice);
    }
  }

  testWidgets('le lecteur reçoit chaque déplacement du doigt', (tester) async {
    final moves = <double>[];
    bool listener(TouchpadMove move) {
      moves.add(move.dx);
      return true;
    }

    TvTouchpad.addMoveListener(listener);

    await flick(tester);
    expect(TvTouchpad.isSwiping, isTrue);
    TvTouchpad.removeMoveListener(listener);
    TvTouchpad.handleTouch(TouchpadPhase.moved, 2.4, 0);

    expect(moves, hasLength(10));
    expect(moves.fold<double>(0, (a, b) => a + b), closeTo(1.6, 1e-9));
  });

  TvNavHarness.forEachEngine((engine) {
    Future<List<FocusNode>> pumpRow(
      WidgetTester tester, {
      required bool scrollable,
      Axis axis = Axis.horizontal,
      int count = 30,
      double height = 100,
      bool declaredPrecise = false,
    }) async {
      final nodes = [
        for (var i = 0; i < count; i++) FocusNode(debugLabel: 'card$i'),
      ];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      final cards = [
        for (var i = 0; i < count; i++)
          TvFocusable(
            focusNode: nodes[i],
            autofocus: i == 0,
            onSelect: () {},
            child: TvTestTile('card$i', width: 100, height: height),
          ),
      ];
      final Widget list = scrollable
          ? ListView(scrollDirection: axis, children: cards)
          : Row(children: cards);
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              // Une liste horizontale étire ses enfants à sa hauteur : elle
              // suit donc celle des cartes, qui décide du rythme du pavé.
              height: axis == Axis.horizontal ? height + 20 : 1000,
              width: axis == Axis.horizontal ? 1900 : 120,
              child: declaredPrecise
                  ? TvTouchpadPace.precise(child: list)
                  : list,
            ),
          ),
        ),
        engine: engine,
      );
      return nodes;
    }

    int focusedIndex(List<FocusNode> nodes) =>
        nodes.indexWhere((node) => node.hasFocus);

    testWidgets('un glissé lent avance d’une affiche par pas de trajet',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      // 2 unités en une seconde : le premier pas à 0,32, puis un tous les
      // 0,75. Aucune flèche du moteur dans ce test : le doigt suffit.
      await swipe(tester,
          distance: 2, duration: const Duration(milliseconds: 1000));
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 3);
    });

    testWidgets('la flèche que le moteur tire du glissé ne compte pas en plus',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await swipe(tester,
          distance: 0.5, duration: const Duration(milliseconds: 250));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 1);
    });

    testWidgets('sans glissé, une flèche avance d’une seule affiche',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 1);
    });

    testWidgets('un clic sur l’anneau, le doigt posé sans glisser, passe',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      TvTouchpad.handleTouch(TouchpadPhase.began, 0.8, 0);
      clock += const Duration(milliseconds: 16);
      TvTouchpad.handleTouch(TouchpadPhase.moved, 0.81, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 1);
    });

    testWidgets('à la verticale, un glissé descend au rythme du doigt',
        (tester) async {
      // À l'essai, un glissé vers le bas sautait des rangées entières de
      // l'accueil et des lignes des réglages.
      final nodes =
          await pumpRow(tester, scrollable: true, axis: Axis.vertical);

      await swipe(
        tester,
        distance: 1,
        duration: const Duration(milliseconds: 400),
        lift: true,
        down: true,
      );
      await wait(tester, const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      // Un glissé ordinaire descend d'une rangée (réglage du 2026-11-13).
      expect(focusedIndex(nodes), 1);
    });

    testWidgets('hors de ce qui défile, pas d’élan', (tester) async {
      // Une barre de boutons : sauter des commandes d'un geste serait se
      // perdre.
      final nodes = await pumpRow(tester, scrollable: false, count: 10);

      await flick(tester, lift: true);
      final landed = focusedIndex(nodes);
      await wait(tester, const Duration(seconds: 3));

      expect(landed, lessThanOrEqualTo(4));
      expect(focusedIndex(nodes), landed);
    });

    // ADR-0122 : la pilule des onglets défile, et prenait donc le gain et la
    // lancée d'une rangée d'affiches (« super rapide », essai de la 1.1.42).
    // Puis « trop faible » à un cran par glissé : le trajet vaut maintenant
    // deux ou trois crans, rendus même si le doigt est allé plus vite que le
    // focus.
    testWidgets(
        'une barre d’onglets qui défile avance de trois crans pour un coup '
        'sec, sans la lancée d’une rangée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true, height: 36);
      expect(TvTouchpad.paceOf(nodes.first), TouchpadPace.precise);

      // 1,6 unité en 160 ms : deux crans sous le doigt, un troisième dû.
      await flick(tester, lift: true);
      expect(focusedIndex(nodes), 2);
      await wait(tester, const Duration(seconds: 3));

      // Sur des affiches, le même geste en traverserait bien davantage.
      expect(focusedIndex(nodes), 3);
      expect(TvTouchpad.isGliding, isFalse);
    });

    testWidgets('sur des onglets, un glissé ordinaire avance de deux crans',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true, height: 36);

      await swipe(
        tester,
        distance: 1,
        duration: const Duration(milliseconds: 300),
        lift: true,
      );
      await wait(tester, const Duration(seconds: 1));

      expect(focusedIndex(nodes), 2);
    });

    testWidgets('sur des onglets, un long glissé posé avance de quatre crans',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true, height: 36);

      await swipe(
        tester,
        distance: 1.6,
        duration: const Duration(milliseconds: 700),
        lift: true,
      );
      await wait(tester, const Duration(seconds: 1));

      expect(focusedIndex(nodes), 4);
    });

    testWidgets('poser le doigt arrête les crans dus', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true, height: 36);

      await flick(tester, lift: true);
      expect(focusedIndex(nodes), 2);
      TvTouchpad.handleTouch(TouchpadPhase.began, 0, 0);
      await wait(tester, const Duration(seconds: 1));

      expect(focusedIndex(nodes), 2);
    });

    testWidgets(
        'une zone déclarée posée l’emporte sur la hauteur de ses lignes',
        (tester) async {
      // Une ligne de réglage monte jusqu'à 170 px : plus qu'une vignette
      // d'épisode, et pourtant une commande.
      final nodes = await pumpRow(
        tester,
        scrollable: true,
        axis: Axis.vertical,
        height: 120,
        declaredPrecise: true,
      );
      expect(TvTouchpad.paceOf(nodes.first), TouchpadPace.precise);

      await flick(tester, lift: true, down: true);
      await wait(tester, const Duration(seconds: 3));

      // Trois lignes, pas la traversée d'une liste d'affiches.
      expect(focusedIndex(nodes), 3);
    });

    testWidgets('une carte reste une carte : sa hauteur la désigne',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      expect(TvTouchpad.paceOf(nodes.first), TouchpadPace.browse);
    });

    testWidgets('un geste lâché vif continue sur sa lancée, puis s’arrête',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await flick(tester, lift: true);
      final lifted = focusedIndex(nodes);
      expect(TvTouchpad.isGliding, isTrue);
      await wait(tester, const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      // Posé, le même trajet de 1,6 unité vaut 3 affiches en tout.
      expect(focusedIndex(nodes), greaterThan(lifted + 2));
      expect(focusedIndex(nodes), greaterThan(3));
    });

    testWidgets('poser le doigt arrête la lancée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await flick(tester, lift: true);
      await wait(tester, const Duration(milliseconds: 70));
      final stopped = focusedIndex(nodes);

      TvTouchpad.handleTouch(TouchpadPhase.began, 0, 0);
      await wait(tester, const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), stopped);
    });

    testWidgets('OK pendant la lancée la coupe', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await flick(tester, lift: true);
      await wait(tester, const Duration(milliseconds: 70));
      final stopped = focusedIndex(nodes);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await wait(tester, const Duration(seconds: 3));

      expect(focusedIndex(nodes), stopped);
    });

    testWidgets('une flèche dans l’autre sens coupe la lancée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await flick(tester, lift: true);
      // Hors de la grâce de la flèche du geste lui-même.
      await wait(tester, const Duration(milliseconds: 200));
      final stopped = focusedIndex(nodes);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await wait(tester, const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), stopped - 1);
    });

    testWidgets('la lancée s’arrête au bout de la rangée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true, count: 3);

      await flick(tester, lift: true);
      await wait(tester, const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), 2);
    });

    testWidgets('un geste dont le lecteur se sert ne déplace pas le focus',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);
      bool listener(TouchpadMove move) => true;
      TvTouchpad.addMoveListener(listener);

      await flick(tester, lift: true);
      await wait(tester, const Duration(seconds: 3));

      expect(focusedIndex(nodes), 0);
    });
  });

  group('dpad', () {
    testWidgets('l’élan passe par le portail, et ses traces le racontent',
        (tester) async {
      final log = <String>[];
      TvDpadLog.debugSink = log;
      addTearDown(() => TvDpadLog.debugSink = null);
      final nodes = [for (var i = 0; i < 30; i++) FocusNode()];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < 30; i++)
                  TvFocusable(
                    focusNode: nodes[i],
                    autofocus: i == 0,
                    onSelect: () {},
                    child: TvTestTile('c$i', width: 100),
                  ),
              ],
            ),
          ),
        ),
        engine: TvNavEngine.dpad,
      );
      expect(TvTouchpad.glideStepper, isNotNull);

      await flick(tester, lift: true);
      await wait(tester, const Duration(seconds: 3));

      final glide = log.where((line) => line.contains('élan')).toList();
      expect(glide.first, contains('élan : right'));
      expect(glide.where((line) => line.contains('élan : pas →')), isNotEmpty);
      expect(glide.last, contains('élan coupé : fini'));
    });
  });
}
