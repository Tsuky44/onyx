import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/input/tv_arrow_gate.dart';
import 'package:onyx/tv/input/tv_repeat_cadence.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_key_repeat.dart';

import 'support/tv_nav_harness.dart';

/// La flèche maintenue, avec l'un et l'autre système : `TvKeyRepeat` et
/// `TvDirectionalFocusAction` avec l'ancien, `TvArrowGate` avec dpad.
void main() {
  setUpAll(TvKeyRepeat.install);

  TvNavHarness.forEachEngine((engine) {
    Future<List<FocusNode>> pumpRow(WidgetTester tester, int count) async {
      final nodes = [
        for (var i = 0; i < count; i++) FocusNode(debugLabel: 'card$i'),
      ];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < count; i++)
                TvFocusable(
                  focusNode: nodes[i],
                  autofocus: i == 0,
                  onSelect: () {},
                  child: const SizedBox(width: 40, height: 40),
                ),
            ],
          ),
        ),
        engine: engine,
      );
      return nodes;
    }

    int focusedIndex(List<FocusNode> nodes) =>
        nodes.indexWhere((node) => node.hasFocus);

    testWidgets('une flèche maintenue ne dépasse pas le débit régulé',
        (tester) async {
      final nodes = await pumpRow(tester, 10);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      // Une rafale de répétitions arrivées dans le même instant : une seule
      // passe, les autres attendent l'intervalle.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), lessThanOrEqualTo(3));
    });

    testWidgets('des appuis distincts ne sont jamais retenus', (tester) async {
      final nodes = await pumpRow(tester, 10);

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await TvNavHarness.settle(tester);

      expect(focusedIndex(nodes), 5);
    });

    testWidgets('au bout d’une rangée, droite ne saute pas ailleurs à l’écran',
        (tester) async {
      final header = FocusNode(debugLabel: 'header');
      final cards = [
        for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'card$i'),
      ];
      addTearDown(header.dispose);
      addTearDown(() {
        for (final node in cards) {
          node.dispose();
        }
      });

      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Stack(
            children: [
              // Un bouton de l'en-tête, en haut à droite, au-delà de la rangée.
              Positioned(
                right: 0,
                top: 0,
                child: TvFocusable(
                  focusNode: header,
                  onSelect: () {},
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
              Positioned(
                left: 0,
                top: 200,
                // Une rangée de l'app est une zone (`MediaRow`) : sous dpad,
                // c'est elle qui arrête la flèche à son bout.
                child: TvRegion.rail(
                  id: 'rangée',
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        TvFocusable(
                          focusNode: cards[i],
                          autofocus: i == 0,
                          onSelect: () {},
                          child: const SizedBox(width: 60, height: 60),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        engine: engine,
      );

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await TvNavHarness.settle(tester);
      }

      expect(cards.last.hasFocus, isTrue);
      expect(header.hasFocus, isFalse);
    });
  });

  group('cadence sous dpad (C13)', () {
    tearDown(() => TvRepeatCadence.debugNativeOverride = null);

    test(
        'sur Apple TV, le moteur répète à 110 ms et le portail ne retient rien',
        () {
      TvRepeatCadence.debugNativeOverride = true;
      final pushed = <Duration>[];
      TvRepeatCadence.install(configure: pushed.add);
      expect(pushed, <Duration>[TvArrowGate.defaultRepeatInterval]);
      expect(TvRepeatCadence.gateRepeatInterval, isNull);
    });

    test('ailleurs, rien n’est poussé et le portail régule à 110 ms', () {
      TvRepeatCadence.debugNativeOverride = false;
      final pushed = <Duration>[];
      TvRepeatCadence.install(configure: pushed.add);
      expect(pushed, isEmpty);
      expect(TvRepeatCadence.gateRepeatInterval,
          TvArrowGate.defaultRepeatInterval);
    });

    test('la cadence est celle de l’ancien système', () {
      expect(TvRepeatCadence.interval, TvKeyRepeat.repeatInterval);
    });
  });
}
