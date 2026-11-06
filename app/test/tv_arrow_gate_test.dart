import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/input/step_target.dart';
import 'package:onyx/tv/input/tv_arrow_gate.dart';
import 'package:onyx/tv/nav/tv_dpad_focusable.dart';

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
/// comme il le sera en phase 2.
Future<TvNavHarness> _mount(
  WidgetTester tester, {
  int count = 8,
  TvArrowSteps steps = _one,
  bool isTv = true,
}) async {
  _CountingNode.requests = 0;
  final nodes = [for (var i = 0; i < count; i++) _CountingNode('c$i')];
  addTearDown(() {
    for (final node in nodes) {
      node.dispose();
    }
  });
  return TvNavHarness.pump(
    tester,
    Scaffold(
      body: TvArrowGate(
        stepsFor: steps,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  TvDpadFocusable(
                    autofocus: i == 0,
                    focusNode: nodes[i],
                    onSelect: () {},
                    child: TvTestTile('c$i', width: 180),
                  ),
              ],
            ),
            TvDpadFocusable(
                onSelect: () {}, child: const TvTestTile('dessous')),
          ],
        ),
      ),
    ),
    isTv: isTv,
  );
}

int _one(FocusNode from, TraversalDirection direction) => 1;

void main() {
  var now = Duration.zero;
  setUp(() {
    now = Duration.zero;
    TvArrowGate.debugClock = () => now;
  });
  tearDown(() => TvArrowGate.debugClock = null);

  Future<void> repeat(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyRepeatEvent(key);
    await TvNavHarness.settle(tester);
  }

  testWidgets('un appui simple passe, un seul requestFocus', (tester) async {
    final nav = await _mount(tester);
    _CountingNode.requests = 0;
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'c1');
    expect(_CountingNode.requests, 1);
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

    now += TvArrowGate.defaultRepeatInterval;
    await repeat(tester, key);
    expect(nav.focusedLabel, 'c2', reason: 'passé l’intervalle, un pas');
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
      final target = StepTarget.after(from, TraversalDirection.right, 10);
      expect(focusedLabelOf(target), 'c3');
    });

    testWidgets('moins de deux pas, ou à la verticale : rien', (tester) async {
      await _mount(tester);
      final from = FocusManager.instance.primaryFocus!;
      expect(StepTarget.after(from, TraversalDirection.right, 1), isNull);
      expect(StepTarget.after(from, TraversalDirection.down, 3), isNull);
      expect(StepTarget.after(from, TraversalDirection.up, 3), isNull);
    });

    testWidgets('au bord de la rangée : rien', (tester) async {
      await _mount(tester);
      final from = FocusManager.instance.primaryFocus!;
      expect(StepTarget.after(from, TraversalDirection.left, 3), isNull);
    });
  });
}
