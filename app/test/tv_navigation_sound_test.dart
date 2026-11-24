import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/navigation/search_route_observer.dart';
import 'package:onyx/screens/settings/settings_categories.dart';
import 'package:onyx/screens/settings/settings_search.dart';
import 'package:onyx/screens/settings/widgets/navigation_sound_tile.dart';
import 'package:onyx/services/player_presence.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/touchpad_motion.dart';
import 'package:onyx/tv/tv_navigation_sound.dart';
import 'package:onyx/tv/tv_touchpad.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// Les sons de navigation de l'Apple TV (ADR
/// `2026-11-23-fytroz-sons-de-navigation-apple-tv`), avec l'un et l'autre
/// système de navigation.
///
/// L'hôte natif n'existe pas ici : une doublure du canal note ce que Dart
/// lui demande. Ce que ces tests tiennent, c'est *quand* un son part ; que
/// l'Apple TV le fasse entendre ne se vérifie que sur l'appareil.
void main() {
  const channel = MethodChannel('onyx/tv_navigation_sound');
  final messenger = TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger;

  late List<String> calls;
  var clock = Duration.zero;

  int count(String sound) => calls.where((call) => call == sound).length;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TvNavigationSound.resetForTest();
    TvNavigationSound.debugSupported = true;
    clock = Duration.zero;
    TvNavigationSound.debugClock = () => clock;
    calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'prepare'
          ? <String, String>{'move': 'file', 'push': 'file', 'pop': 'file'}
          : null;
    });
    // Le banc d'essai vide les observateurs de touches après chaque test :
    // c'est par celui de la télécommande que le clic apprend une flèche.
    TvTouchpad.debugReset();
    TvTouchpad.debugInstallKeyObserver();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    TvNavigationSound.resetForTest();
    TvTouchpad.debugReset();
  });

  TvNavHarness.forEachEngine((engine) {
    Future<(TvNavHarness, List<FocusNode>)> pumpRow(
      WidgetTester tester, {
      int count = 4,
    }) async {
      final nodes = [
        for (var i = 0; i < count; i++) FocusNode(debugLabel: 'card$i'),
      ];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      final harness = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < count; i++)
                TvFocusable(
                  focusNode: nodes[i],
                  autofocus: i == 0,
                  onSelect: () {},
                  child: TvTestTile('card$i', width: 100, height: 100),
                ),
            ],
          ),
        ),
        engine: engine,
        navigatorObservers: [TvNavigationSound.routeObserver],
      );
      return (harness, nodes);
    }

    testWidgets('une flèche qui déplace le focus joue le clic, une fois',
        (tester) async {
      await TvNavigationSound.initialize();
      final (harness, nodes) = await pumpRow(tester);
      // Le focus d'entrée de la page n'est le pas de personne.
      expect(calls, ['prepare']);

      await harness.press(TraversalDirection.right);

      expect(nodes[1].hasFocus, isTrue);
      expect(calls, ['prepare', 'move']);
    });

    testWidgets('une flèche refusée au bord ne joue rien', (tester) async {
      await TvNavigationSound.initialize();
      final (harness, nodes) = await pumpRow(tester);

      await harness.press(TraversalDirection.left);
      await harness.press(TraversalDirection.up);

      expect(nodes[0].hasFocus, isTrue);
      expect(count('move'), 0);
    });

    testWidgets('un focus posé sans flèche reste muet', (tester) async {
      await TvNavigationSound.initialize();
      final (_, nodes) = await pumpRow(tester);

      nodes[2].requestFocus();
      await TvNavHarness.settle(tester);

      expect(nodes[2].hasFocus, isTrue);
      expect(count('move'), 0);
    });

    testWidgets(
        'une flèche butée au bord ne fait pas sonner le focus qui suit OK',
        (tester) async {
      await TvNavigationSound.initialize();
      final (harness, nodes) = await pumpRow(tester);

      await harness.press(TraversalDirection.left);
      await harness.select();
      nodes[2].requestFocus();
      await TvNavHarness.settle(tester);

      expect(nodes[2].hasFocus, isTrue);
      expect(count('move'), 0);
    });

    testWidgets('une flèche butée au bord ne vaut plus rien un instant après',
        (tester) async {
      await TvNavigationSound.initialize();
      final (harness, nodes) = await pumpRow(tester);

      await harness.press(TraversalDirection.left);
      clock += TvNavigationSound.stepWindow + const Duration(milliseconds: 1);
      nodes[2].requestFocus();
      await TvNavHarness.settle(tester);

      expect(count('move'), 0);
    });

    testWidgets('pendant une lecture, rien ne joue', (tester) async {
      await TvNavigationSound.initialize();
      final (harness, nodes) = await pumpRow(tester);
      PlayerPresence.enter();
      addTearDown(PlayerPresence.leave);

      await harness.press(TraversalDirection.right);
      expect(nodes[1].hasFocus, isTrue);
      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      );
      await TvNavHarness.settle(tester);
      harness.navigatorKey.currentState!.pop();
      await TvNavHarness.settle(tester);

      expect(calls, ['prepare']);
    });

    testWidgets('ouvrir une page joue push, la quitter joue pop',
        (tester) async {
      await TvNavigationSound.initialize();
      final (harness, _) = await pumpRow(tester);
      // La première route est l'app qui démarre.
      expect(count('push'), 0);

      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TvFocusable(
              autofocus: true,
              onSelect: () {},
              child: const TvTestTile('fiche'),
            ),
          ),
        ),
      );
      await TvNavHarness.settle(tester);
      expect(calls, ['prepare', 'push']);

      harness.navigatorKey.currentState!.pop();
      await TvNavHarness.settle(tester);
      // Ni le focus d'entrée de la fiche ni celui qu'on retrouve en revenant
      // ne sont des pas : ils n'ajoutent pas de clic.
      expect(calls, ['prepare', 'push', 'pop']);
    });

    testWidgets(
        'une page ouverte juste après une flèche butée ne joue que push',
        (tester) async {
      await TvNavigationSound.initialize();
      final (harness, _) = await pumpRow(tester);

      // Menu arrive sans touche sur Apple TV : rien d'autre ne désarmerait
      // la flèche avant que le focus de la page ne se pose.
      await harness.press(TraversalDirection.left);
      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TvFocusable(
              autofocus: true,
              onSelect: () {},
              child: const TvTestTile('fiche'),
            ),
          ),
        ),
      );
      await TvNavHarness.settle(tester);
      expect(harness.focusedLabel, 'fiche');

      await harness.press(TraversalDirection.left);
      harness.navigatorKey.currentState!.pop();
      await TvNavHarness.settle(tester);

      expect(calls, ['prepare', 'push', 'pop']);
    });

    testWidgets('le lecteur s’ouvre et se referme sans un son',
        (tester) async {
      await TvNavigationSound.initialize();
      final (harness, _) = await pumpRow(tester);

      // Le lecteur ne s'annonce ouvert qu'une fois monté, et le reste encore
      // quand sa route se retire : c'est son nom qui le fait reconnaître.
      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings:
              const RouteSettings(name: SearchRouteObserver.playerRouteName),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
      await TvNavHarness.settle(tester);
      harness.navigatorKey.currentState!.pop();
      await TvNavHarness.settle(tester);

      expect(calls, ['prepare']);
    });

    testWidgets('hors Apple TV, aucun appel ne part vers le canal',
        (tester) async {
      TvNavigationSound.debugSupported = false;
      await TvNavigationSound.initialize();
      final (harness, nodes) = await pumpRow(tester);

      await harness.press(TraversalDirection.right);
      TvNavigationSound.noteStep();
      nodes[3].requestFocus();
      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      );
      await TvNavHarness.settle(tester);
      harness.navigatorKey.currentState!.pop();
      await TvNavHarness.settle(tester);

      expect(calls, isEmpty);
    });

    testWidgets('un pas du pavé tactile joue le clic comme une flèche',
        (tester) async {
      var touchpadClock = Duration.zero;
      TvTouchpad.debugClock = () => touchpadClock;
      await TvNavigationSound.initialize();
      final (_, nodes) = await pumpRow(tester);

      // Un glissé de 0,5 unité en 250 ms : un pas, le premier (0,32 de
      // trajet). Aucune flèche du moteur : le doigt suffit.
      TvTouchpad.handleTouch(TouchpadPhase.began, 0, 0);
      for (var i = 1; i <= 16; i++) {
        touchpadClock += const Duration(milliseconds: 16);
        clock += const Duration(milliseconds: 16);
        TvTouchpad.handleTouch(TouchpadPhase.moved, 0.5 * i / 16, 0);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await TvNavHarness.settle(tester);

      expect(nodes[1].hasFocus, isTrue);
      expect(count('move'), 1);
    });
  });

  group('cadence', () {
    Future<List<FocusNode>> pumpNodes(WidgetTester tester) async {
      final nodes = [
        for (var i = 0; i < 12; i++) FocusNode(debugLabel: 'card$i'),
      ];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      await tester.pumpWidget(MaterialApp(
        home: Row(
          children: [
            for (final node in nodes)
              Focus(focusNode: node, child: const SizedBox(width: 10)),
          ],
        ),
      ));
      return nodes;
    }

    /// Un pas toutes les [every] : le focus avance d'une cible à chaque fois.
    Future<void> steps(
      WidgetTester tester,
      List<FocusNode> nodes, {
      required Duration every,
    }) async {
      for (final node in nodes) {
        TvNavigationSound.noteStep();
        node.requestFocus();
        await tester.pump();
        clock += every;
      }
    }

    testWidgets('des pas plus serrés que l’écart minimal ne mitraillent pas',
        (tester) async {
      await TvNavigationSound.initialize();
      final nodes = await pumpNodes(tester);

      // Douze pas en 330 ms : un clic à 0, 90, 180 et 270 ms.
      await steps(tester, nodes, every: const Duration(milliseconds: 30));

      expect(count('move'), 4);
    });

    testWidgets('une flèche maintenue à sa cadence régulée garde chaque clic',
        (tester) async {
      await TvNavigationSound.initialize();
      final nodes = await pumpNodes(tester);

      await steps(tester, nodes, every: const Duration(milliseconds: 110));

      expect(count('move'), nodes.length);
    });

    testWidgets('un pas ne sonne qu’une fois, même si le focus se pose deux fois',
        (tester) async {
      await TvNavigationSound.initialize();
      final nodes = await pumpNodes(tester);

      TvNavigationSound.noteStep();
      nodes[1].requestFocus();
      await tester.pump();
      clock += const Duration(milliseconds: 200);
      nodes[2].requestFocus();
      await tester.pump();

      expect(count('move'), 1);
    });
  });

  group('réglage', () {
    testWidgets('coupé, plus aucun son, et le choix est gardé',
        (tester) async {
      await TvNavigationSound.initialize();
      expect(TvNavigationSound.enabled, isTrue);

      await TvNavigationSound.setEnabled(false);
      final harness = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < 2; i++)
                TvFocusable(
                  autofocus: i == 0,
                  onSelect: () {},
                  child: TvTestTile('card$i'),
                ),
            ],
          ),
        ),
      );
      await harness.press(TraversalDirection.right);

      expect(harness.focusedLabel, 'card1');
      expect(calls, ['prepare']);

      // Au lancement suivant : le réglage est relu, et l'hôte ne charge rien.
      calls.clear();
      TvNavigationSound.resetForTest();
      TvNavigationSound.debugSupported = true;
      await TvNavigationSound.initialize();

      expect(TvNavigationSound.enabled, isFalse);
      expect(calls, isEmpty);

      // Rallumé, l'hôte charge ses sons sans attendre le premier pas.
      await TvNavigationSound.setEnabled(true);
      expect(calls, ['prepare']);
    });

    testWidgets('la ligne des réglages coupe et rallume les sons',
        (tester) async {
      await TvNavigationSound.initialize();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: NavigationSoundTile()),
      ));
      expect(find.text('Sons de navigation'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(TvNavigationSound.enabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Sons de navigation'));
      await tester.pumpAndSettle();

      expect(TvNavigationSound.enabled, isTrue);
    });

    TvNavHarness.forEachEngine((engine) {
      testWidgets('à la télécommande, OK sur la ligne bascule le réglage',
          (tester) async {
        await TvNavigationSound.initialize();
        final harness = await TvNavHarness.pump(
          tester,
          Scaffold(
            body: Column(
              children: [
                TvFocusable(
                  autofocus: true,
                  onSelect: () {},
                  child: const TvTestTile('au-dessus'),
                ),
                const NavigationSoundTile(),
              ],
            ),
          ),
          engine: engine,
        );

        await harness.press(TraversalDirection.down);
        await harness.select();

        expect(TvNavigationSound.enabled, isFalse);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
        // Le pas qui a mené à la ligne a sonné ; le réglage une fois coupé,
        // celui qui la quitte ne sonne plus.
        expect(count('move'), 1);
        await harness.press(TraversalDirection.up);
        expect(count('move'), 1);
      });
    });

    test('la recherche des réglages ne le propose que sur Apple TV', () {
      List<String> hits() {
        const permissions = Permissions();
        final index = buildSettingsSearchIndex(
            settingsCategoriesFor(permissions), permissions);
        return [for (final hit in searchSettings(index, 'clic')) hit.title];
      }

      expect(hits(), contains('Sons de navigation'));

      TvNavigationSound.debugSupported = false;
      expect(hits(), isNot(contains('Sons de navigation')));
    });
  });

  testWidgets('un hôte sans ce canal ne lève rien et n’est plus sollicité',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw MissingPluginException();
    });
    await TvNavigationSound.initialize();
    final harness = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Row(
          children: [
            for (var i = 0; i < 2; i++)
              TvFocusable(
                autofocus: i == 0,
                onSelect: () {},
                child: TvTestTile('card$i'),
              ),
          ],
        ),
      ),
    );

    await harness.press(TraversalDirection.right);

    expect(harness.focusedLabel, 'card1');
    expect(calls, ['prepare']);
    expect(tester.takeException(), isNull);
  });
}
