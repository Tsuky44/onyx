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

  testWidgets('une marche n’est consultée que si sa route est au premier plan',
      (tester) async {
    var steps = 0;
    final nav = await TvNavHarness.pump(
      tester,
      TvBackStep(onBack: () => ++steps > 0, child: _page('A')),
    );
    final state = tester.state<TvBackState>(find.byType(TvBack));
    expect(state.handleKey(), isTrue, reason: 'la marche de A a répondu');
    expect(steps, 1);

    nav.navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => _page('B')));
    await TvNavHarness.settle(tester);
    now += TvBack.defaultWindow;
    await nav.popRoute();
    expect(find.text('B'), findsNothing, reason: 'B se dépile d’abord');
    expect(steps, 1, reason: 'la marche de A, couverte, n’a pas été appelée');
  });

  testWidgets('une route qui garde son Retour (PopScope) le reçoit, une fois',
      (tester) async {
    var ownBacks = 0;
    final nav = await _stack(tester, ['A']);
    nav.navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ownBacks++;
        },
        child: _page('Lecteur'),
      ),
    ));
    await TvNavHarness.settle(tester);
    await nav.popRoute();
    expect(ownBacks, 1);
    expect(find.text('Lecteur'), findsOneWidget);
  });

  group('un écran qui lit lui-même la touche Retour (le lecteur)', () {
    testWidgets('touche puis popRoute du même appui : popRoute est absorbé',
        (tester) async {
      var ownBacks = 0;
      final nav = await _stack(tester, ['A']);
      nav.navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) ownBacks++;
          },
          child: _page('Lecteur'),
        ),
      ));
      await TvNavHarness.settle(tester);
      final context = tester.element(find.text('Lecteur'));

      expect(TvBack.claimKey(context), isTrue, reason: 'appui neuf');
      now += const Duration(milliseconds: 20);
      await nav.popRoute();
      expect(ownBacks, 0, reason: 'la seconde moitié du même appui');
    });

    testWidgets('popRoute puis touche du même appui : la touche est avalée',
        (tester) async {
      final nav = await _stack(tester, ['A', 'B']);
      await nav.popRoute();
      now += const Duration(milliseconds: 20);
      expect(TvBack.claimKey(tester.element(find.text('A'))), isFalse);
    });

    testWidgets('deux touches de suite sont deux appuis', (tester) async {
      await _stack(tester, ['A']);
      final context = tester.element(find.text('A'));
      expect(TvBack.claimKey(context), isTrue);
      now += const Duration(milliseconds: 20);
      expect(TvBack.claimKey(context), isTrue);
    });

    testWidgets('sans TvBack (ancien système), la touche agit toujours',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('seul')));
      expect(TvBack.claimKey(tester.element(find.text('seul'))), isTrue);
    });
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
