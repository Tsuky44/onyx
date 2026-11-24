import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_theme.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_controls_layer.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_loading_ring.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_progress_bar.dart';
import 'package:onyx/screens/player/widgets/player_status_panels.dart';
import 'package:onyx/theme/app_motion.dart';
import 'package:onyx/theme/lite_mode.dart';
import 'package:onyx/tv/tv_mode.dart';

/// Trois retouches vues sur un iPhone (ADR-0140) : la vignette de la barre
/// qui restait après le lever du doigt, le bouton des sous-titres sans piste,
/// l'anneau d'attente posé sous lecture/pause au lieu de sa place. Et ce que
/// l'Apple TV y a ajouté : un anneau qui ne s'arrête jamais.
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

    testWidgets('sur un téléviseur, il se pose à l’échelle du lecteur',
        (tester) async {
      // Une Apple TV annonce 1920 points : mis en page sur 1280, l'anneau y
      // est une fois et demie plus grand.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [PlayerLoadingSpinner(isTv: true)]),
          ),
        ),
      );

      final ring = tester.getRect(find.byType(OnyxLoadingRing));
      expect(ring.center, const Offset(960, 540));
      expect(ring.width, closeTo(OnyxLoadingRing.defaultSize * 1.5, 0.01));
    });

  });

  group('ce que le lecteur attend', () {
    bool awaits({
      bool hasFirstFrame = true,
      bool startupStalled = false,
      bool isSwitchingQuality = false,
      bool isBuffering = false,
    }) =>
        playerAwaitsPicture(
          hasFirstFrame: hasFirstFrame,
          startupStalled: startupStalled,
          isSwitchingQuality: isSwitchingQuality,
          isBuffering: isBuffering,
        );

    test('sa première image, puis ce que le moteur charge encore', () {
      expect(awaits(hasFirstFrame: false), isTrue);
      expect(awaits(), isFalse, reason: 'un film qui joue n’attend rien');
      expect(awaits(isSwitchingQuality: true), isTrue);
      expect(awaits(isBuffering: true), isTrue);
    });

    test('une première image n’est pas un film qui joue', () {
      // Le moteur d'Apple annonce sa première image avant que la lecture ne
      // parte : tant qu'il charge, l'anneau reste, sans attendre la fin du
      // démarrage.
      expect(awaits(hasFirstFrame: true, isBuffering: true), isTrue);
    });

    test('pas d’anneau sur le panneau d’un démarrage au délai dépassé', () {
      expect(
        awaits(hasFirstFrame: false, startupStalled: true, isBuffering: true),
        isFalse,
        reason: 'le moteur se dit encore « en tampon » sous le panneau',
      );
    });
  });

  // L'anneau ne s'arrête jamais (ADR du 2026-11-23, qui contredit le point 3
  // de l'ADR-0140) : immobile, il se lisait comme un plantage sur une Apple TV
  // HD, que son matériel met d'office en mode léger.
  group('l’anneau d’attente vit', () {
    final drawing = find.descendant(
      of: find.byType(OnyxLoadingRing),
      matching: find.byType(CustomPaint),
    );

    OnyxLoadingRingPainter painterOf(WidgetTester tester) =>
        tester.widget<CustomPaint>(drawing).painter! as OnyxLoadingRingPainter;

    Future<void> pumpRing(
      WidgetTester tester, {
      bool lite = false,
      bool tv = false,
      bool reducedMotion = false,
    }) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: TvScope(
              isTv: tv,
              child: LiteScope(
                isLite: lite,
                child: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Center(child: OnyxLoadingRing()),
                ),
              ),
            ),
          ),
        );

    /// Refuse ce qu'une puce A8 ne tient pas à chaque image : un flou, un
    /// calque hors écran. Faux : `paints` dit lui-même quel appel a déplu.
    bool cheap(Symbol method, List<dynamic> arguments) {
      if (method == #saveLayer) return false;
      return !arguments.any((a) => a is Paint && a.maskFilter != null);
    }

    testWidgets('il tourne', (tester) async {
      await pumpRing(tester);
      final first = painterOf(tester).turn;
      await tester.pump(const Duration(milliseconds: 300));
      expect(painterOf(tester).turn, isNot(first));
    });

    testWidgets(
        'sur un téléviseur en mode léger (une Apple TV HD), il tourne '
        'encore, sans flou', (tester) async {
      // La chaîne qui le figeait : le matériel décide du mode léger, et le
      // mode léger arrêtait l'anneau.
      final lite = LiteMode.isModestHardware(
        isAndroid: false,
        isIOS: false,
        isTvOS: true,
        isWebOS: false,
        totalMemoryMb: 1990,
        isLowRamDevice: false,
        model: 'AppleTV5,3',
      );
      expect(lite, isTrue);

      await pumpRing(tester, lite: lite, tv: true);
      final first = painterOf(tester).turn;
      await tester.pump(const Duration(milliseconds: 300));

      expect(painterOf(tester).turn, isNot(first));
      expect(painterOf(tester).soft, isFalse);
      expect(tester.renderObject(drawing), paints..everything(cheap));
    });

    testWidgets('hors mode léger, son ombre est floue mais sans calque',
        (tester) async {
      await pumpRing(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(painterOf(tester).soft, isTrue);
      expect(
        tester.renderObject(drawing),
        paints..everything((method, arguments) => method != #saveLayer),
      );
      expect(
        tester.renderObject(drawing),
        paints
          ..something((method, arguments) =>
              arguments.any((a) => a is Paint && a.maskFilter != null)),
      );
    });

    testWidgets(
        'sous « réduire les animations », il respire au lieu de tourner',
        (tester) async {
      for (final lite in [false, true]) {
        await pumpRing(tester, reducedMotion: true, lite: lite);
        // Son arrivée passée, il ne reste que la respiration.
        await tester.pump(AppMotion.standard);
        final first = painterOf(tester).opacity;
        await tester.pump(const Duration(milliseconds: 500));
        final later = painterOf(tester).opacity;

        expect(painterOf(tester).turn, 0, reason: 'il ne tourne pas');
        expect(later, isNot(first), reason: 'il n’est pas immobile');
        expect(later, greaterThanOrEqualTo(OnyxLoadingRingPainter.breathFloor),
            reason: 'il ne disparaît pas');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('il arrive en fondu, par l’alpha de ses traits',
        (tester) async {
      await pumpRing(tester);
      expect(painterOf(tester).opacity, 0);
      expect(tester.renderObject(drawing), paintsNothing);

      await tester.pump(AppMotion.standard);
      await tester.pump();
      expect(painterOf(tester).opacity, 1);
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(FadeTransition), findsNothing);
    });

    // Vu sur une Apple TV : démonté net à la fin de chaque attente, l'anneau
    // claquait à l'écran et repartait du haut à la suivante.
    testWidgets('il part en fondu, et garde son tour si l’attente reprend',
        (tester) async {
      Widget host({required bool visible}) => MaterialApp(
            home: Scaffold(
              body: Stack(children: [PlayerLoadingSpinner(visible: visible)]),
            ),
          );

      await tester.pumpWidget(host(visible: false));
      expect(find.byType(OnyxLoadingRing), findsNothing,
          reason: 'sans attente, aucune animation ne tourne');

      await tester.pumpWidget(host(visible: true));
      await tester.pump(AppMotion.standard);
      await tester.pump();
      expect(painterOf(tester).opacity, 1);

      // L'attente cesse : il s'efface, toujours en mouvement.
      final state = tester.state(find.byType(OnyxLoadingRing));
      await tester.pumpWidget(host(visible: false));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(painterOf(tester).opacity, inExclusiveRange(0, 1));
      final turn = painterOf(tester).turn;

      // Elle reprend avant la fin du fondu : le même anneau, sur son tour.
      await tester.pumpWidget(host(visible: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.state(find.byType(OnyxLoadingRing)), same(state));
      expect(painterOf(tester).turn, greaterThan(turn));
      await tester.pump(AppMotion.standard);
      expect(painterOf(tester).opacity, 1);

      // Elle cesse pour de bon : une fois effacé, il est démonté.
      await tester.pumpWidget(host(visible: false));
      // Une image après la fin du fondu : c'est là que l'animation se dit
      // terminée.
      await tester.pump(AppMotion.standard);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(find.byType(OnyxLoadingRing), findsNothing);
    });

    testWidgets('chaque image ne repeint que lui, sans rien reconstruire',
        (tester) async {
      await pumpRing(tester, lite: true, tv: true);
      final painter = painterOf(tester);
      final layer = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(
          of: find.byType(OnyxLoadingRing),
          matching: find.byType(RepaintBoundary),
        ),
      );
      layer.debugResetMetrics();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(painterOf(tester), same(painter),
          reason: 'le dessin écoute l’animation : aucune reconstruction');
      expect(layer.debugAsymmetricPaintCount, 5,
          reason: 'il se repeint à chaque image, dans son propre calque');
      expect(layer.debugSymmetricPaintCount, 0,
          reason: 'sans faire repeindre ce qui l’entoure');
    });
  });
}
