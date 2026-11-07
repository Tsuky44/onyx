import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/player_key_routing.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/tv_touchpad.dart';
import 'package:onyx/tv/touchpad_motion.dart';

import 'support/player_remote_bench.dart';
import 'support/tv_nav_harness.dart';

/// La carte de navigation du chrome télé du lecteur (ADR-0006, ADR-0008,
/// ADR-0110 phase 7), et ses invariants, dans les deux systèmes :
///
/// - chrome affiché ⇒ une commande est entourée ;
/// - chrome masqué, les flèches vont à `routePlayerKey`, avant dpad et sans
///   le portail des flèches (C4) ;
/// - un Retour défait une couche, et une seule.
///
/// Le lecteur est celui du banc (`PlayerRemoteBench`), les widgets du chrome
/// et du menu sont les vrais.
void main() {
  const up = TraversalDirection.up;
  const down = TraversalDirection.down;
  const left = TraversalDirection.left;
  const right = TraversalDirection.right;

  TvNavHarness.forEachEngine((engine) {
    late TvNavHarness nav;
    late List<PlayerKeyAction> actions;
    late FocusNode card;

    PlayerRemoteBenchState player(WidgetTester tester) =>
        tester.state<PlayerRemoteBenchState>(find.byType(PlayerRemoteBench));

    /// Ce que la télécommande tient : le libellé de la commande (son
    /// infobulle), « barre » pour la barre de progression, « lecteur » pour
    /// le lecteur lui-même, « carte » pour l'écran d'avant.
    String focused(WidgetTester tester) {
      final node = FocusManager.instance.primaryFocus;
      if (node == null) return 'rien';
      if (identical(node, card)) return 'carte';
      final bench = find.byType(PlayerRemoteBench).evaluate().isEmpty
          ? null
          : player(tester);
      if (bench != null && identical(node, bench.player)) return 'lecteur';
      if (bench != null && identical(node, bench.progress)) return 'barre';
      final tooltip =
          node.context?.findAncestorWidgetOfExactType<Tooltip>()?.message;
      return tooltip ?? focusedLabelOf(node) ?? node.toString();
    }

    /// Lance le lecteur depuis la carte, chrome levé par OK, télécommande
    /// sur lecture/pause.
    Future<void> open(
      WidgetTester tester, {
      bool skipIntro = false,
      bool raise = true,
    }) async {
      actions = <PlayerKeyAction>[];
      card = FocusNode(debugLabel: 'carte');
      addTearDown(card.dispose);
      nav = await TvNavHarness.pump(
        tester,
        PlayerBenchHome(
          card: card,
          player: () => PlayerRemoteBench(
            skipIntro: skipIntro,
            actions: actions,
          ),
        ),
        engine: engine,
      );
      card.requestFocus();
      await TvNavHarness.settle(tester);
      await nav.select();
      await tester.pumpAndSettle();
      expect(focused(tester), 'lecteur');
      if (!raise) return;
      // Haut : le chrome monte, la télécommande sur lecture/pause.
      await nav.press(up);
      await tester.pumpAndSettle();
      expect(focused(tester), 'Pause');
    }

    Future<void> press(WidgetTester tester, TraversalDirection direction,
        {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await nav.press(direction);
      }
      await tester.pumpAndSettle();
    }

    group('carte du chrome', () {
      testWidgets('depuis lecture/pause : Bas la barre, Haut la rangée du haut',
          (tester) async {
        await open(tester);
        await press(tester, down);
        expect(focused(tester), 'barre');
        await press(tester, up);
        expect(focused(tester), 'Pause');
        await press(tester, up);
        expect(
          ['Retour', 'Épisodes suivants', 'Sous-titres', 'Pistes audio',
              'Réglages'],
          contains(focused(tester)),
        );
      });

      testWidgets('la rangée du milieu se parcourt, ses bords sont des murs',
          (tester) async {
        await open(tester);
        await press(tester, left, times: 5);
        expect(focused(tester), 'Épisode précédent');
        await press(tester, right, times: 6);
        expect(focused(tester), 'Épisode suivant');
      });

      testWidgets('la rangée du haut : de Retour à Réglages, murs aux deux bouts',
          (tester) async {
        await open(tester);
        await press(tester, up);
        await press(tester, left, times: 6);
        expect(focused(tester), 'Retour');
        await press(tester, up);
        expect(focused(tester), 'Retour', reason: 'rien au-dessus du chrome');
        await press(tester, right, times: 8);
        expect(focused(tester), 'Réglages');
      });

      testWidgets(
          'Bas depuis Réglages ou Retour mène à lecture/pause, pas à la barre',
          (tester) async {
        // La barre, pleine largeur, est dans le faisceau de Réglages, et la
        // lecture au centre ne l'est pas : la géométrie seule y sautait la
        // rangée du milieu.
        await open(tester);
        await press(tester, up);
        await press(tester, right, times: 8);
        expect(focused(tester), 'Réglages');
        await press(tester, down);
        expect(focused(tester), 'Pause');

        await press(tester, up);
        await press(tester, left, times: 8);
        expect(focused(tester), 'Retour');
        await press(tester, down);
        expect(focused(tester), 'Pause');
      });

      testWidgets('la barre cherche à gauche et à droite, Bas est un mur',
          (tester) async {
        await open(tester);
        await press(tester, down);
        final before = player(tester).seeks;
        await press(tester, left);
        await press(tester, right);
        expect(player(tester).seeks, before + 2);
        expect(focused(tester), 'barre');
        await press(tester, down);
        expect(focused(tester), 'barre');
      });

      testWidgets('« Passer l’intro » est sa propre rangée, entre la lecture '
          'et la barre', (tester) async {
        await open(tester, skipIntro: true);
        await press(tester, down);
        final pill = focused(tester);
        expect(pill, isNot('barre'));
        expect(pill, isNot('Pause'));
        await press(tester, down);
        expect(focused(tester), 'barre');
        await press(tester, up);
        expect(focused(tester), pill);
        await press(tester, up);
        expect(focused(tester), 'Pause');
      });
    });

    group('invariants', () {
      testWidgets('chrome affiché ⇒ une commande est entourée, à chaque pas',
          (tester) async {
        await open(tester);
        const walk = [up, right, right, right, down, down, left, up, left,
            left, left, up, up, down, down, down];
        for (final direction in walk) {
          await press(tester, direction);
          expect(player(tester).chromeVisible, isTrue);
          expect(player(tester).browsingControls, isTrue,
              reason: 'après $direction, le focus a quitté les commandes '
                  '(${focused(tester)})');
        }
      });

      testWidgets('chrome masqué, les flèches vont à routePlayerKey, '
          'et dpad ne bouge rien', (tester) async {
        await open(tester, raise: false);
        await nav.press(left);
        expect(actions.single, isA<PlayerKeyRemoteSeek>());
        expect((actions.single as PlayerKeyRemoteSeek).direction, -1);
        await tester.pumpAndSettle();
        // Le chrome monte sur la barre : la recherche continue de là.
        expect(focused(tester), 'barre');
      });

      testWidgets('chrome masqué, une rafale n’est pas regroupée : chaque '
          'flèche est un pas de recherche', (tester) async {
        await open(tester, raise: false);
        TvNavHarness.sendBurst([
          for (var i = 0; i < 3; i++)
            (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
        ]);
        await tester.pumpAndSettle();
        expect(actions.whereType<PlayerKeyRemoteSeek>(), hasLength(3));
        expect(player(tester).seeks, 3);
      });

      testWidgets('chrome masqué, un glissé vif ne lance pas d’élan',
          (tester) async {
        var clock = Duration.zero;
        TvTouchpad.debugReset();
        TvTouchpad.debugClock = () => clock;
        addTearDown(TvTouchpad.debugReset);
        await open(tester, raise: false);

        TvTouchpad.handleTouch(TouchpadPhase.began, 0, 0);
        for (var i = 1; i <= 7; i++) {
          clock += const Duration(milliseconds: 16);
          TvTouchpad.handleTouch(TouchpadPhase.moved, 0.3 * i, 0);
        }
        TvTouchpad.handleTouch(TouchpadPhase.ended, 2.1, 0);
        expect(TvTouchpad.isGliding, isFalse,
            reason: 'le lecteur suit le doigt lui-même');
        await tester.pump(const Duration(milliseconds: 500));
        expect(focused(tester), 'lecteur');
      });

      testWidgets('un Retour défait une couche : section, menu, chrome, lecteur',
          (tester) async {
        await open(tester);
        await press(tester, up);
        await press(tester, right, times: 8);
        expect(focused(tester), 'Réglages');

        await nav.select();
        await tester.pumpAndSettle();
        expect(find.text('Vitesse de lecture'), findsOneWidget);
        await nav.select();
        await tester.pumpAndSettle();
        expect(focused(tester), 'English');

        Future<void> back() async {
          await nav.back();
          // Sous dpad, l'Apple TV peut livrer Menu en touche *et* en
          // `popRoute` : la seconde moitié est le même appui.
          if (engine == TvNavEngine.dpad) await nav.popRoute();
          await tester.pumpAndSettle();
        }

        await back();
        expect(find.text('Vitesse de lecture'), findsOneWidget,
            reason: 'la section remonte à l’index, le menu reste');
        expect(focused(tester), 'Audio');

        await back();
        expect(find.text('Vitesse de lecture'), findsNothing);
        expect(player(tester).chromeVisible, isTrue);
        // dpad rend la télécommande au bouton qui a ouvert le menu ;
        // l'ancien système la pose sur lecture/pause.
        expect(focused(tester),
            engine == TvNavEngine.dpad ? 'Réglages' : 'Pause');

        await back();
        expect(player(tester).chromeVisible, isFalse);
        expect(focused(tester), 'lecteur');

        await back();
        expect(find.byType(PlayerRemoteBench), findsNothing);
        expect(focused(tester), 'carte',
            reason: 'la sortie du lecteur rend le focus à la carte d’origine');
      });

      testWidgets('le menu piège les flèches', (tester) async {
        await open(tester);
        await press(tester, up);
        await press(tester, right, times: 8);
        await nav.select();
        await tester.pumpAndSettle();
        for (final direction in [up, up, up, right, right, down]) {
          await press(tester, direction);
          expect(find.text('Vitesse de lecture'), findsOneWidget);
          expect(player(tester).popups.isOpen, isTrue);
          expect(player(tester).player.hasPrimaryFocus, isFalse);
          expect(player(tester).browsingControls, isFalse,
              reason: 'le focus est sorti du menu (${focused(tester)})');
        }
      });
    });
  });
}
