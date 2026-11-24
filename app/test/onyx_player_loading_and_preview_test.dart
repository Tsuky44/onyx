import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_theme.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_controls_layer.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_loading_ring.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_progress_bar.dart';
import 'package:onyx/screens/player/widgets/player_status_panels.dart';

/// Trois retouches vues sur un iPhone (ADR-0140) : la vignette de la barre
/// qui restait après le lever du doigt, le bouton des sous-titres sans piste,
/// l'anneau d'attente posé sous lecture/pause au lieu de sa place.
void main() {
  Future<void> pumpBar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: OnyxProgressBar(
                progress: 0.25,
                buffered: 0.5,
                duration: const Duration(minutes: 40),
                metrics: const OnyxChromeMetrics.handheld(),
                onSeek: (_) {},
                marker: true,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // La bulle du temps visé : « 20:00 » au milieu d'une barre de 40 minutes.
  final aimed = find.text('20:00');

  group('la vignette de la barre', () {
    testWidgets('part avec le doigt qui a glissé', (tester) async {
      await pumpBar(tester);
      final bar = tester.getRect(find.byType(OnyxProgressBar));

      final finger = await tester.startGesture(
        bar.centerLeft + const Offset(100, 0),
        kind: PointerDeviceKind.touch,
      );
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      expect(aimed, findsOneWidget, reason: 'pendant le glissé');

      await finger.up();
      await tester.pump();
      expect(aimed, findsNothing, reason: 'après le lever');
    });

    testWidgets('reste sous une souris qui survole encore', (tester) async {
      await pumpBar(tester);
      final bar = tester.getRect(find.byType(OnyxProgressBar));

      final mouse = await tester.startGesture(
        bar.centerLeft + const Offset(100, 0),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await mouse.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await mouse.up();
      await tester.pump();
      expect(aimed, findsOneWidget);
    });
  });

  Future<void> pumpChrome(
    WidgetTester tester, {
    bool hasSubtitles = true,
    bool isLoading = false,
    bool handheld = true,
    bool isTv = false,
    VoidCallback? onPlayPause,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnyxControlsLayer(
            visible: true,
            handheld: handheld,
            isTv: isTv,
            isPlaying: true,
            isLoading: isLoading,
            position: const Duration(minutes: 5),
            duration: const Duration(minutes: 90),
            buffered: 0.1,
            volume: 70,
            onPlayPause: onPlayPause ?? () {},
            onRewind: () {},
            onForward: () {},
            onSeekFraction: (_) {},
            onVolumeChanged: (_) {},
            onBack: () {},
            onToggleSubtitles: () {},
            hasSubtitles: hasSubtitles,
            onOpenAudio: () {},
            onOpenSettings: () {},
            onToggleFullscreen: () {},
            onOpenInfo: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final subtitles = find.byKey(const ValueKey('onyx-subtitles'));

  group('le bouton des sous-titres', () {
    testWidgets('n’est pas posé sans piste, dans aucun arrangement',
        (tester) async {
      for (final (handheld, isTv) in [(true, false), (false, false), (false, true)]) {
        await pumpChrome(tester,
            hasSubtitles: false, handheld: handheld, isTv: isTv);
        expect(subtitles, findsNothing, reason: 'main $handheld, tv $isTv');
        expect(find.byKey(const ValueKey('onyx-audio')), findsOneWidget);
      }
    });

    testWidgets('est là dès qu’il y a une piste', (tester) async {
      await pumpChrome(tester);
      expect(subtitles, findsOneWidget);
    });
  });

  group('l’anneau d’attente', () {
    testWidgets('prend la place de lecture/pause, qui garde sa cible',
        (tester) async {
      var toggled = 0;
      await pumpChrome(tester, isLoading: true, onPlayPause: () => toggled++);
      await tester.pumpAndSettle();

      final play = find.byKey(const ValueKey('onyx-play-pause'));
      final fade = tester.widget<AnimatedOpacity>(
        find.ancestor(of: play, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(fade.opacity, 0);
      await tester.tap(play, warnIfMissed: false);
      expect(toggled, 1, reason: 'on peut encore mettre en pause');
    });

    testWidgets('son milieu tombe sur celui de lecture/pause', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                PlayerLoadingSpinner(
                  centreAt: OnyxChromeTheme.handheldCentreAt,
                ),
              ],
            ),
          ),
        ),
      );

      final ring = tester.getCenter(find.byType(OnyxLoadingRing));
      expect(ring.dx, closeTo(844 / 2, 0.5));
      expect(ring.dy, closeTo(390 * OnyxChromeTheme.handheldCentreAt, 0.5));
    });

    // Vu sur une Apple TV : deux anneaux, un par attente, qui se relayaient
    // en repartant de zéro et claquaient à l'écran sans fondu.
    testWidgets('un seul anneau paraît et s’efface en fondu, sans repartir de '
        'zéro', (tester) async {
      Widget host({required bool visible}) => MaterialApp(
            home: Scaffold(
              body: Stack(children: [PlayerLoadingSpinner(visible: visible)]),
            ),
          );
      double opacity() => tester
          .widget<FadeTransition>(find
              .ancestor(
                of: find.byType(OnyxLoadingRing),
                matching: find.byType(FadeTransition),
              )
              .first)
          .opacity
          .value;
      double turn() => (tester
              .widget<CustomPaint>(find.descendant(
                of: find.byType(OnyxLoadingRing),
                matching: find.byType(CustomPaint),
              ))
              .painter! as OnyxLoadingRingPainter)
          .turn;

      await tester.pumpWidget(host(visible: false));
      expect(find.byType(OnyxLoadingRing), findsNothing,
          reason: 'sans attente, aucune animation ne tourne');

      await tester.pumpWidget(host(visible: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), inExclusiveRange(0, 1), reason: 'il paraît en fondu');
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(), 1);

      // L'attente cesse puis reprend aussitôt (une recherche après un
      // tampon) : l'anneau est encore là et continue son tour.
      final state = tester.state(find.byType(OnyxLoadingRing));
      await tester.pumpWidget(host(visible: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), inExclusiveRange(0, 1), reason: 'il s’efface en fondu');
      final before = turn();
      await tester.pumpWidget(host(visible: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.state(find.byType(OnyxLoadingRing)), same(state));
      expect(turn(), isNot(before));

      await tester.pumpWidget(host(visible: false));
      await tester.pumpAndSettle();
      expect(find.byType(OnyxLoadingRing), findsNothing);
    });

    testWidgets('ne tourne pas sous « réduire les animations »',
        (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: OnyxLoadingRing()),
          ),
        ),
      );
      final painter = tester
          .widget<CustomPaint>(find.descendant(
            of: find.byType(OnyxLoadingRing),
            matching: find.byType(CustomPaint),
          ))
          .painter! as OnyxLoadingRingPainter;
      await tester.pump(const Duration(milliseconds: 300));
      final later = tester
          .widget<CustomPaint>(find.descendant(
            of: find.byType(OnyxLoadingRing),
            matching: find.byType(CustomPaint),
          ))
          .painter! as OnyxLoadingRingPainter;
      expect(later.turn, painter.turn);
    });

    testWidgets('tourne ailleurs', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: OnyxLoadingRing()),
      ));
      double turn() => (tester
              .widget<CustomPaint>(find.descendant(
                of: find.byType(OnyxLoadingRing),
                matching: find.byType(CustomPaint),
              ))
              .painter! as OnyxLoadingRingPainter)
          .turn;
      final first = turn();
      await tester.pump(const Duration(milliseconds: 300));
      expect(turn(), isNot(first));
    });
  });
}
