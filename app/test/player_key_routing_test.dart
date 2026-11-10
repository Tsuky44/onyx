import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/screens/player/player_key_routing.dart';
import 'package:onyx/screens/player/player_shortcuts.dart';

import 'support/tv_nav_harness.dart';

KeyEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyEvent _repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  // Les raccourcis lisent les modificateurs sur le clavier du binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  PlayerKeyAction route(
    KeyEvent event, {
    bool isTv = false,
    bool browsingControls = false,
    bool chromeVisible = false,
    bool skipIntroShown = false,
  }) =>
      routePlayerKey(
        event,
        isTv: isTv,
        browsingControls: browsingControls,
        chromeVisible: chromeVisible,
        skipIntroShown: skipIntroShown,
      );

  group('sur un téléviseur', () {
    test('gauche et droite cherchent tout de suite, sans réveiller le chrome',
        () {
      final left = route(_down(LogicalKeyboardKey.arrowLeft), isTv: true);
      final right = route(_repeat(LogicalKeyboardKey.arrowRight), isTv: true);
      expect((left as PlayerKeyRemoteSeek).direction, -1);
      expect((right as PlayerKeyRemoteSeek).direction, 1);
    });

    test('haut et bas montent le chrome, une seule fois par appui', () {
      expect(route(_down(LogicalKeyboardKey.arrowUp), isTv: true),
          isA<PlayerKeyEnterControlBar>());
      // Touche tenue : le réveil ne doit pas s'empiler quarante fois.
      expect(route(_repeat(LogicalKeyboardKey.arrowDown), isTv: true),
          isA<PlayerKeyConsumed>());
    });

    test('OK ne met jamais en pause : il pose la télécommande sur le chrome',
        () {
      expect(route(_down(LogicalKeyboardKey.select), isTv: true),
          isA<PlayerKeyEnterControlBar>());
    });

    test('OK presse « Passer l’intro » quand il est seul à l’écran', () {
      expect(
        route(_down(LogicalKeyboardKey.select),
            isTv: true, skipIntroShown: true),
        isA<PlayerKeySkipIntro>(),
      );
      // Chrome visible : le bouton y est atteignable, c'est lui qui répond.
      expect(
        route(_down(LogicalKeyboardKey.select),
            isTv: true, skipIntroShown: true, chromeVisible: true),
        isA<PlayerKeyEnterControlBar>(),
      );
    });

    test('sur la barre de contrôle, les touches reviennent aux boutons', () {
      expect(
        route(_down(LogicalKeyboardKey.select),
            isTv: true, browsingControls: true),
        isA<PlayerKeyIgnored>(),
      );
      expect(
        route(_down(LogicalKeyboardKey.arrowLeft),
            isTv: true, browsingControls: true),
        isA<PlayerKeyIgnored>(),
      );
    });

    test('les lettres ne déclenchent aucun raccourci', () {
      expect(route(_down(LogicalKeyboardKey.keyK), isTv: true),
          isA<PlayerKeyIgnored>());
    });
  });

  group('au clavier', () {
    test('les flèches cherchent de dix secondes et règlent le volume', () {
      expect(
          (route(_down(LogicalKeyboardKey.arrowLeft)) as PlayerKeySeek).seconds,
          -10);
      expect(
          (route(_down(LogicalKeyboardKey.arrowRight)) as PlayerKeySeek)
              .seconds,
          10);
      expect(
          (route(_down(LogicalKeyboardKey.arrowUp)) as PlayerKeyVolume).delta,
          5);
      expect(
          (route(_down(LogicalKeyboardKey.arrowDown)) as PlayerKeyVolume).delta,
          -5);
    });

    test('espace et entrée basculent la lecture, sans se répéter', () {
      expect(route(_down(LogicalKeyboardKey.space)),
          isA<PlayerKeyTogglePlayback>());
      expect(route(_down(LogicalKeyboardKey.enter)),
          isA<PlayerKeyTogglePlayback>());
      expect(
          route(_repeat(LogicalKeyboardKey.space)), isA<PlayerKeyConsumed>());
      expect(
          route(_repeat(LogicalKeyboardKey.enter)), isA<PlayerKeyConsumed>());
    });

    test('une lettre connue devient son raccourci', () {
      final action = route(_down(LogicalKeyboardKey.keyM));
      expect((action as PlayerKeyShortcut).match.shortcut,
          PlayerShortcut.toggleMute);
    });
  });

  test('Échap demande un retour, sur tous les écrans', () {
    expect(route(_down(LogicalKeyboardKey.escape)), isA<PlayerKeyBack>());
    expect(route(_down(LogicalKeyboardKey.escape), isTv: true),
        isA<PlayerKeyBack>());
  });

  test('une touche inconnue continue son chemin', () {
    expect(route(_down(LogicalKeyboardKey.f9)), isA<PlayerKeyIgnored>());
  });

  // Les mêmes décisions, vues d'un écran monté : la touche du lecteur passe
  // avant dpad (constat C4), dans les deux systèmes de navigation.
  TvNavHarness.forEachEngine((engine) {
    group('vu par un écran monté', () {
      late List<PlayerKeyAction> actions;
      late FocusNode player;

      Future<TvNavHarness> mount(WidgetTester tester) async {
        actions = <PlayerKeyAction>[];
        player = FocusNode(debugLabel: 'lecteur');
        addTearDown(player.dispose);
        final nav = await TvNavHarness.pump(
          tester,
          Scaffold(
            body: Focus(
              focusNode: player,
              autofocus: true,
              onKeyEvent: (node, event) {
                final action = routePlayerKey(
                  event,
                  isTv: true,
                  browsingControls: false,
                  chromeVisible: false,
                  skipIntroShown: false,
                );
                // Le relâchement est rendu consommé comme l'appui, mais ne
                // compte pas pour une action de plus.
                if (event is KeyDownEvent) actions.add(action);
                return action is PlayerKeyIgnored
                    ? KeyEventResult.ignored
                    : KeyEventResult.handled;
              },
              child: const SizedBox.expand(),
            ),
          ),
          engine: engine,
        );
        expect(player.hasPrimaryFocus, isTrue);
        return nav;
      }

      testWidgets(
          'gauche et droite cherchent tout de suite, sans réveiller le chrome',
          (tester) async {
        final nav = await mount(tester);

        await nav.press(TraversalDirection.left);
        expect(actions.whereType<PlayerKeyRemoteSeek>().single.direction, -1);
        expect(player.hasPrimaryFocus, isTrue);

        actions.clear();
        await nav.press(TraversalDirection.right);
        expect(actions.whereType<PlayerKeyRemoteSeek>().single.direction, 1);
        expect(player.hasPrimaryFocus, isTrue);
      });

      testWidgets('haut et bas montent le chrome, une seule fois par appui',
          (tester) async {
        final nav = await mount(tester);

        await nav.press(TraversalDirection.up);
        expect(actions.whereType<PlayerKeyEnterControlBar>(), hasLength(1));
        expect(player.hasPrimaryFocus, isTrue);

        actions.clear();
        await nav.press(TraversalDirection.down);
        expect(actions.whereType<PlayerKeyEnterControlBar>(), hasLength(1));
        expect(player.hasPrimaryFocus, isTrue);
      });

      testWidgets(
          'OK ne met jamais en pause : il pose la télécommande sur le chrome',
          (tester) async {
        final nav = await mount(tester);

        await nav.select();

        expect(actions.whereType<PlayerKeyEnterControlBar>(), hasLength(1));
        expect(actions.whereType<PlayerKeyTogglePlayback>(), isEmpty);
      });
    });
  });
}
