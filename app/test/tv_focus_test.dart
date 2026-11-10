import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_nav_theme.dart';
import 'package:onyx/tv/tv_focus.dart';

import 'support/tv_nav_harness.dart';

/// Un OK long, tel que chaque système le mesure (constat C10) : l'ancien
/// compte les répétitions de la touche tenue (Android répète après environ une
/// demi-seconde, la première répétition est l'appui long) ; dpad mesure la
/// durée entre l'appui et le relâchement.
///
/// [duringHold] s'exécute une fois l'appui long atteint, touche encore
/// enfoncée (pour la suite de répétitions d'un appui qui se prolonge).
Future<void> _holdSelect(
  WidgetTester tester,
  TvNavEngine engine, {
  Future<void> Function()? duringHold,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  switch (engine) {
    case TvNavEngine.legacy:
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    case TvNavEngine.dpad:
      await tester.pump(
        TvNavTheme.longSelectDuration + const Duration(milliseconds: 100),
      );
  }
  await duringHold?.call();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await TvNavHarness.settle(tester);
}

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets('OK active la carte focalisée', (tester) async {
      var taps = 0;
      final node = FocusNode();
      addTearDown(node.dispose);

      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            focusNode: node,
            autofocus: true,
            onSelect: () => taps++,
            child: const TvTestTile('carte'),
          ),
        ),
        engine: engine,
      );

      await nav.select();
      expect(taps, 1, reason: 'le centre du dpad doit activer la carte');

      // La télécommande et le clavier atteignent la même action.
      await nav.select(key: LogicalKeyboardKey.enter);
      await nav.select(key: LogicalKeyboardKey.gameButtonA);
      expect(taps, 3);
    });

    testWidgets('tenir OK ne répète pas l’action', (tester) async {
      var taps = 0;
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () => taps++,
            child: const TvTestTile('carte'),
          ),
        ),
        engine: engine,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await TvNavHarness.settle(tester);

      expect(taps, 1, reason: 'l’auto-répétition ne lance pas trois épisodes');
    });

    testWidgets('une carte désactivée est sautée par la télécommande',
        (tester) async {
      var disabledTaps = 0;
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              TvFocusable(
                autofocus: true,
                onSelect: () {},
                child: const TvTestTile('avant'),
              ),
              TvFocusable(
                // Un épisode qui n'est pas encore sorti : montré, pas
                // atteignable.
                enabled: false,
                onSelect: () => disabledTaps++,
                child: const TvTestTile('inactive'),
              ),
              TvFocusable(
                onSelect: () {},
                child: const TvTestTile('après'),
              ),
            ],
          ),
        ),
        engine: engine,
      );
      expect(nav.focusedLabel, 'avant');

      await nav.press(TraversalDirection.down);

      expect(nav.focusedLabel, 'après',
          reason: 'la carte inatteignable ne doit pas être une impasse');
      expect(disabledTaps, 0);
    });

    testWidgets('la touche menu ouvre le menu de la carte', (tester) async {
      var menus = 0;
      var taps = 0;
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () => taps++,
            onContextMenu: () => menus++,
            child: const TvTestTile('carte'),
          ),
        ),
        engine: engine,
      );

      await nav.select(key: LogicalKeyboardKey.contextMenu);

      expect(menus, 1);
      expect(taps, 0);
    });

    testWidgets('Y d’une manette ouvre le menu de la carte', (tester) async {
      var menus = 0;
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () {},
            onContextMenu: () => menus++,
            child: const TvTestTile('carte'),
          ),
        ),
        engine: engine,
      );

      await nav.select(key: LogicalKeyboardKey.gameButtonY);

      expect(menus, 1);
    });

    testWidgets('sur une carte à menu, un OK court agit au relâchement',
        (tester) async {
      var taps = 0;
      var menus = 0;
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () => taps++,
            onContextMenu: () => menus++,
            child: const TvTestTile('carte'),
          ),
        ),
        engine: engine,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(taps, 0, reason: 'l’appui peut encore devenir un appui long');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      // `flutter_test` date chaque touche de zéro : le relâchement paraît
      // suivre l'appui de 0 ms, comme le rebond d'un clic tenu sur la
      // télécommande du simulateur Apple TV. L'action part une fois passée
      // la fenêtre de ce rebond (40 ms), sans nouvel appui.
      await tester.pump(const Duration(milliseconds: 100));
      await TvNavHarness.settle(tester);
      expect(taps, 1);
      expect(menus, 0);
    });

    testWidgets('tenir OK sur une carte à menu ouvre le menu, et lui seul',
        (tester) async {
      var taps = 0;
      var menus = 0;
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () => taps++,
            onContextMenu: () => menus++,
            child: const TvTestTile('carte'),
          ),
        ),
        engine: engine,
      );

      await _holdSelect(tester, engine);

      expect(menus, 1);
      expect(taps, 0,
          reason: 'relâcher un appui long ne doit pas aussi lancer la carte');
    });

    testWidgets(
        'le menu ouvert par un OK long survit à la fin de l’appui '
        'et ne choisit rien tout seul', (tester) async {
      String? picked;
      var menuClosed = false;

      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TvFocusable(
              autofocus: true,
              onSelect: () {},
              onContextMenu: () async {
                picked = await showMenu<String>(
                  context: context,
                  position: const RelativeRect.fromLTRB(100, 100, 100, 100),
                  items: const [
                    PopupMenuItem(value: 'first', child: Text('Premier')),
                    PopupMenuItem(value: 'second', child: Text('Second')),
                  ],
                );
                menuClosed = true;
              },
              child: const TvTestTile('carte'),
            ),
          ),
        ),
        engine: engine,
      );

      switch (engine) {
        case TvNavEngine.legacy:
          // La touche continue de se répéter après l'ouverture du menu, puis
          // se relâche : ces évènements appartiennent encore à l'appui long.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          // Sur un téléviseur, le premier élément du menu prend le focus :
          // c'est lui que les répétitions activaient.
          Focus.of(tester.element(find.text('Premier'))).requestFocus();
          await tester.pump();
          for (var i = 0; i < 5; i++) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
            await tester.pump();
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
        case TvNavEngine.dpad:
          // C10 : dpad ne répète rien, l'appui long est tranché au relâchement,
          // donc le menu s'ouvre après la fin de l'appui (rien ne le ferme).
          await _holdSelect(tester, engine);
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('Premier'))).requestFocus();
          await tester.pump();
      }

      expect(find.text('Premier'), findsOneWidget,
          reason: 'la touche tenue ne doit pas fermer le menu qu’elle ouvre');
      expect(menuClosed, isFalse);
      expect(picked, isNull);

      // L'appui suivant, lui, appartient au menu.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(menuClosed, isTrue);
      expect(picked, 'first');
    });

    testWidgets('une carte focalisée est ramenée à l’écran', (tester) async {
      final node = FocusNode();
      final controller = ScrollController();
      addTearDown(node.dispose);
      addTearDown(controller.dispose);

      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: SizedBox(
            height: 200,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  // Le focus part d'en haut : sans lui, le banc le poserait
                  // sur la seule carte, déjà défilée avant la mesure.
                  TvFocusable(
                    autofocus: true,
                    onSelect: () {},
                    child: const TvTestTile('départ'),
                  ),
                  const SizedBox(height: 1000),
                  TvFocusable(
                    focusNode: node,
                    onSelect: () {},
                    child: const TvTestTile('cible'),
                  ),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
        engine: engine,
      );

      expect(controller.offset, 0);

      node.requestFocus();
      await tester.pumpAndSettle();

      // Un focus qui tombe hors de l'écran ne laisse aucun curseur à suivre :
      // c'est la fenêtre qui doit venir à lui.
      expect(controller.offset, greaterThan(0));
    });
  });

  // L'enchaînement par Tab (`nextFocus`) est celui de l'ancienne politique de
  // parcours, qui disparaît en phase 8 : dpad n'a pas de Tab.
  group('legacy seulement', () {
    testWidgets('une carte désactivée est sautée par nextFocus',
        (tester) async {
      final before = FocusNode(debugLabel: 'before');
      final after = FocusNode(debugLabel: 'after');
      addTearDown(before.dispose);
      addTearDown(after.dispose);

      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              Focus(
                  focusNode: before,
                  child: const SizedBox(width: 10, height: 10)),
              TvFocusable(
                enabled: false,
                onSelect: () {},
                child: const SizedBox(width: 10, height: 10),
              ),
              Focus(
                  focusNode: after,
                  child: const SizedBox(width: 10, height: 10)),
            ],
          ),
        ),
        engine: TvNavEngine.legacy,
      );

      before.requestFocus();
      await tester.pump();
      before.nextFocus();
      await tester.pump();

      expect(after.hasFocus, isTrue);
    });
  });
}
