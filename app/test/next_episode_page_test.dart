import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/hooks/use_episode_navigation.dart';
import 'package:onyx/screens/player/widgets/next_episode_page.dart';
import 'package:onyx/screens/player/widgets/player_video_stage.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// La page de l'épisode suivant, au générique (ADR-0130) : elle présente
/// l'épisode qui vient, montre le compte à rebours du lecteur sans le tenir
/// elle-même, et « Plus tard » la range pour de bon.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomeMediaItem next() => HomeMediaItem(
        media: Media(
          id: 44,
          type: MediaType.episode,
          title: 'L’Île absente',
          duration: 3060,
          seasonNumber: 1,
          episodeNumber: 4,
          isAvailable: true,
          createdAt: DateTime(2026),
        ),
        currentPositionSeconds: 0,
        duration: 3060,
        isFinished: false,
        showId: 7,
        showTitle: 'Phare Nord',
      );

  Widget page({
    int? countdown = 5,
    bool frozen = false,
    VoidCallback? onPlayNext,
    VoidCallback? onLater,
  }) =>
      Provider<ApiClient>.value(
        value: ApiClient(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              NextEpisodePage(
                nextEpisode: next(),
                currentLabel: 'S1, E3 · Le Gardien',
                countdownSeconds: countdown,
                frozen: frozen,
                onPlayNext: onPlayNext ?? () {},
                onLater: onLater ?? () {},
              ),
            ],
          ),
        ),
      );

  /// L'anneau du compte à rebours, par ce qu'il annonce.
  Finder ring(String label) => find.byWidgetPredicate((widget) =>
      widget is Semantics && (widget.properties.label ?? '').startsWith(label));

  void setScreen(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  testWidgets('elle nomme l’épisode qui vient, à droite de l’image rangée',
      (tester) async {
    setScreen(tester, const Size(1280, 720));
    await tester.pumpWidget(MaterialApp(home: page()));
    await tester.pump();

    expect(find.text('ÉPISODE SUIVANT'), findsOneWidget);
    expect(find.text('L’Île absente'), findsOneWidget);
    expect(find.text('Phare Nord · S01E04 · 51min'), findsOneWidget);
    expect(find.text('S1, E3 · Le Gardien'), findsOneWidget);

    final video = PlayerVideoStage.frameFor(
      const Size(1280, 720),
      scale: PlayerVideoStage.nextEpisodeScale,
      alignment: PlayerVideoStage.nextEpisodeAlignment,
    );
    // L'image du générique tombe là où la maquette la pose : marge de 53, sous
    // le haut de l'écran.
    expect(video.left, closeTo(53, 1.5));
    expect(video.top, closeTo(96, 1.5));
    expect(tester.getRect(find.text('L’Île absente')).left,
        greaterThan(video.right));
    expect(tester.getRect(find.text('S1, E3 · Le Gardien')).top,
        greaterThanOrEqualTo(video.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('l’anneau porte les secondes du lecteur ; gelé, une pause',
      (tester) async {
    setScreen(tester, const Size(1280, 720));
    await tester.pumpWidget(MaterialApp(home: page(countdown: 3)));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(ring('Lecture dans 3 s'), findsOneWidget);

    await tester
        .pumpWidget(MaterialApp(home: page(countdown: 3, frozen: true)));
    await tester.pump();
    expect(find.text('3'), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(ring('Lecture automatique en pause'), findsOneWidget);
  });

  testWidgets(
      'sans compte à rebours (la minuterie s’arrête après cet épisode), pas '
      'd’anneau, mais toujours les deux réponses', (tester) async {
    setScreen(tester, const Size(1280, 720));
    await tester.pumpWidget(MaterialApp(home: page(countdown: null)));
    await tester.pump();

    expect(ring('Lecture'), findsNothing);
    expect(find.text('Lire'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });

  testWidgets('« Lire » enchaîne, « Plus tard » range', (tester) async {
    setScreen(tester, const Size(1280, 720));
    var played = 0;
    var later = 0;
    await tester.pumpWidget(MaterialApp(
      home: page(onPlayNext: () => played++, onLater: () => later++),
    ));
    await tester.pump();

    await tester.tap(find.text('Lire'));
    await tester.tap(find.text('Plus tard'));
    expect((played, later), (1, 1));
  });

  testWidgets('elle garde sa forme sur un téléphone tenu en largeur',
      (tester) async {
    setScreen(tester, const Size(740, 360));
    await tester.pumpWidget(MaterialApp(home: page()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final later = tester.getRect(find.text('Plus tard'));
    expect(later.right, lessThanOrEqualTo(740));
    expect(later.bottom, lessThanOrEqualTo(360));
  });

  group('sur un téléviseur', () {
    TvNavHarness.forEachEngine((engine) {
      testWidgets(
          'la télécommande arrive sur « Lire », seule commande blanche, et '
          'droite mène à « Plus tard »', (tester) async {
        var later = 0;
        final nav = await TvNavHarness.pump(
          tester,
          page(onLater: () => later++),
          engine: engine,
        );
        await tester.pumpAndSettle();

        final lit = find.byWidgetPredicate((widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == FocusFill.fill);
        expect(lit, findsOneWidget);
        expect(find.descendant(of: lit, matching: find.text('Lire')),
            findsOneWidget);

        await nav.press(TraversalDirection.right);
        await tester.pumpAndSettle();
        await nav.select();
        expect(later, 1);
      });
    });
  });

  group('« Plus tard »', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    EpisodeNavigationController controller({VoidCallback? onAutoPlay}) =>
        EpisodeNavigationController(
          apiClient: ApiClient(),
          episodeId: 1,
          initialTimestamps: EpisodeTimestamps(
            introStart: 0,
            introEnd: 0,
            outroStart: 2900,
            outroEnd: 3000,
          ),
          onAutoPlay: onAutoPlay,
        )..nextEpisode = next();

    testWidgets('la page arrive au générique, avec son compte à rebours',
        (tester) async {
      var played = 0;
      final nav = controller(onAutoPlay: () => played++);
      addTearDown(nav.dispose);

      nav.checkPosition(100, mediaDurationSeconds: 3000);
      expect(nav.showNextEpisodePage, isFalse);

      nav.checkPosition(2910, mediaDurationSeconds: 3000);
      expect(nav.showNextEpisodePage, isTrue);
      expect(nav.outroAutoPlayActive, isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(played, 1);
    });

    testWidgets(
        'elle se range pour de bon : la position suivante, toujours au '
        'générique, ne la relève pas et n’enchaîne rien', (tester) async {
      var played = 0;
      final nav = controller(onAutoPlay: () => played++);
      addTearDown(nav.dispose);
      nav.checkPosition(2910, mediaDurationSeconds: 3000);

      nav.deferNextEpisode();
      expect(nav.showNextEpisodePage, isFalse);
      expect(nav.outroAutoPlayActive, isFalse);

      for (final second in [2911, 2912, 2950]) {
        nav.checkPosition(second, mediaDurationSeconds: 3000);
      }
      await tester.pump(const Duration(seconds: 10));

      expect(nav.showNextEpisodePage, isFalse);
      expect(played, 0);
      // Le bouton « Épisode suivant » du chrome, lui, reste.
      expect(nav.nextEpisode, isNotNull);
    });
  });
}
