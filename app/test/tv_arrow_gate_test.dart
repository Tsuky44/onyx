import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/input/step_target.dart';
import 'package:onyx/tv/input/tv_arrow_gate.dart';
import 'package:onyx/tv/input/tv_dpad_log.dart';
import 'package:onyx/tv/nav/tv_dpad_focusable.dart';
import 'package:onyx/tv/nav/tv_region.dart';

import 'support/tv_nav_harness.dart';

/// Compte les `requestFocus` des cartes : un seul par flèche (ADR-0109).
class _CountingNode extends FocusNode {
  _CountingNode(String label) : super(debugLabel: label);

  static int requests = 0;

  @override
  void requestFocus([FocusNode? node]) {
    if (node == null) requests++;
    super.requestFocus(node);
  }
}

/// Une rangée de cartes sous `OnyxDpad`, le portail monté juste sous `Dpad`
/// comme dans l'app, et deux cartes l'une sous l'autre en dessous.
///
/// La rangée défile à l'horizontale ([scrollable]), comme celles de
/// l'accueil, avec le cache par défaut : sur 1920 de large, les cartes de
/// 180 sont construites jusqu'à la douzième environ.
Future<TvNavHarness> _mount(
  WidgetTester tester, {
  int count = 8,
  TvArrowSteps steps = _one,
  Duration? repeatInterval = TvArrowGate.defaultRepeatInterval,
  bool scrollable = true,
  bool isTv = true,
  void Function(ScrollNotification)? onScroll,
}) async {
  _CountingNode.requests = 0;
  final nodes = [for (var i = 0; i < count; i++) _CountingNode('c$i')];
  addTearDown(() {
    for (final node in nodes) {
      node.dispose();
    }
  });
  Widget card(int i) => TvDpadFocusable(
        autofocus: i == 0,
        focusNode: nodes[i],
        onSelect: () {},
        child: TvTestTile('c$i', width: 180),
      );
  return TvNavHarness.pump(
    tester,
    Scaffold(
      body: TvArrowGate(
        stepsFor: steps,
        repeatInterval: repeatInterval,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TvRegion.rail(
              entersAtStart: false,
              id: 'rangée',
              child: SizedBox(
                height: 120,
                child: scrollable
                    ? NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          onScroll?.call(notification);
                          return false;
                        },
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: count,
                          itemBuilder: (_, i) => card(i),
                        ),
                      )
                    : Row(children: [for (var i = 0; i < count; i++) card(i)]),
              ),
            ),
            TvDpadFocusable(
                onSelect: () {}, child: const TvTestTile('dessous')),
            TvDpadFocusable(
                onSelect: () {}, child: const TvTestTile('dessous 2')),
          ],
        ),
      ),
    ),
    isTv: isTv,
  );
}

int _one(FocusNode from, TraversalDirection direction) => 1;

int _indexOf(String? label) => int.parse(label!.substring(1));

