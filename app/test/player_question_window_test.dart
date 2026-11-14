import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/player_question_window.dart';
import 'package:onyx/screens/player/widgets/player_status_panels.dart';
import 'package:onyx/screens/player/widgets/still_watching_prompt.dart';
import 'package:onyx/theme/focus_fill.dart';

import 'support/tv_nav_harness.dart';

/// Les questions du lecteur arrivent dans une même fenêtre (ADR-0130) : la
/// réponse attendue est déjà sous la télécommande, et rien ne se répond seul.
void main() {
  testWidgets('« Vous regardez encore ? » : ses deux réponses', (tester) async {
    var continued = 0;
    var left = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StillWatchingPrompt(
          onContinue: () => continued++,
          onLeave: () => left++,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Vous regardez encore ?'), findsOneWidget);
    await tester.tap(find.text('Continuer la lecture'));
    await tester.tap(find.text('Quitter'));
    expect((continued, left), (1, 1));
  });

  testWidgets('la lecture reprise ailleurs nomme l’appareil', (tester) async {
    var resumed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayingElsewhere(
          deviceName: 'Salon',
          busy: false,
          onResume: () => resumed++,
          onBack: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('« Salon »'), findsOneWidget);
    await tester.tap(find.text('Reprendre la lecture ici'));
    expect(resumed, 1);
  });

  testWidgets('une réponse en cours ne se relance pas', (tester) async {
    var resumed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayingElsewhere(
          deviceName: 'Salon',
          busy: true,
          onResume: () => resumed++,
          onBack: () {},
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Reprendre la lecture ici'));
    expect(resumed, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('la fenêtre tient sur un téléphone tenu en largeur',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerQuestionWindow(
          title: 'Une question assez longue pour passer à la ligne ?',
          message: 'Un texte qui explique. ' * 12,
          answers: [
            PlayerQuestionAnswer(label: 'Oui', onPressed: () {}),
            PlayerQuestionAnswer(label: 'Non', onPressed: () {}),
            PlayerQuestionAnswer(label: 'Fermer', onPressed: () {}),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('sur un téléviseur', () {
    TvNavHarness.forEachEngine((engine) {
      Finder lit() => find.byWidgetPredicate((widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == FocusFill.fill);

      String litLabel(WidgetTester tester) => tester
          .widget<Text>(
              find.descendant(of: lit(), matching: find.byType(Text)).first)
          .data!;

      testWidgets(
          'la réponse attendue est sous la télécommande, seule commande '
          'blanche', (tester) async {
        await TvNavHarness.pump(
          tester,
          Scaffold(
            body: StillWatchingPrompt(onContinue: () {}, onLeave: () {}),
          ),
          engine: engine,
        );
        await tester.pumpAndSettle();

        expect(lit(), findsOneWidget);
        expect(litLabel(tester), 'Continuer la lecture');
      });

      testWidgets('Bas passe à la réponse suivante et s’y arrête, OK répond',
          (tester) async {
        var left = 0;
        final nav = await TvNavHarness.pump(
          tester,
          Scaffold(
            body: StillWatchingPrompt(
              onContinue: () {},
              onLeave: () => left++,
            ),
          ),
          engine: engine,
        );
        await tester.pumpAndSettle();

        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(litLabel(tester), 'Quitter');

        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(litLabel(tester), 'Quitter', reason: 'rien sous la fenêtre');

        await nav.select();
        expect(left, 1);
      });
    });
  });
}
