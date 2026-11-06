import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/onyx_dpad.dart' show TvNavScope;
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_entry.dart';
import 'package:onyx/tv/tv_focus_memory.dart';

import 'support/tv_nav_harness.dart';

/// Un en-tête à trois éléments au-dessus d'un contenu : deux « onglets » et
/// une « recherche » à droite. Le contenu a un bouton à gauche et un à droite.
/// L'onglet affiché est le second (`tabB`), que la géométrie ne désignerait pas
/// depuis le bouton de gauche (elle choisirait le premier).
///
/// L'en-tête se monte comme `main_shell` le fait (`_headerZone`) : sous dpad,
/// une `TvRegion.tabs` dont l'onglet affiché est marqué `entry` ; avec l'ancien
/// système, un groupe à parcours dans l'ordre des widgets et une réponse de
/// zone enregistrée dans `TvFocusEntries`.
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final FocusNode header =
      FocusNode(debugLabel: 'header', canRequestFocus: false);
  final FocusNode tabA = FocusNode(debugLabel: 'tabA');
  final FocusNode tabB = FocusNode(debugLabel: 'tabB');
  final FocusNode contentLeft = FocusNode(debugLabel: 'contentLeft');
  final FocusNode contentRight = FocusNode(debugLabel: 'contentRight');
  bool _registered = false;

  FocusNode? _enterHeader(FocusNode landed, FocusNode? from) {
    if (from != null && from.ancestors.contains(header)) return null;
    return {tabA, tabB}.contains(landed) ? tabB : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final legacy = !TvNavScope.isActive(context);
    if (legacy && !_registered) {
      TvFocusEntries.register(header, _enterHeader);
      _registered = true;
    }
  }

  @override
  void dispose() {
    if (_registered) TvFocusEntries.unregister(header);
    header.dispose();
    tabA.dispose();
    tabB.dispose();
    contentLeft.dispose();
    contentRight.dispose();
    super.dispose();
  }

  Widget _box(String label, {FocusNode? node, bool entry = false}) =>
      TvFocusable(
        focusNode: node,
        entry: entry,
        focusScale: 1.0,
        onSelect: () {},
        child: TvTestTile(label, width: 80, height: 40),
      );

  @override
  Widget build(BuildContext context) {
    final headerRow = Row(
      children: [
        _box('tabA', node: tabA),
        _box('tabB', node: tabB, entry: true),
        const Spacer(),
        _box('search'),
      ],
    );
    final Widget headerZone = TvNavScope.isActive(context)
        ? TvRegion.tabs(child: headerRow)
        : Focus(
            focusNode: header,
            canRequestFocus: false,
            skipTraversal: true,
            child: FocusTraversalGroup(
              policy: TvWidgetOrderTraversalPolicy(),
              child: headerRow,
            ),
          );
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerZone,
          const SizedBox(height: 40),
          Row(
            children: [
              _box('contentLeft', node: contentLeft),
              const Spacer(),
              _box('contentRight', node: contentRight),
            ],
          ),
        ],
      ),
    );
  }
}

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets(
        'Haut depuis le contenu entre sur l’onglet affiché, en une passe',
        (tester) async {
      final nav =
          await TvNavHarness.pump(tester, const _Page(), engine: engine);
      final tabA = tester.state<_PageState>(find.byType(_Page)).tabA;

      var landedOnWrongTab = false;
      void spy() => landedOnWrongTab |= tabA.hasPrimaryFocus;
      tabA.addListener(spy);
      addTearDown(() => tabA.removeListener(spy));

      // Le contenu n'a pas le focus au départ : on le lui donne.
      await _focus(tester, nav, 'contentLeft');
      await nav.press(TraversalDirection.up);

      expect(nav.focusedLabel, 'tabB');
      expect(landedOnWrongTab, isFalse);
    });

    testWidgets('la recherche, à droite de l’en-tête, reste atteignable',
        (tester) async {
      final nav =
          await TvNavHarness.pump(tester, const _Page(), engine: engine);
      await _focus(tester, nav, 'contentRight');
      await nav.press(TraversalDirection.up);

      // Écart assumé : avec l'ancien système, la zone ne répond que si le
      // focus tombe sur un onglet, et la recherche est atteinte telle quelle ;
      // sous dpad, une zone d'onglets s'entre toujours par l'onglet affiché,
      // même depuis la droite de l'écran, et la recherche s'atteint ensuite
      // par la droite.
      switch (engine) {
        case TvNavEngine.legacy:
          expect(nav.focusedLabel, 'search');
        case TvNavEngine.dpad:
          expect(nav.focusedLabel, 'tabB');
          await nav.press(TraversalDirection.right);
          expect(nav.focusedLabel, 'search');
      }
    });

    testWidgets('dans l’en-tête, la zone ne redirige rien', (tester) async {
      final nav =
          await TvNavHarness.pump(tester, const _Page(), engine: engine);
      final tabB = tester.state<_PageState>(find.byType(_Page)).tabB;
      tabB.requestFocus();
      await TvNavHarness.settle(tester);
      expect(nav.focusedLabel, 'tabB');

      await nav.press(TraversalDirection.left);

      expect(nav.focusedLabel, 'tabA');
    });
  });

  group('legacy seulement', () {
    // Ces tests lisent `TvFocusEntries` et `TvFocusMemoryState`, des détails
    // de l'ancien système qui disparaissent avec lui en phase 8.
    testWidgets('hors téléviseur, aucune zone ne redirige', (tester) async {
      await TvNavHarness.pump(tester, const _Page(),
          engine: TvNavEngine.legacy, isTv: false);
      final tabA = tester.state<_PageState>(find.byType(_Page)).tabA;

      expect(TvFocusEntries.resolve(tabA), same(tabA));
    });

    testWidgets('une zone retirée n’est plus consultée', (tester) async {
      await TvNavHarness.pump(tester, const _Page(),
          engine: TvNavEngine.legacy);
      final state = tester.state<_PageState>(find.byType(_Page));
      expect(TvFocusEntries.resolve(state.tabA), same(state.tabB));

      TvFocusEntries.unregister(state.header);
      state._registered = false;

      expect(TvFocusEntries.resolve(state.tabA), same(state.tabA));
    });

    testWidgets('la mémoire d’une zone retirée ne retient plus rien',
        (tester) async {
      final key = GlobalKey<TvFocusMemoryState>();
      final card = FocusNode(debugLabel: 'card');
      addTearDown(card.dispose);

      final nav = await TvNavHarness.pump(
        tester,
        TvFocusMemory(
          key: key,
          child: TvFocusable(
            focusNode: card,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
        engine: TvNavEngine.legacy,
      );
      card.requestFocus();
      await tester.pump();
      final state = key.currentState!;
      expect(state.remembered, same(card));

      await tester.pumpWidget(TvNavHarnessApp(
        engine: TvNavEngine.legacy,
        navigatorKey: nav.navigatorKey,
        profileKey: 'test-profile',
        home: const SizedBox.shrink(),
      ));

      expect(state.remembered, isNull);
    });
  });
}

/// Donne le focus au nœud de contenu nommé [label].
Future<void> _focus(WidgetTester tester, TvNavHarness nav, String label) async {
  final state = tester.state<_PageState>(find.byType(_Page));
  (label == 'contentLeft' ? state.contentLeft : state.contentRight)
      .requestFocus();
  await TvNavHarness.settle(tester);
  expect(nav.focusedLabel, label);
}
