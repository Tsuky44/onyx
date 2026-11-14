import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/player_key_routing.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_menu_section.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_tabs.dart';
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

    /// Lance le lecteur depuis la carte, chrome levé par Haut, télécommande
    /// sur la barre de lecture : c'est elle qui répond à OK, à gauche et à
    /// droite, comme dans le lecteur d'Apple (ADR-0124).
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
      // Haut : le chrome monte, la télécommande sur la barre.
      await nav.press(up);
      await tester.pumpAndSettle();
      expect(focused(tester), 'barre');
    }

    /// Les boutons ronds, de gauche à droite (le banc joue une série) : un
    /// par réglage, entre les deux épisodes voisins (ADR-0130).
    const buttons = [
      'Épisode précédent',
      'Sous-titres',
      'Pistes audio',
      'Qualité',
      'Vitesse de lecture',
      'Format d’image',
      'Minuterie de veille',
      'Épisode suivant',
    ];

    /// De la barre au bouton des pistes audio, le troisième de sa rangée.
    Future<void> toAudio(WidgetTester tester) async {
      await nav.press(up);
      for (var i = 0; i < buttons.length; i++) {
        await nav.press(left);
      }
      for (var i = 0; i < 2; i++) {
        await nav.press(right);
      }
      await tester.pumpAndSettle();
      expect(focused(tester), 'Pistes audio');
    }

    Future<void> press(WidgetTester tester, TraversalDirection direction,
        {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await nav.press(direction);
      }
      await tester.pumpAndSettle();
    }

    group('carte du chrome', () {
      testWidgets('depuis la barre : Haut les boutons ronds, Bas les onglets',
          (tester) async {
        await open(tester);
        await press(tester, up);
        expect(buttons, contains(focused(tester)));
        await press(tester, down);
        expect(focused(tester), 'barre');
        // Le premier onglet, et son volet s'ouvre.
        await press(tester, down);
        expect(focused(tester), 'Infos');
        expect(player(tester).openTab, OnyxTab.info);
        await press(tester, up);
        expect(focused(tester), 'barre');
        expect(player(tester).openTab, isNull,
            reason: 'quitter les onglets ferme le volet');
      });

      testWidgets('les boutons ronds se parcourent, leurs bords sont des murs',
          (tester) async {
        await open(tester);
        await press(tester, up);
        await press(tester, left, times: buttons.length);
        expect(focused(tester), buttons.first);
        await press(tester, up);
        expect(focused(tester), buttons.first,
            reason: 'rien au-dessus du chrome');
        for (final button in buttons.skip(1)) {
          await press(tester, right);
          expect(focused(tester), button);
        }
        await press(tester, right);
        expect(focused(tester), buttons.last);
      });

      testWidgets('Bas depuis un bouton rond ramène à la barre',
          (tester) async {
        await open(tester);
        await press(tester, up);
        await press(tester, left, times: buttons.length);
        await press(tester, down);
        expect(focused(tester), 'barre');

        await press(tester, up);
        await press(tester, right, times: buttons.length);
        expect(focused(tester), buttons.last);
        await press(tester, down);
        expect(focused(tester), 'barre');
      });

      testWidgets('la barre cherche à gauche et à droite', (tester) async {
        await open(tester);
        final before = player(tester).seeks;
        await press(tester, left);
        await press(tester, right);
        expect(player(tester).seeks, before + 2);
        expect(focused(tester), 'barre');
      });

      testWidgets(
          'les onglets se parcourent, Bas entre dans le volet, et sous le '
          'volet Bas est un mur', (tester) async {
        await open(tester);
        await press(tester, down);
        expect(focused(tester), 'Infos');
        await press(tester, right);
        expect(focused(tester), 'Épisodes');
        expect(player(tester).openTab, OnyxTab.episodes);
        await press(tester, right, times: 3);
        expect(focused(tester), 'Stats');

        await press(tester, down);
        expect(focused(tester), 'Dans Stats');
        await press(tester, down);
        expect(focused(tester), 'Dans Stats');
        expect(player(tester).openTab, OnyxTab.stats);

        // Remonter rend l'onglet du volet, pas le plus proche.
        await press(tester, up);
        expect(focused(tester), 'Stats');
      });

      testWidgets(
          '« Passer l’intro » est sa propre rangée, au-dessus des '
          'boutons ronds', (tester) async {
        await open(tester, skipIntro: true);
        await press(tester, up);
        expect(buttons, contains(focused(tester)));
        await press(tester, up);
        final pill = focused(tester);
        expect(buttons, isNot(contains(pill)));
        expect(pill, isNot('barre'));
        await press(tester, down);
        expect(buttons, contains(focused(tester)));
        await press(tester, down);
        expect(focused(tester), 'barre');
      });
    });

    group('invariants', () {
      testWidgets('chrome affiché ⇒ une commande est entourée, à chaque pas',
          (tester) async {
        await open(tester);
        const walk = [
          up,
          right,
          right,
          right,
          down,
          down,
          left,
          up,
          left,
          left,
          left,
          up,
          up,
          down,
          down,
          down
        ];
        for (final direction in walk) {
          await press(tester, direction);
          expect(player(tester).chromeVisible, isTrue);
          expect(player(tester).browsingControls, isTrue,
              reason: 'après $direction, le focus a quitté les commandes '
                  '(${focused(tester)})');
        }
      });

      testWidgets(
          'chrome masqué, les flèches vont à routePlayerKey, '
          'et dpad ne bouge rien', (tester) async {
        await open(tester, raise: false);
        await nav.press(left);
        expect(actions.single, isA<PlayerKeyRemoteSeek>());
        expect((actions.single as PlayerKeyRemoteSeek).direction, -1);
        await tester.pumpAndSettle();
        // Le chrome monte sur la barre : la recherche continue de là.
        expect(focused(tester), 'barre');
      });

      testWidgets(
          'chrome masqué, une rafale n’est pas regroupée : chaque '
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
        // Comme `PlayerScreen` : chrome masqué, la barre de lecture suit le
        // doigt, et l'écouteur le dit au pavé (ADR-0116).
        TvTouchpad.addMoveListener((move) => true);

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

      testWidgets(
          'un Retour défait une couche : menu, volet, chrome, lecteur',
          (tester) async {
        await open(tester);
        await toAudio(tester);

        // Le menu de ce seul réglage, sur la piste jouée, et son bouton reste
        // allumé.
        await nav.select();
        await tester.pumpAndSettle();
        expect(focused(tester), 'English');
        expect(player(tester).openMenu, OnyxMenuSection.audio);

        Future<void> back() async {
          await nav.back();
          // Sous dpad, l'Apple TV peut livrer Menu en touche *et* en
          // `popRoute` : la seconde moitié est le même appui.
          if (engine == TvNavEngine.dpad) await nav.popRoute();
          await tester.pumpAndSettle();
        }

        await back();
        expect(find.text('English'), findsNothing,
            reason: 'pas d’index où remonter : le menu se ferme');
        expect(player(tester).openMenu, isNull);
        expect(player(tester).chromeVisible, isTrue);
        // dpad rend la télécommande au bouton qui a ouvert le menu ;
        // l'ancien système la pose sur la barre de lecture.
        expect(focused(tester),
            engine == TvNavEngine.dpad ? 'Pistes audio' : 'barre');

        // Le volet des onglets est une couche : Retour le ferme et rend la
        // barre, chrome toujours affiché.
        if (engine == TvNavEngine.dpad) await press(tester, down);
        await press(tester, down);
        expect(player(tester).openTab, OnyxTab.info);
        await back();
        expect(player(tester).openTab, isNull);
        expect(player(tester).chromeVisible, isTrue);
        expect(focused(tester), 'barre');

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
        await toAudio(tester);
        await nav.select();
        await tester.pumpAndSettle();
        for (final direction in [up, up, up, right, right, down]) {
          await press(tester, direction);
          expect(find.text('English'), findsOneWidget);
          expect(player(tester).popups.isOpen, isTrue);
          expect(player(tester).player.hasPrimaryFocus, isFalse);
          expect(player(tester).browsingControls, isFalse,
              reason: 'le focus est sorti du menu (${focused(tester)})');
        }
      });
    });
  });
}
