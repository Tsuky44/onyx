import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/input/tv_dpad_log.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/touchpad_motion.dart';
import 'package:onyx/tv/tv_touchpad.dart';

import 'support/tv_nav_harness.dart';

/// Le trackpad de la Siri Remote (ADR-0039), avec l'un et l'autre système de
/// navigation : sous dpad, l'accélération et l'élan passent par
/// `TvArrowGate` et `StepTarget` (phase 6), mais promettent la même chose.
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

  /// Un coup sec sur le trackpad : 2,1 unités en 112 ms, vers la droite ou
  /// vers le bas.
  void flick({bool lift = false, bool down = false}) {
    void touch(TouchpadPhase phase, double travel) => TvTouchpad.handleTouch(
          phase,
          down ? 0 : travel,
          down ? travel : 0,
        );
    touch(TouchpadPhase.began, 0);
    for (var i = 1; i <= 7; i++) {
      clock += const Duration(milliseconds: 16);
      touch(TouchpadPhase.moved, 0.3 * i);
    }
    if (lift) touch(TouchpadPhase.ended, 2.1);
  }

  testWidgets('le lecteur reçoit chaque déplacement du doigt', (tester) async {
    final moves = <double>[];
    void listener(TouchpadMove move) => moves.add(move.dx);
    TvTouchpad.addMoveListener(listener);

    flick();
    expect(TvTouchpad.isSwiping, isTrue);
    TvTouchpad.removeMoveListener(listener);
    TvTouchpad.handleTouch(TouchpadPhase.moved, 2.4, 0);

    expect(moves, hasLength(7));
    expect(moves.fold<double>(0, (a, b) => a + b), closeTo(2.1, 1e-9));
  });

  TvNavHarness.forEachEngine((engine) {
    Future<List<FocusNode>> pumpRow(
      WidgetTester tester, {
      required bool scrollable,
      Axis axis = Axis.horizontal,
      int count = 30,
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
            child: TvTestTile('card$i', width: 100, height: 100),
          ),
      ];
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: axis == Axis.horizontal ? 120 : 1000,
              width: axis == Axis.horizontal ? 1900 : 120,
              child: scrollable
                  ? ListView(scrollDirection: axis, children: cards)
                  : Row(children: cards),
            ),
          ),
        ),
        engine: engine,
      );
      return nodes;
    }

    int focusedIndex(List<FocusNode> nodes) =>
        nodes.indexWhere((node) => node.hasFocus);

    testWidgets('dans une rangée, un coup sec avance de plusieurs affiches',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      flick();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 3);
    });

    testWidgets('à la verticale, un glissé descend d’une ligne à la fois',
        (tester) async {
      // À l'essai, un glissé vers le bas sautait des rangées entières de
      // l'accueil et des lignes des réglages.
      final nodes =
          await pumpRow(tester, scrollable: true, axis: Axis.vertical);

      flick(lift: true, down: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), 1);
    });

    testWidgets('sans glissé, une flèche avance d’une seule affiche',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 1);
    });

    testWidgets('hors de ce qui défile, un pas reste un pas', (tester) async {
      // Une barre de boutons : sauter trois commandes d'un geste serait se
      // perdre.
      final nodes = await pumpRow(tester, scrollable: false, count: 10);

      flick();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 1);
    });

    testWidgets('un geste lâché vif continue sur sa lancée, puis s’arrête',
        (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      flick(lift: true);
      expect(TvTouchpad.isGliding, isTrue);
      await tester.pump(const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), 3);
    });

    testWidgets('poser le doigt arrête la lancée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      flick(lift: true);
      await tester.pump(const Duration(milliseconds: 70));
      expect(focusedIndex(nodes), 1);

      TvTouchpad.handleTouch(TouchpadPhase.began, 0, 0);
      await tester.pump(const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), 1);
    });

    testWidgets('OK pendant la lancée la coupe', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      flick(lift: true);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 3));

      expect(focusedIndex(nodes), 1);
    });

    testWidgets('une flèche dans l’autre sens coupe la lancée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true);

      flick(lift: true);
      await tester.pump(const Duration(milliseconds: 70));
      expect(focusedIndex(nodes), 1);
      // Hors de la grâce de la flèche du geste lui-même.
      clock += const Duration(milliseconds: 200);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), 0);
    });

    testWidgets('la lancée s’arrête au bout de la rangée', (tester) async {
      final nodes = await pumpRow(tester, scrollable: true, count: 3);

      flick(lift: true);
      await tester.pump(const Duration(seconds: 3));

      expect(TvTouchpad.isGliding, isFalse);
      expect(focusedIndex(nodes), 2);
    });
  });

  group('dpad', () {
    testWidgets('l’élan passe par le portail, et ses traces le racontent',
        (tester) async {
      final log = <String>[];
      TvDpadLog.debugSink = log;
      addTearDown(() => TvDpadLog.debugSink = null);
      final nodes = [for (var i = 0; i < 10; i++) FocusNode()];
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
                for (var i = 0; i < 10; i++)
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

      flick(lift: true);
      await tester.pump(const Duration(seconds: 3));

      expect(log.first, contains('élan : right, 3 pas'));
      expect(log.where((line) => line.contains('élan : pas →')), hasLength(3));
      expect(log.last, contains('élan coupé : fini'));
    });
  });
}
