import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_dpad_focusable.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_memory.dart';
import 'package:onyx/tv/tv_focus_panes.dart';
import 'package:onyx/tv/tv_mode.dart' show TvScope;

import 'support/tv_nav_harness.dart';

Widget _row(String prefix, int count) => Row(
      children: [
        for (var i = 0; i < count; i++)
          TvDpadFocusable(onSelect: () {}, child: TvTestTile('$prefix$i')),
      ],
    );

void main() {
  group('sans OnyxDpad : l’ancien système, à l’identique', () {
    Future<void> mount(WidgetTester tester, Widget region) async {
      await tester.pumpWidget(
        TvScope(
          isTv: true,
          child: MaterialApp(home: Scaffold(body: region)),
        ),
      );
    }

    testWidgets('une rangée est une TvFocusMemory', (tester) async {
      await mount(
        tester,
        const TvRegion.rail(
          id: 'home/r0',
          entersAtTop: true,
          child: TvFocusable(child: Text('a')),
        ),
      );
      final memory = tester.widget<TvFocusMemory>(find.byType(TvFocusMemory));
      expect(memory.entersAtTop, isTrue);
      expect(find.byType(DpadRegion), findsNothing);
    });

    testWidgets('un volet est un TvFocusPane', (tester) async {
      await mount(
        tester,
        const TvFocusPanes(
          child: TvRegion.pane(
            id: 'settings/categories',
            child: TvFocusable(child: Text('a')),
          ),
        ),
      );
      expect(find.byType(TvFocusPane), findsOneWidget);
      expect(find.byType(DpadRegion), findsNothing);
    });
  });

  group('sous OnyxDpad : une DpadRegion', () {
    testWidgets('chaque forme règle ses bords', (tester) async {
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              TvRegion.rail(id: 'r', child: _row('r', 1)),
              TvRegion.grid(id: 'g', child: _row('g', 1)),
              TvRegion.list(id: 'l', child: _row('l', 1)),
              TvRegion.tabs(id: 't', child: _row('t', 1)),
              TvRegion.pane(id: 'p', child: _row('p', 1)),
            ],
          ),
        ),
      );
      DpadRegion region(String id) => tester.widget<DpadRegion>(
          find.byWidgetPredicate((w) => w is DpadRegion && w.debugLabel == id));

      expect(region('r').horizontalEdge, DpadEdgeBehavior.stop);
      expect(region('g').horizontalEdge, DpadEdgeBehavior.lineWrap);
      expect(region('l').horizontalEdge, DpadEdgeBehavior.leave);
      expect(region('t').horizontalEdge, DpadEdgeBehavior.stop);
      expect(region('t').enter, DpadEnterBehavior.entry);
      expect(region('p').horizontalEdge, DpadEdgeBehavior.leave);
      for (final id in ['r', 'g', 'l', 'p']) {
        expect(region(id).enter, DpadEnterBehavior.restore, reason: id);
      }
      expect(find.byType(TvFocusMemory), findsNothing);
    });

    testWidgets('au bout d’une rangée, le focus reste dans la rangée',
        (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TvRegion.rail(id: 'r', child: _row('c', 3)),
              // Plus loin à droite, mais plus bas : l'ancien saut à l'autre
              // bout de l'écran.
              Padding(
                padding: const EdgeInsets.only(top: 400),
                child: TvDpadFocusable(
                  onSelect: () {},
                  child: const TvTestTile('ailleurs'),
                ),
              ),
            ],
          ),
        ),
      );
      expect(nav.focusedLabel, 'c0');
      for (var i = 0; i < 4; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(nav.focusedLabel, 'c2');
    });

    testWidgets('remonter vers une rangée rend la carte quittée',
        (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TvRegion.rail(id: 'r0', child: _row('r0 c', 5)),
              TvRegion.rail(id: 'r1', child: _row('r1 c', 5)),
            ],
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.right);
      }
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.left);
      await nav.press(TraversalDirection.left);
      expect(nav.focusedLabel, 'r1 c1');
      await nav.press(TraversalDirection.up);
      expect(nav.focusedLabel, 'r0 c3');
    });
  });
}
