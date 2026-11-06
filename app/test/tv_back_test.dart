import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_back.dart';
import 'package:onyx/tv/nav/tv_dpad_focusable.dart';

import 'support/tv_nav_harness.dart';

Widget _page(String title) => Scaffold(
      body: Column(
        children: [
          Text(title),
          TvDpadFocusable(
            autofocus: true,
            onSelect: () {},
            child: TvTestTile('$title bouton'),
          ),
        ],
      ),
    );

Future<TvNavHarness> _stack(WidgetTester tester, List<String> titles,
    {bool isTv = true, bool android = false}) async {
  final nav = await TvNavHarness.pump(tester, _page(titles.first),
      isTv: isTv, android: android);
  for (final title in titles.skip(1)) {
    nav.navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => _page(title)));
    await TvNavHarness.settle(tester);
  }
  return nav;
}

void main() {
  var now = Duration.zero;
  setUp(() {
    now = Duration.zero;
    TvBack.debugClock = () => now;
  });
  tearDown(() => TvBack.debugClock = null);

  testWidgets('popRoute dépile une route', (tester) async {
    final nav = await _stack(tester, ['A', 'B']);
    await nav.popRoute();
    expect(find.text('B'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('une touche Retour dépile une route', (tester) async {
    final nav = await _stack(tester, ['A', 'B']);
    await nav.back();
    expect(find.text('B'), findsNothing);
    expect(nav.focusedLabel, 'A bouton');
  });

  testWidgets('touche puis popRoute du même appui : une seule couche (C2)',
      (tester) async {
    final nav = await _stack(tester, ['A', 'B', 'C']);
    await nav.back();
    now += const Duration(milliseconds: 20);
    await nav.popRoute();
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('popRoute puis touche du même appui : une seule couche',
      (tester) async {
    final nav = await _stack(tester, ['A', 'B', 'C']);
    await nav.popRoute();
    now += const Duration(milliseconds: 20);
    await nav.back();
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('deux appuis de même origine, même rapides, font deux couches',
      (tester) async {
    final nav = await _stack(tester, ['A', 'B', 'C']);
    await nav.popRoute();
    now += const Duration(milliseconds: 20);
    await nav.popRoute();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('deux appuis d’origines différentes, espacés, font deux couches',
      (tester) async {
    final nav = await _stack(tester, ['A', 'B', 'C']);
    await nav.back();
    now += TvBack.defaultWindow + const Duration(milliseconds: 1);
    await nav.popRoute();
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('à la racine, Retour est rendu au système', (tester) async {
    await _stack(tester, ['A']);
    final state = tester.state<TvBackState>(find.byType(TvBack));
    expect(await state.didPopRoute(), isFalse);
    expect(state.handleKey(), isFalse);
  });

  testWidgets('un dialogue se ferme avant que la page ne se dépile',
      (tester) async {
    final nav = await _stack(tester, ['A', 'B']);
    showDialog<void>(
      context: nav.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('dialogue')),
    );
    await TvNavHarness.settle(tester);
    await nav.popRoute();
    expect(find.text('dialogue'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('hors téléviseur, TvBack ne décide de rien', (tester) async {
    final nav = await _stack(tester, ['A', 'B'], isTv: false);
    final state = tester.state<TvBackState>(find.byType(TvBack));
    expect(await state.didPopRoute(), isFalse);
    expect(state.handleKey(), isFalse);
    // Le Retour de Flutter, lui, dépile toujours.
    await nav.popRoute();
    expect(find.text('B'), findsNothing);
  });

  testWidgets('Échap hors téléviseur garde son sens de bureau', (tester) async {
    await _stack(tester, ['A', 'B'], isTv: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await TvNavHarness.settle(tester);
    expect(find.text('B'), findsOneWidget);
  });
}
