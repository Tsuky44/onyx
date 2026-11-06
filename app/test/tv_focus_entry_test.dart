import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_entry.dart';
import 'package:onyx/tv/tv_focus_memory.dart';
import 'package:onyx/tv/tv_mode.dart';

/// Un en-tête à trois éléments au-dessus d'un contenu : deux « onglets » et
/// une « recherche » à droite. Le contenu a un bouton à gauche et un à droite.
class _Page {
  _Page() {
    for (final node in all) {
      addTearDown(node.dispose);
    }
    addTearDown(header.dispose);
  }

  final FocusNode header =
      FocusNode(debugLabel: 'header', canRequestFocus: false);
  final FocusNode tabA = FocusNode(debugLabel: 'tabA');
  final FocusNode tabB = FocusNode(debugLabel: 'tabB');
  final FocusNode search = FocusNode(debugLabel: 'search');
  final FocusNode contentLeft = FocusNode(debugLabel: 'contentLeft');
  final FocusNode contentRight = FocusNode(debugLabel: 'contentRight');

  List<FocusNode> get all => [tabA, tabB, search, contentLeft, contentRight];
}

Widget _app(_Page page) {
  Widget box(FocusNode node) => TvFocusable(
        focusNode: node,
        focusScale: 1.0,
        onSelect: () {},
        child: const SizedBox(width: 80, height: 40),
      );

  return TvScope(
    isTv: true,
    child: MaterialApp(
      builder: (context, child) =>
          FocusTraversalGroup(policy: TvTraversalPolicy(), child: child!),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              focusNode: page.header,
              canRequestFocus: false,
              skipTraversal: true,
              child: FocusTraversalGroup(
                policy: TvWidgetOrderTraversalPolicy(),
                child: Row(
                  children: [
                    box(page.tabA),
                    box(page.tabB),
                    const Spacer(),
                    box(page.search),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                box(page.contentLeft),
                const Spacer(),
                box(page.contentRight),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => TvMode.enabled.value = true);
  tearDown(() => TvMode.enabled.value = false);

  testWidgets('Haut depuis le contenu entre sur l’onglet affiché, en une passe',
      (tester) async {
    final page = _Page();
    // L'onglet affiché est le second, que la géométrie ne désignerait pas
    // depuis le bouton de gauche (elle choisirait le premier).
    TvFocusEntries.register(page.header, (landed, from) {
      if (from != null && from.ancestors.contains(page.header)) return null;
      return {page.tabA, page.tabB}.contains(landed) ? page.tabB : null;
    });
    addTearDown(() => TvFocusEntries.unregister(page.header));
    await tester.pumpWidget(_app(page));

    var landedOnWrongTab = false;
    void spy() => landedOnWrongTab |= page.tabA.hasPrimaryFocus;
    page.tabA.addListener(spy);
    addTearDown(() => page.tabA.removeListener(spy));

    page.contentLeft.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(page.tabB.hasFocus, isTrue);
    expect(landedOnWrongTab, isFalse);
  });

  testWidgets('la recherche, à droite de l’en-tête, reste atteignable',
      (tester) async {
    final page = _Page();
    TvFocusEntries.register(page.header, (landed, from) {
      if (from != null && from.ancestors.contains(page.header)) return null;
      return {page.tabA, page.tabB}.contains(landed) ? page.tabB : null;
    });
    addTearDown(() => TvFocusEntries.unregister(page.header));
    await tester.pumpWidget(_app(page));

    page.contentRight.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(page.search.hasFocus, isTrue);
  });

  testWidgets('dans l’en-tête, la zone ne redirige rien', (tester) async {
    final page = _Page();
    TvFocusEntries.register(page.header, (landed, from) {
      if (from != null && from.ancestors.contains(page.header)) return null;
      return page.tabB;
    });
    addTearDown(() => TvFocusEntries.unregister(page.header));
    await tester.pumpWidget(_app(page));

    page.tabB.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(page.tabA.hasFocus, isTrue);
  });

  testWidgets('hors téléviseur, aucune zone ne redirige', (tester) async {
    TvMode.enabled.value = false;
    final page = _Page();
    TvFocusEntries.register(page.header, (landed, from) => page.tabB);
    addTearDown(() => TvFocusEntries.unregister(page.header));
    await tester.pumpWidget(_app(page));

    expect(TvFocusEntries.resolve(page.tabA), same(page.tabA));
  });

  testWidgets('une zone retirée n’est plus consultée', (tester) async {
    final page = _Page();
    TvFocusEntries.register(page.header, (landed, from) => page.tabB);
    await tester.pumpWidget(_app(page));
    expect(TvFocusEntries.resolve(page.tabA), same(page.tabB));

    TvFocusEntries.unregister(page.header);

    expect(TvFocusEntries.resolve(page.tabA), same(page.tabA));
  });

  testWidgets('la mémoire d’une zone retirée ne retient plus rien',
      (tester) async {
    final key = GlobalKey<TvFocusMemoryState>();
    final card = FocusNode(debugLabel: 'card');
    addTearDown(card.dispose);

    await tester.pumpWidget(TvScope(
      isTv: true,
      child: MaterialApp(
        home: TvFocusMemory(
          key: key,
          child: TvFocusable(
            focusNode: card,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    ));
    card.requestFocus();
    await tester.pump();
    final state = key.currentState!;
    expect(state.remembered, same(card));

    await tester.pumpWidget(const SizedBox.shrink());

    expect(state.remembered, isNull);
  });
}
