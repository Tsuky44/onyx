import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/playback/mpv_fast_rendering.dart';
import 'package:onyx/screens/player/playback_profile.dart';
import 'package:onyx/theme/app_motion.dart';
import 'package:onyx/theme/frame_budget_watch.dart';
import 'package:onyx/theme/lite_mode.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/tv/tv_ui_scale.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le mode léger (ADR-0086) : qui le reçoit, ce qu'il retire, et ce qu'il ne
/// touche pas — le fichier reste lu en Direct Play.
void main() {
  group('le matériel modeste passe en mode léger', () {
    bool modest({
      bool android = false,
      bool ios = false,
      bool tvos = false,
      bool webos = false,
      int memory = 0,
      bool lowRam = false,
      String model = '',
      int cpus = 0,
    }) =>
        LiteMode.isModestHardware(
          isAndroid: android,
          isIOS: ios,
          isTvOS: tvos,
          isWebOS: webos,
          totalMemoryMb: memory,
          isLowRamDevice: lowRam,
          model: model,
          processorCount: cpus,
        );

    test('une Apple TV HD, pas une Apple TV 4K', () {
      expect(modest(tvos: true, memory: 1990, model: 'AppleTV5,3'), isTrue);
      expect(modest(tvos: true, memory: 2900, model: 'AppleTV6,2'), isFalse);
      expect(modest(tvos: true, memory: 3800, model: 'AppleTV14,1'), isFalse);
    });

    test('une clé Android à 2 Go ou qui se dit low-RAM', () {
      expect(modest(android: true, memory: 1900), isTrue);
      expect(modest(android: true, memory: 8000, lowRam: true), isTrue);
      expect(modest(android: true, memory: 4096), isFalse);
    });

    test('une mémoire inconnue ne décide rien', () {
      expect(modest(android: true), isFalse);
      expect(modest(tvos: true), isFalse);
    });

    test('un téléviseur LG, toujours', () {
      expect(modest(webos: true), isTrue);
    });

    test(
        'un ordinateur à deux processeurs ou moins, pas un ordinateur '
        'ordinaire (ADR-0101)', () {
      expect(modest(cpus: 2), isTrue);
      expect(modest(cpus: 1), isTrue);
      expect(modest(cpus: 4), isFalse);
      expect(modest(cpus: 8), isFalse);
      expect(modest(memory: 1024), isFalse,
          reason: 'sur ordinateur, la mémoire ne décide pas');
    });

    test('un navigateur ou un nombre inconnu ne décide rien', () {
      expect(modest(cpus: 0), isFalse);
    });
  });

  group('les saccades mesurées', () {
    const budget = Duration(microseconds: 16667);
    const fast = Duration(milliseconds: 6);
    const slow = Duration(milliseconds: 40);

    test('une fenêtre où un tiers des images est lent conclut', () {
      final watch = FrameBudgetWatch(frameBudget: budget, window: 30);
      var verdict = false;
      for (var i = 0; i < 30; i++) {
        verdict = watch.add(build: fast, raster: i % 3 == 0 ? slow : fast);
      }
      expect(verdict, isTrue);
    });

    test('une saccade isolée ne suffit pas', () {
      final watch = FrameBudgetWatch(frameBudget: budget, window: 30);
      var verdicts = 0;
      for (var i = 0; i < 90; i++) {
        if (watch.add(build: i == 5 ? slow : fast, raster: fast)) verdicts++;
      }
      expect(verdicts, 0);
    });

    test(
        'une image qui dépasse à peine son budget n’est pas lente '
        '(une Apple TV 4K était jugée lente)', () {
      final watch = FrameBudgetWatch(frameBudget: budget, window: 30);
      var verdict = false;
      for (var i = 0; i < 30; i++) {
        verdict = watch.add(
            build: fast, raster: const Duration(milliseconds: 20));
      }
      expect(verdict, isFalse);
    });

    test('le budget suit la fréquence de l’écran, le cinéma se juge à 60 Hz',
        () {
      expect(FrameBudgetWatch.budgetFor(60).inMicroseconds, 16667);
      expect(FrameBudgetWatch.budgetFor(120).inMicroseconds, 8333);
      expect(FrameBudgetWatch.budgetFor(24).inMicroseconds, 16667);
      expect(FrameBudgetWatch.budgetFor(null).inMicroseconds, 16667);
    });
  });

  group('la lecture reste en Direct Play, dessinée au plus simple', () {
    test('le profil léger garde ses tampons et allège le dessin', () {
      final lite = PlaybackProfile.constrained.withFastRendering();
      expect(lite.fastRendering, isTrue);
      expect(lite.allowHdrComputePeak, isFalse);
      expect(lite.demuxerMaxBytes, PlaybackProfile.constrained.demuxerMaxBytes);
      expect(lite.backBufferMs, PlaybackProfile.constrained.backBufferMs);
    });

    test('mpv passe au bilinéaire et lâche une image plutôt que ralentir', () {
      final options =
          mpvFastRenderingOptions(PlaybackProfile.desktop.withFastRendering());
      expect(options['scale'], 'bilinear');
      expect(options['dscale'], 'bilinear');
      expect(options['framedrop'], 'decoder+vo');
      expect(options['deband'], 'no');
      expect(options.keys, isNot(contains('hwdec')),
          reason: 'le décodage matériel reste le choix de l’utilisateur');
    });

    test('un profil ordinaire ne touche à aucune option', () {
      expect(mpvFastRenderingOptions(PlaybackProfile.desktop), isEmpty);
    });
  });

  group('l’interface', () {
    Widget host({required bool lite, required Widget child}) => MaterialApp(
          home: LiteScope(isLite: lite, child: Scaffold(body: child)),
        );

    testWidgets('le verre ne floute plus en mode léger', (tester) async {
      const panel = Stack(children: [
        GlassSurface(child: Text('a')),
        GlassBlur(sigma: 20, child: Text('b')),
      ]);
      await tester.pumpWidget(host(lite: false, child: panel));
      expect(find.byType(BackdropFilter), findsNWidgets(2));

      await tester.pumpWidget(host(lite: true, child: panel));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('le mouvement géométrique tombe à zéro, le fondu reste',
        (tester) async {
      late Duration move;
      late Duration fade;
      await tester.pumpWidget(host(
        lite: true,
        child: Builder(builder: (context) {
          move = AppMotion.move(context);
          fade = AppMotion.fade(context);
          return const SizedBox();
        }),
      ));
      expect(move, Duration.zero);
      expect(fade, AppMotion.standard);
    });

    test('la télé prend la transition d’Onyx, pas le glissé du système', () {
      const builder = TvScaledPageTransitionsBuilder();
      expect(builder.transitionDuration, AppMotion.emphasis);
      expect(builder.reverseTransitionDuration, AppMotion.standard);
    });
  });

  group('le choix', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LiteMode.resetForTest();
    });
    tearDown(LiteMode.resetForTest);

    test('des saccades proposent le mode léger sans l’activer (ADR-0141)',
        () {
      LiteMode.noteSustainedJank();
      expect(LiteMode.suggestion.value, isTrue);
      expect(LiteMode.isLite, isFalse);
      expect(LiteMode.reason, LiteModeReason.none);
    });

    test('accepter passe sur « Activé »', () async {
      LiteMode.noteSustainedJank();
      await LiteMode.acceptSuggestion();
      expect(LiteMode.isLite, isTrue);
      expect(LiteMode.preference, LiteModePreference.on);
      expect(LiteMode.reason, LiteModeReason.chosen);
      expect(LiteMode.suggestion.value, isFalse);
    });

    test('un refus est gardé, « Auto » choisi de nouveau l’oublie', () async {
      LiteMode.noteSustainedJank();
      await LiteMode.declineSuggestion();
      expect(LiteMode.isLite, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('lite_mode_suggestion_declined'), isTrue);

      LiteMode.noteSustainedJank();
      expect(LiteMode.suggestion.value, isFalse,
          reason: 'la question ne revient pas après un non');

      await LiteMode.setPreference(LiteModePreference.auto);
      LiteMode.noteSustainedJank();
      expect(LiteMode.suggestion.value, isTrue);
    });

    test('« Désactivé » ne demande rien', () async {
      await LiteMode.setPreference(LiteModePreference.off);
      LiteMode.noteSustainedJank();
      expect(LiteMode.suggestion.value, isFalse);
    });

    test('l’ancienne mesure, qui imposait le mode léger, est effacée',
        () async {
      SharedPreferences.setMockInitialValues(
          {'lite_mode_measured_slow': true});
      await LiteMode.initialize();
      expect(LiteMode.isLite, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('lite_mode_measured_slow'), isFalse);
      expect(TvMode.isTv, isFalse);
    });
  });
}