void main() {
  var now = Duration.zero;
  late List<String> log;
  setUp(() {
    now = Duration.zero;
    TvArrowGate.debugClock = () => now;
    log = <String>[];
    TvDpadLog.debugSink = log;
  });
  tearDown(() {
    TvArrowGate.debugClock = null;
    TvDpadLog.debugSink = null;
  });

  Future<void> repeat(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyRepeatEvent(key);
    await TvNavHarness.settle(tester);
  }

  testWidgets('un appui simple : un pas, décidé par dpad, un seul requestFocus',
      (tester) async {
    final nav = await _mount(tester);
    _CountingNode.requests = 0;
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'c1');
    expect(_CountingNode.requests, 1);
    expect(log.last, contains('pas 1 par dpad'));
  });

  testWidgets('une répétition trop rapprochée est retenue (C13)',
      (tester) async {
    final nav = await _mount(tester);
    const key = LogicalKeyboardKey.arrowRight;
    await tester.sendKeyDownEvent(key);
    await TvNavHarness.settle(tester);
    expect(nav.focusedLabel, 'c1');

    now += const Duration(milliseconds: 50);
    await repeat(tester, key);
    expect(nav.focusedLabel, 'c1', reason: 'à 50 ms, retenue');
    expect(log.last, allOf(contains('rep +50 ms'), contains('retenue')));

    now += TvArrowGate.defaultRepeatInterval;
    await repeat(tester, key);
    expect(nav.focusedLabel, 'c2', reason: 'passé l’intervalle, un pas');
    await tester.sendKeyUpEvent(key);
  });

  testWidgets(
      'sans intervalle (Apple TV, cadence réglée par le moteur), aucune '
      'répétition n’est retenue', (tester) async {
    final nav = await _mount(tester, repeatInterval: null);
    const key = LogicalKeyboardKey.arrowRight;
    await tester.sendKeyDownEvent(key);
    await TvNavHarness.settle(tester);
    now += const Duration(milliseconds: 50);
    await repeat(tester, key);
    expect(nav.focusedLabel, 'c2');
    await tester.sendKeyUpEvent(key);
  });

  testWidgets('deux appuis rapides ne sont jamais retenus', (tester) async {
    final nav = await _mount(tester);
    await nav.press(TraversalDirection.right);
    now += const Duration(milliseconds: 10);
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'c2');
  });

  testWidgets(
      'un glissé de trois pas : la carte d’arrivée, un seul '
      'requestFocus', (tester) async {
    final nav = await _mount(tester, steps: (_, __) => 3);
    _CountingNode.requests = 0;
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'c3');
    expect(_CountingNode.requests, 1);
  });

  group('rafales (N2)', () {
    testWidgets(
        'quatre flèches avant que le focus se pose : quatre pas, un seul '
        'requestFocus', (tester) async {
      final nav = await _mount(tester);
      _CountingNode.requests = 0;
      await nav.burst(TraversalDirection.right, 4);
      expect(nav.focusedLabel, 'c4');
      expect(_CountingNode.requests, 1);
      expect(log.where((line) => line.contains('rafale #')), hasLength(3));
      expect(log.last, contains('pas 4/4 (rafale de 4)'));
    });

    testWidgets(
        'la mémoire de la rangée note la carte d’arrivée, pas une carte '
        'demandée en chemin (N3)', (tester) async {
      final nav = await _mount(tester);
      await nav.burst(TraversalDirection.right, 4);
      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'dessous');
      await nav.press(TraversalDirection.up);
      expect(nav.focusedLabel, 'c4');
    });

    testWidgets(
        'une rafale qui sort de l’écran : un seul défilement, un seul '
        'requestFocus', (tester) async {
      var scrolls = 0;
      final nav = await _mount(
        tester,
        count: 20,
        onScroll: (n) => scrolls += n is ScrollStartNotification ? 1 : 0,
      );
      _CountingNode.requests = 0;
      await nav.burst(TraversalDirection.right, 10);
      expect(nav.focusedLabel, 'c10');
      expect(_CountingNode.requests, 1);
      expect(scrolls, 1);
    });

    testWidgets(
        'bornée aux cartes construites, puis dpad fait défiler et '
        'réessaie (C6)', (tester) async {
      final nav = await _mount(tester, count: 40);
      await nav.burst(TraversalDirection.right, 30);
      final reached = _indexOf(nav.focusedLabel);
      expect(reached, inInclusiveRange(9, 29),
          reason: 'la dernière carte construite, pas au-delà');
      expect(log.last, contains('borné : bout de la rangée'));

      // La carte d'arrivée ramenée à l'écran, la rangée a construit la
      // suite : chaque flèche d'après avance d'une carte, sans en perdre.
      for (var i = 1; i <= 5; i++) {
        await nav.press(TraversalDirection.right);
        expect(_indexOf(nav.focusedLabel), reached + i);
      }
    });

    testWidgets('changer de sens au milieu : chaque sens compte ses pas',
        (tester) async {
      final nav = await _mount(tester);
      TvNavHarness.sendBurst(<(LogicalKeyboardKey, PhysicalKeyboardKey)>[
        (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
        (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
        (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
        (LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
      ]);
      await TvNavHarness.settle(tester);
      expect(nav.focusedLabel, 'c2');
    });

    testWidgets('à la verticale, une rafale ne fait qu’un pas (ADR-0039)',
        (tester) async {
      final nav = await _mount(tester);
      await nav.burst(TraversalDirection.down, 3);
      expect(nav.focusedLabel, 'dessous');
      expect(log.last, contains('verticale'));
    });

    testWidgets('hors d’une rangée qui défile, une rafale ne fait qu’un pas',
        (tester) async {
      final nav = await _mount(tester, scrollable: false);
      await nav.burst(TraversalDirection.right, 3);
      expect(nav.focusedLabel, 'c1');
      expect(log.last, contains('hors rangée'));
    });
  });

  testWidgets('jamais plusieurs pas à la verticale (ADR-0039)', (tester) async {
    final nav = await _mount(tester, steps: (_, __) => 3);
    await nav.press(TraversalDirection.down);
    expect(nav.focusedLabel, 'dessous');
  });

  testWidgets('hors téléviseur, tout passe', (tester) async {
    final nav = await _mount(tester, steps: (_, __) => 3, isTv: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await TvNavHarness.settle(tester);
    expect(nav.focusedLabel, 'c0');
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'c1');
    expect(log, isEmpty);
  });

  testWidgets('un Focus d’écran voit la flèche avant le portail et dpad (C4)',
      (tester) async {
    var seen = 0;
    final nav = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: TvArrowGate(
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                seen++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Row(
              children: [
                TvDpadFocusable(
                  autofocus: true,
                  onSelect: () {},
                  child: const TvTestTile('a'),
                ),
                TvDpadFocusable(onSelect: () {}, child: const TvTestTile('b')),
              ],
            ),
          ),
        ),
      ),
    );
    await nav.press(TraversalDirection.right);
    expect(seen, 1);
    expect(nav.focusedLabel, 'a');
  });

  group('StepTarget', () {
    testWidgets('borné aux cartes construites', (tester) async {
      await _mount(tester, count: 4);
      final from = FocusManager.instance.primaryFocus!;
      final hop = StepTarget.after(from, TraversalDirection.right, 10)!;
      expect(focusedLabelOf(hop.node), 'c3');
      expect(hop.steps, 3);
    });

    testWidgets('un pas : la carte voisine', (tester) async {
      await _mount(tester);
      final from = FocusManager.instance.primaryFocus!;
      final hop = StepTarget.after(from, TraversalDirection.right, 1)!;
      expect(focusedLabelOf(hop.node), 'c1');
    });

    testWidgets('à la verticale, ou hors d’une rangée qui défile : rien',
        (tester) async {
      await _mount(tester);
      final from = FocusManager.instance.primaryFocus!;
      expect(StepTarget.after(from, TraversalDirection.right, 0), isNull);
      expect(StepTarget.after(from, TraversalDirection.down, 3), isNull);
      expect(StepTarget.after(from, TraversalDirection.up, 3), isNull);
    });

    testWidgets('une rangée qui ne défile pas : rien', (tester) async {
      await _mount(tester, scrollable: false);
      final from = FocusManager.instance.primaryFocus!;
      expect(StepTarget.after(from, TraversalDirection.right, 3), isNull);
    });

    testWidgets('au bord de la rangée : rien', (tester) async {
      await _mount(tester);
      final from = FocusManager.instance.primaryFocus!;
      expect(StepTarget.after(from, TraversalDirection.left, 3), isNull);
    });

    testWidgets('un bouton posé au bout de la rangée ne compte pas',
        (tester) async {
      final first = FocusNode(debugLabel: 'r0');
      addTearDown(first.dispose);
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: SizedBox(
            height: 120,
            child: Row(
              children: [
                SizedBox(
                  width: 600,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < 3; i++)
                        TvDpadFocusable(
                          autofocus: i == 0,
                          focusNode: i == 0 ? first : null,
                          onSelect: () {},
                          child: TvTestTile('r$i', width: 180),
                        ),
                    ],
                  ),
                ),
                TvDpadFocusable(
                    onSelect: () {}, child: const TvTestTile('à côté')),
              ],
            ),
          ),
        ),
      );
      final hop = StepTarget.after(first, TraversalDirection.right, 6)!;
      expect(focusedLabelOf(hop.node), 'r2');
      expect(hop.steps, 2);
    });
  });
}
