import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/player_key_routing.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_loading_ring.dart';
import 'package:onyx/screens/player/widgets/player_status_panels.dart';
import 'package:onyx/screens/player/widgets/player_wait_cancel.dart';
import 'package:onyx/theme/focus_fill.dart';

import 'support/player_remote_bench.dart';
import 'support/tv_nav_harness.dart';

/// « Annuler », sous l'anneau d'un lancement qui se fait attendre (ADR du
/// 2026-11-23) : il n'arrive qu'après un délai, sous la télécommande d'un
/// téléviseur quand elle ne tient rien, et Retour quitte d'un seul appui.
void main() {
  const up = TraversalDirection.up;
  final cancel = find.text('Annuler');

  /// Le temps que la capsule arrive, puis celui de la lire.
  Future<void> waitForOffer(WidgetTester tester) async {
    await tester.pump(PlayerWaitCancel.defaultDelay);
    await TvNavHarness.settle(tester);
  }

  Future<void> waitUntilArmed(WidgetTester tester) =>
      tester.pump(PlayerWaitCancel.armDelay);

  group('l’offre', () {
    late int cancelled;

    Future<void> pumpWait(WidgetTester tester) async {
      cancelled = 0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                PlayerLoadingSpinner(
                  cancel: PlayerWaitCancel(onCancel: () => cancelled++),
                ),
              ],
            ),
          ),
        ),
      );
    }

    double shown(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(of: cancel, matching: find.byType(AnimatedOpacity))
              .last,
        )
        .opacity;

    testWidgets(
        'n’arrive qu’après le délai : un lancement ordinaire ne '
        'propose rien', (tester) async {
      await pumpWait(tester);
      await tester.pump(
          PlayerWaitCancel.defaultDelay - const Duration(milliseconds: 100));

      expect(shown(tester), 0);
      await tester.tap(cancel, warnIfMissed: false);
      expect(cancelled, 0, reason: 'invisible, elle ne prend aucun toucher');

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(shown(tester), 1);
    });

    testWidgets('ne répond qu’une fois lisible', (tester) async {
      await pumpWait(tester);
      await waitForOffer(tester);

      await tester.tap(cancel);
      expect(cancelled, 0,
          reason: 'un appui parti avant qu’elle soit lisible n’était pas '
              'pour elle');

      await waitUntilArmed(tester);
      await tester.tap(cancel);
      expect(cancelled, 1);
    });

    testWidgets('se pose sous l’anneau, au milieu, sans le toucher',
        (tester) async {
      await pumpWait(tester);
      await waitForOffer(tester);

      final ring = tester.getRect(find.byType(OnyxLoadingRing));
      final capsule = tester.getRect(
        find.ancestor(of: cancel, matching: find.byType(AnimatedContainer)),
      );
      expect(ring.center, const Offset(640, 360));
      expect(capsule.top, ring.bottom + PlayerLoadingSpinner.cancelGap);
      expect(capsule.center.dx, closeTo(640, 0.5));
    });

    testWidgets('sans offre, la couche ne prend aucun toucher', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped++,
                  ),
                ),
                const PlayerLoadingSpinner(),
              ],
            ),
          ),
        ),
      );

      // Sur l'anneau même : attendre est le moment où l'on veut mettre en
      // pause ou s'en aller, et rien ne doit s'interposer.
      await tester.tap(find.byType(OnyxLoadingRing), warnIfMissed: false);
      expect(tapped, 1);
    });
  });

  group('sur un téléviseur', () {
    TvNavHarness.forEachEngine((engine) {
      late TvNavHarness nav;
      late FocusNode card;

      PlayerRemoteBenchState player(WidgetTester tester) =>
          tester.state<PlayerRemoteBenchState>(find.byType(PlayerRemoteBench));

      /// Ce que la télécommande tient.
      String focused(WidgetTester tester) {
        final node = FocusManager.instance.primaryFocus;
        if (node == null) return 'rien';
        if (identical(node, card)) return 'carte';
        if (find.byType(PlayerRemoteBench).evaluate().isEmpty) {
          return node.toString();
        }
        final bench = player(tester);
        if (identical(node, bench.player)) return 'lecteur';
        if (identical(node, bench.progress)) return 'barre';
        if (identical(node, bench.waitCancel)) return 'Annuler';
        return focusedLabelOf(node) ?? node.toString();
      }

      /// La capsule blanche à l'encre noire : la seule commande allumée.
      Finder lit() => find.byWidgetPredicate((widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == FocusFill.fill);

      /// Lance un film qui attend sa première image. L'anneau ne s'arrête
      /// jamais : aucun `pumpAndSettle` tant qu'il est à l'écran.
      Future<void> launch(WidgetTester tester) async {
        card = FocusNode(debugLabel: 'carte');
        addTearDown(card.dispose);
        nav = await TvNavHarness.pump(
          tester,
          PlayerBenchHome(
            card: card,
            player: () => PlayerRemoteBench(
              waiting: true,
              actions: <PlayerKeyAction>[],
            ),
          ),
          engine: engine,
        );
        card.requestFocus();
        await TvNavHarness.settle(tester);
        await nav.select();
        await tester.pump(const Duration(seconds: 1));
        await TvNavHarness.settle(tester);
        expect(focused(tester), 'lecteur');
      }

      /// Le lecteur est sorti, et sa route avec lui.
      Future<void> expectLeft(WidgetTester tester) async {
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerRemoteBench), findsNothing);
        expect(focused(tester), 'carte',
            reason: 'la sortie rend le focus à la carte d’où l’on venait');
      }

      testWidgets(
          '« Annuler » est atteignable au D-pad : il arrive sous la '
          'télécommande garée, et OK annule', (tester) async {
        await launch(tester);
        expect(lit(), findsNothing, reason: 'rien avant le délai');

        await waitForOffer(tester);
        expect(focused(tester), 'Annuler');
        expect(lit(), findsOneWidget,
            reason: 'ce que fera OK se voit : la capsule est allumée');

        await waitUntilArmed(tester);
        await nav.select();
        await expectLeft(tester);
      });

      testWidgets('Retour pendant l’attente quitte, d’un seul appui',
          (tester) async {
        await launch(tester);

        // Avant l'offre : le Menu de l'Apple TV arrive en `popRoute`.
        await nav.popRoute();
        await expectLeft(tester);
      });

      testWidgets(
          'Retour quitte encore d’un seul appui quand « Annuler » tient la '
          'télécommande', (tester) async {
        await launch(tester);
        await waitForOffer(tester);
        expect(focused(tester), 'Annuler');

        // « Annuler » n'est pas la barre de commandes : Retour ne « range »
        // rien, il s'en va.
        await nav.popRoute();
        await expectLeft(tester);
      });

      testWidgets(
          'la télécommande occupée dans le chrome y reste ; Retour range la '
          'barre et la rend à « Annuler »', (tester) async {
        await launch(tester);
        await nav.press(up);
        await TvNavHarness.settle(tester);
        expect(focused(tester), 'barre');

        await waitForOffer(tester);
        expect(focused(tester), 'barre',
            reason: 'l’offre ne prend pas le focus à une commande');
        expect(cancel, findsOneWidget);

        await nav.popRoute();
        await TvNavHarness.settle(tester);
        expect(player(tester).chromeVisible, isFalse);
        expect(focused(tester), 'Annuler');

        await nav.popRoute();
        await expectLeft(tester);
      });

      testWidgets('depuis « Annuler », Haut lève le chrome comme lecteur garé',
          (tester) async {
        await launch(tester);
        await waitForOffer(tester);
        expect(focused(tester), 'Annuler');

        await nav.press(up);
        await TvNavHarness.settle(tester);
        expect(player(tester).chromeVisible, isTrue);
        expect(focused(tester), 'barre');
      });

      testWidgets(
          'à la première image, « Annuler » s’efface et la télécommande '
          'passe au chrome', (tester) async {
        await launch(tester);
        await waitForOffer(tester);
        expect(focused(tester), 'Annuler');

        player(tester).firstFrame();
        await tester.pumpAndSettle();

        expect(cancel, findsNothing);
        expect(find.byType(OnyxLoadingRing), findsNothing);
        // Un focus perdu avec la capsule laisserait le lecteur sourd à la
        // télécommande.
        expect(focused(tester), 'barre');
      });
    });
  });
}
