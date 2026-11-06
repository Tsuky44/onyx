import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/tv/nav/tv_dpad_focusable.dart';
import 'package:onyx/tv/nav/tv_nav_theme.dart';

import 'support/tv_nav_harness.dart';

/// L'anneau d'Onyx : la bordure de la couleur d'accent posée sur la carte.
Finder _ring() => find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.border is Border &&
          (decoration.border! as Border).top.color == AppColors.accent;
    });

void main() {
  group('un Select = un onSelect (C9)', () {
    for (final key in [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.gameButtonA,
    ]) {
      testWidgets('cible simple, ${key.debugName}', (tester) async {
        var selects = 0;
        final nav = await TvNavHarness.pump(
          tester,
          Scaffold(
            body: TvDpadFocusable(
              autofocus: true,
              onSelect: () => selects++,
              child: const TvTestTile('carte'),
            ),
          ),
        );
        await nav.select(key: key);
        expect(selects, 1);
      });
    }

    testWidgets(
        'cible qui enveloppe un bouton Material : l’action passe par '
        'onSelect, jamais par onPressed (N4)', (tester) async {
      var selects = 0;
      var pressed = 0;
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvDpadFocusable(
            autofocus: true,
            onSelect: () => selects++,
            child: ElevatedButton(
              onPressed: () => pressed++,
              child: const Text('bouton'),
            ),
          ),
        ),
      );
      // tvOS envoie Select en `enter`, que reconnaît aussi l'ActivateIntent.
      await nav.select(key: LogicalKeyboardKey.enter);
      expect(selects, 1);
      expect(pressed, 0);
    });

    testWidgets('tenir OK ne déclenche l’action qu’une fois', (tester) async {
      var selects = 0;
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvDpadFocusable(
            autofocus: true,
            onSelect: () => selects++,
            child: const TvTestTile('carte'),
          ),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await TvNavHarness.settle(tester);
      expect(selects, 1);
    });
  });

  group('menu de la carte', () {
    Future<(int Function(), int Function())> mount(WidgetTester tester) async {
      var selects = 0;
      var menus = 0;
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvDpadFocusable(
            autofocus: true,
            onSelect: () => selects++,
            onContextMenu: () => menus++,
            child: const TvTestTile('carte'),
          ),
        ),
      );
      return (() => selects, () => menus);
    }

    testWidgets('appui court : l’action, au relâchement', (tester) async {
      final (selects, menus) = await mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await TvNavHarness.settle(tester);
      expect(selects(), 1);
      expect(menus(), 0);
    });

    testWidgets('appui long : le menu, pas l’action', (tester) async {
      final (selects, menus) = await mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(
          TvNavTheme.longSelectDuration + const Duration(milliseconds: 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await TvNavHarness.settle(tester);
      expect(selects(), 0);
      expect(menus(), 1);
    });

    for (final key in [
      LogicalKeyboardKey.contextMenu,
      LogicalKeyboardKey.gameButtonY,
    ]) {
      testWidgets('${key.debugName} ouvre le menu', (tester) async {
        final (selects, menus) = await mount(tester);
        await tester.sendKeyEvent(key);
        await TvNavHarness.settle(tester);
        expect(menus(), 1);
        expect(selects(), 0);
      });
    }
  });

  testWidgets('l’anneau suit le focus', (tester) async {
    final nav = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Row(
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
    );
    expect(
        find.descendant(
            of: find.ancestor(of: find.text('a'), matching: find.byType(Stack)),
            matching: _ring()),
        findsOneWidget);
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'b');
    expect(_ring(), findsOneWidget);
  });

  testWidgets('une carte inactive est inatteignable', (tester) async {
    final nav = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Row(
          children: [
            TvDpadFocusable(
              autofocus: true,
              onSelect: () {},
              child: const TvTestTile('a'),
            ),
            TvDpadFocusable(
              enabled: false,
              onSelect: () {},
              child: const TvTestTile('b'),
            ),
            TvDpadFocusable(onSelect: () {}, child: const TvTestTile('c')),
          ],
        ),
      ),
    );
    await nav.press(TraversalDirection.right);
    expect(nav.focusedLabel, 'c');
  });

  testWidgets('hors téléviseur : ni autofocus, ni anneau', (tester) async {
    final nav = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: TvDpadFocusable(
          autofocus: true,
          onSelect: () {},
          child: const TvTestTile('a'),
        ),
      ),
      isTv: false,
    );
    expect(nav.focusedLabel, isNull);
    expect(_ring(), findsNothing);
  });

  testWidgets('le toucher reste à l’enfant', (tester) async {
    var selects = 0;
    var taps = 0;
    await TvNavHarness.pump(
      tester,
      Scaffold(
        body: TvDpadFocusable(
          onSelect: () => selects++,
          child: GestureDetector(
            onTap: () => taps++,
            child: const TvTestTile('a'),
          ),
        ),
      ),
      isTv: false,
    );
    await tester.tap(find.text('a'));
    await TvNavHarness.settle(tester);
    expect(taps, 1);
    expect(selects, 0);
  });
}
