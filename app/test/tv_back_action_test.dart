import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';

import 'support/tv_nav_harness.dart';

/// Une touche Retour dépile une page sur un téléviseur qui n'est pas Android
/// (Apple TV, téléviseur LG), avec les deux systèmes de navigation : l'ancien
/// par `TvBackAction`, dpad par `TvBack` (ADR-0110). Hors téléviseur, Échap
/// garde son sens de bureau.
///
/// Porté sur le banc en phase 5 : il montait `TvBackAction` seul, que dpad ne
/// monte plus. La classe reste tant que le drapeau `ONYX_TV_NAV` existe.
Widget _home() => Builder(
      builder: (context) => Scaffold(
        body: TvFocusable(
          autofocus: true,
          onSelect: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: TvFocusable(
                  autofocus: true,
                  onSelect: () {},
                  child: const TvTestTile('détail'),
                ),
              ),
            ),
          ),
          child: const TvTestTile('accueil'),
        ),
      ),
    );

Future<TvNavHarness> _openDetail(WidgetTester tester, TvNavHarness nav) async {
  nav.navigatorKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('détail')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('détail'), findsOneWidget);
  return nav;
}

void main() {
  TvNavHarness.forEachEngine((engine) {
    // Échap : un clavier, le Retour d'un téléviseur LG, et peut-être le Menu
    // de la Siri Remote ; B : une manette. (goBack est celui d'Android, où le
    // système fait le travail.)
    for (final key in [
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.gameButtonB,
    ]) {
      testWidgets('${key.debugName} recule d’une page sur téléviseur',
          (tester) async {
        final nav = await TvNavHarness.pump(tester, _home(), engine: engine);
        await nav.select();
        await tester.pumpAndSettle();
        expect(find.text('détail'), findsOneWidget);

        await nav.back(key: key);
        await tester.pumpAndSettle();

        expect(find.text('détail'), findsNothing);
        expect(nav.focusedLabel, 'accueil');
      });
    }

    testWidgets('Échap garde son sens de bureau hors téléviseur',
        (tester) async {
      final nav =
          await TvNavHarness.pump(tester, _home(), engine: engine, isTv: false);
      await _openDetail(tester, nav);

      await nav.back();
      await tester.pumpAndSettle();

      expect(find.text('détail'), findsOneWidget);
    });
  });
}
