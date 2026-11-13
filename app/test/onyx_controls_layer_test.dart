import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_brightness_slider.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_buttons.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_theme.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_controls_layer.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_progress_bar.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/widgets/global/app_slider.dart';

import 'support/tv_nav_harness.dart';

/// Mounts the chrome at a given viewport width.
Future<void> pumpChrome(
  WidgetTester tester, {
  required double width,
  double height = 700,
  VoidCallback? onSkipNext,
  VoidCallback? onSkipPrevious,
  VoidCallback? onOpenEpisodes,
  VoidCallback? onSkipIntro,
  double volume = 70,
  bool showVolume = true,
  double scale = 1,
  List<Rect> cutouts = const [],
  double? brightness,
  ValueChanged<double>? onBrightnessChanged,
  bool isPlaying = true,
  bool visible = true,
  bool isTv = false,
  FocusNode? playPauseFocusNode,
  FocusNode? progressFocusNode,
  VoidCallback? onBack,
  VoidCallback? onRewind,
  VoidCallback? onForward,
  VoidCallback? onPlayPause,
  VoidCallback? onLockScreen,
  VoidCallback? onOpenWatchParty,
  String? overview,
  String? logoUrl,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: OnyxControlsLayer(
          visible: visible,
          isPlaying: isPlaying,
          position: const Duration(minutes: 42),
          duration: const Duration(hours: 2),
          buffered: 0.5,
          title: 'Avatar : La Voie de l’eau',
          overline: '2022',
          volume: volume,
          onPlayPause: onPlayPause ?? () {},
          onRewind: onRewind ?? () {},
          onForward: onForward ?? () {},
          onSeekFraction: (_) {},
          onVolumeChanged: (_) {},
          showVolume: showVolume,
          cutouts: cutouts,
          scale: scale,
          brightness: brightness,
          onBrightnessChanged: onBrightnessChanged ?? (_) {},
          onBack: onBack ?? () {},
          onToggleSubtitles: () {},
          onOpenAudio: () {},
          onCycleSpeed: () {},
          onOpenSettings: () {},
          onToggleFullscreen: () {},
          onLockScreen: onLockScreen,
          onSkipNext: onSkipNext,
          onSkipPrevious: onSkipPrevious,
          onOpenEpisodes: onOpenEpisodes,
          onSkipIntro: onSkipIntro,
          onOpenWatchParty: onOpenWatchParty,
          overview: overview,
          logoUrl: logoUrl,
          isTv: isTv,
          playPauseFocusNode: playPauseFocusNode,
          progressFocusNode: progressFocusNode,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Monte le chrome télé sous le banc commun ([TvNavHarness]), sur sa surface de
/// 1920 × 1080, avec le système de navigation [engine]. Le reste est celui de
/// [pumpChrome].
Future<TvNavHarness> pumpTvChrome(
  WidgetTester tester,
  TvNavEngine engine, {
  FocusNode? playPauseFocusNode,
  FocusNode? progressFocusNode,
  VoidCallback? onBack,
  VoidCallback? onRewind,
  VoidCallback? onSkipNext,
  VoidCallback? onPlayPause,
  VoidCallback? onOpenEpisodes,
}) {
  return TvNavHarness.pump(
    tester,
    Scaffold(
      backgroundColor: Colors.black,
      body: OnyxControlsLayer(
        visible: true,
        isPlaying: true,
        position: const Duration(minutes: 42),
        duration: const Duration(hours: 2),
        buffered: 0.5,
        title: 'Avatar : La Voie de l’eau',
        overline: '2022',
        volume: 70,
        onPlayPause: onPlayPause ?? () {},
        onRewind: onRewind ?? () {},
        onForward: () {},
        onSeekFraction: (_) {},
        onVolumeChanged: (_) {},
        showVolume: true,
        cutouts: const [],
        scale: 1,
        brightness: null,
        onBrightnessChanged: (_) {},
        onBack: onBack ?? () {},
        onToggleSubtitles: () {},
        onOpenAudio: () {},
        onCycleSpeed: () {},
        onOpenSettings: () {},
        onToggleFullscreen: () {},
        onSkipNext: onSkipNext,
        onOpenEpisodes: onOpenEpisodes,
        isTv: true,
        playPauseFocusNode: playPauseFocusNode,
        progressFocusNode: progressFocusNode,
      ),
    ),
    engine: engine,
  );
}

void main() {
  group('le verrou d’écran n’existe que là où un doigt touche l’image', () {
    testWidgets('le bouton verrouille quand le lecteur le propose',
        (tester) async {
      var locked = 0;
      await pumpChrome(
        tester,
        width: 400,
        showVolume: false,
        onLockScreen: () => locked++,
      );

      await tester.tap(find.byKey(const ValueKey('onyx-lock')));
      expect(locked, 1);
    });

    testWidgets('sans rappel, aucun bouton', (tester) async {
      await pumpChrome(tester, width: 1280);
      expect(find.byKey(const ValueKey('onyx-lock')), findsNothing);
    });

    testWidgets('jamais sur une télévision', (tester) async {
      await pumpChrome(tester, width: 960, isTv: true, onLockScreen: () {});
      expect(find.byKey(const ValueKey('onyx-lock')), findsNothing);
    });
  });

  group('the chrome carries the agreed control set', () {
    testWidgets('every permanent control is present at desktop width',
        (tester) async {
      await pumpChrome(tester, width: 1280);

      for (final icon in [
        Icons.arrow_back_ios_new_rounded,
        Icons.volume_up_rounded,
        Icons.closed_caption_rounded,
        Icons.graphic_eq_rounded,
        Icons.speed_rounded,
        Icons.settings_rounded,
        Icons.fullscreen_rounded,
        Icons.replay_10_rounded,
        Icons.pause_rounded,
        Icons.forward_10_rounded,
      ]) {
        expect(find.byIcon(icon), findsOneWidget, reason: '$icon missing');
      }
    });

    testWidgets('the removed text links are nowhere in the chrome',
        (tester) async {
      await pumpChrome(tester, width: 1280);

      expect(find.text('Info'), findsNothing);
      expect(find.text('Chapitres'), findsNothing);
      expect(find.text('Distribution et équipe'), findsNothing);
    });

    testWidgets('no cast or picture-in-picture control', (tester) async {
      await pumpChrome(tester, width: 1280);

      expect(find.byIcon(Icons.cast), findsNothing);
      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
    });

    testWidgets('shows the title block, both lines', (tester) async {
      await pumpChrome(tester, width: 1280);

      expect(find.text('2022'), findsOneWidget);
      // Once in the title block; the top bar falls back to the same text when
      // there is no logo.
      expect(find.text('Avatar : La Voie de l’eau'), findsWidgets);
    });

    testWidgets(
        'times read as elapsed on the left, remaining + end on the right',
        (tester) async {
      await pumpChrome(tester, width: 1280);

      expect(find.text('42:00'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data?.startsWith('-01:18:00  /  ') ?? false),
        ),
        findsOneWidget,
      );
    });
  });

  group('conditional controls only appear when they can act', () {
    testWidgets('no next-episode button on a movie', (tester) async {
      await pumpChrome(tester, width: 1280);
      expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    });

    testWidgets('next-episode button on a series', (tester) async {
      await pumpChrome(tester, width: 1280, onSkipNext: () {});
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('no previous-episode button on a movie', (tester) async {
      await pumpChrome(tester, width: 1280);
      expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
    });

    testWidgets('previous-episode button when there is one before',
        (tester) async {
      var back = 0;
      await pumpChrome(tester, width: 1280, onSkipPrevious: () => back++);

      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      expect(back, 1);
    });

    testWidgets('no episode-list button on a movie', (tester) async {
      await pumpChrome(tester, width: 1280);
      expect(find.byIcon(Icons.playlist_play_rounded), findsNothing);
    });

    testWidgets('episode-list button on a series, and it fires',
        (tester) async {
      var opened = 0;
      await pumpChrome(tester, width: 1280, onOpenEpisodes: () => opened++);

      expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      expect(opened, 1);
    });

    testWidgets('no skip-intro pill outside an intro chapter', (tester) async {
      await pumpChrome(tester, width: 1280);
      expect(find.text('Passer l’intro'), findsNothing);
    });

    testWidgets('skip-intro pill during an intro chapter', (tester) async {
      await pumpChrome(tester, width: 1280, onSkipIntro: () {});
      expect(find.text('Passer l’intro'), findsOneWidget);
    });

    testWidgets('the skip-intro pill outlives the hidden chrome',
        (tester) async {
      // A user who is not moving the mouse must still be offered the skip:
      // the intro ends whether or not the chrome is up.
      var skipped = 0;
      await pumpChrome(
        tester,
        width: 1280,
        visible: false,
        onSkipIntro: () => skipped++,
      );
      await tester.pumpAndSettle();

      expect(find.text('Passer l’intro'), findsOneWidget);
      await tester.tap(find.text('Passer l’intro'));
      expect(skipped, 1);
    });
  });

  group('the mute button reflects and toggles the level', () {
    testWidgets('shows the muted icon at zero volume', (tester) async {
      await pumpChrome(tester, width: 1280, volume: 0);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('shows the low icon below half', (tester) async {
      await pumpChrome(tester, width: 1280, volume: 20);
      expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
    });
  });

  group('both arrangements stay usable', () {
    testWidgets('nothing overflows at phone width', (tester) async {
      await pumpChrome(tester,
          width: 375,
          onSkipNext: () {},
          onSkipPrevious: () {},
          onOpenEpisodes: () {},
          onSkipIntro: () {});
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing overflows at desktop width', (tester) async {
      await pumpChrome(tester,
          width: 1280,
          onSkipNext: () {},
          onSkipPrevious: () {},
          onOpenEpisodes: () {},
          onSkipIntro: () {});
      expect(tester.takeException(), isNull);
    });

    testWidgets('the volume slider gives way to the mute button when narrow',
        (tester) async {
      await pumpChrome(tester, width: 375);
      expect(find.byType(AppSlider), findsNothing);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('the volume slider is permanent when there is room',
        (tester) async {
      await pumpChrome(tester, width: 1280);
      expect(find.byType(AppSlider), findsOneWidget);
    });

    testWidgets('compact keeps touch targets at 44px', (tester) async {
      // The whole reason for a second arrangement: a scaled-down single
      // layout would put these well under the usable size.
      const compact = OnyxChromeMetrics.compact();
      expect(compact.hitSize, greaterThanOrEqualTo(44));
    });

    testWidgets('the utility cluster survives both arrangements',
        (tester) async {
      for (final width in [375.0, 1280.0]) {
        await pumpChrome(tester, width: width);
        expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget,
            reason: 'fullscreen lost at $width');
        expect(find.byIcon(Icons.settings_rounded), findsOneWidget,
            reason: 'settings lost at $width');
      }
    });
  });

  testWidgets('hidden chrome stops taking taps', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 700);
    addTearDown(tester.view.reset);

    var backTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnyxControlsLayer(
            visible: false,
            isPlaying: true,
            position: Duration.zero,
            duration: const Duration(hours: 2),
            buffered: 0,
            volume: 70,
            onPlayPause: () {},
            onRewind: () {},
            onForward: () {},
            onSeekFraction: (_) {},
            onVolumeChanged: (_) {},
            onBack: () => backTaps++,
            onToggleSubtitles: () {},
            onOpenAudio: () {},
            onCycleSpeed: () {},
            onOpenSettings: () {},
            onToggleFullscreen: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded),
        warnIfMissed: false);
    expect(backTaps, 0);
  });

  group('the brightness bar', () {
    testWidgets('is left out when the screen backlight is not ours to drive',
        (tester) async {
      // Desktop, television, browser: `brightness` arrives null and the bar
      // must not be there at all rather than sit inert on the edge.
      await pumpChrome(tester, width: 1280);

      expect(find.byType(OnyxBrightnessSlider), findsNothing);
    });

    testWidgets('takes the band between the two bars, on the right edge',
        (tester) async {
      await pumpChrome(tester, width: 420, brightness: 0.5);

      final bar = find.byType(OnyxBrightnessSlider);
      expect(bar, findsOneWidget);

      final rect = tester.getRect(bar);
      expect(rect.right, greaterThan(420 - 60));
      // Below the top bar, which is measured rather than guessed at: the
      // control starts where the bar above it ends.
      final back =
          tester.getRect(find.byIcon(Icons.arrow_back_ios_new_rounded));
      expect(rect.top, greaterThanOrEqualTo(back.bottom));
    });

    testWidgets('never reaches the buttons it shares an edge with',
        (tester) async {
      // The failure this closes was invisible: where the control overlapped
      // the utilities cluster, those buttons were hit-tested first and took
      // the touches, so the lower part of the bar simply stopped answering
      // while still being drawn.
      await pumpChrome(tester, width: 420, brightness: 0.5);

      final rect = tester.getRect(find.byType(OnyxBrightnessSlider));
      final fullscreen = tester.getRect(find.byIcon(Icons.fullscreen_rounded));

      expect(rect.bottom, lessThanOrEqualTo(fullscreen.top));
    });

    testWidgets('dragging up brightens and dragging down dims', (tester) async {
      final values = <double>[];
      await pumpChrome(
        tester,
        width: 420,
        brightness: 0.5,
        onBrightnessChanged: values.add,
      );

      final bar = find.byType(OnyxBrightnessSlider);
      await tester.drag(bar, const Offset(0, -60));
      await tester.pump();
      expect(values.last, greaterThan(0.5),
          reason: 'up is brighter, the direction the bar itself grows');

      values.clear();
      await tester.drag(bar, const Offset(0, 60));
      await tester.pump();
      expect(values.last, lessThan(0.5));
    });

    testWidgets('still there on a screen too short to be comfortable',
        (tester) async {
      // A 1080p phone at 3x, held sideways: 360 dp of height, of which this
      // chrome's bottom bar takes two thirds. The band left is barely 70 px,
      // and the bar has to live in it — it vanished outright at one point,
      // which is worse than tight.
      await pumpChrome(tester, width: 800, height: 360, brightness: 0.5);

      expect(find.byType(OnyxBrightnessSlider), findsOneWidget);
      final rect = tester.getRect(find.byType(OnyxBrightnessSlider));
      final fullscreen = tester.getRect(find.byIcon(Icons.fullscreen_rounded));
      expect(rect.bottom, lessThanOrEqualTo(fullscreen.top));
    });

    testWidgets('holds still under a camera bubble', (tester) async {
      // The jitter this closes: dodging a bubble used to be able to move a row
      // *down*, which changed its height, which moved the rows around it — and
      // in a bar pinned to the bottom of the screen, that moved the row itself.
      // The next frame measured a different position and asked for a different
      // dodge, so the chrome never settled.
      await pumpChrome(
        tester,
        width: 800,
        height: 360,
        brightness: 0.5,
        cutouts: const [Rect.fromLTWH(0, 120, 40, 80)],
      );

      final bar = tester.getRect(find.byType(OnyxBrightnessSlider));
      final fullscreen = tester.getRect(find.byIcon(Icons.fullscreen_rounded));

      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.getRect(find.byType(OnyxBrightnessSlider)), bar);
      expect(tester.getRect(find.byIcon(Icons.fullscreen_rounded)), fullscreen);
    });

    testWidgets('a finger that lands beside the bar still drives it',
        (tester) async {
      // The point of the catch area: it is much wider than the track, and
      // invisible, so the finger never has to find the 8 px that are drawn.
      final values = <double>[];
      await pumpChrome(
        tester,
        width: 420,
        brightness: 0.5,
        onBrightnessChanged: values.add,
      );

      final rect = tester.getRect(find.byType(OnyxBrightnessSlider));
      await tester.dragFrom(
        Offset(rect.left + 8, rect.center.dy),
        const Offset(0, -60),
      );
      await tester.pump();

      expect(values.last, greaterThan(0.5));
    });

    testWidgets('the catch area reaches past both ends of the bar',
        (tester) async {
      // Both ends, because they have to be even. A finger lands lower than it
      // aims — the pad touches the glass, the tip does the aiming — so a catch
      // area generous above the track and stopping at the icon grabs first
      // time at the top and hardly at all at the bottom.
      final values = <double>[];
      await pumpChrome(
        tester,
        width: 420,
        brightness: 0.5,
        onBrightnessChanged: values.add,
      );
      final rect = tester.getRect(find.byType(OnyxBrightnessSlider));

      await tester.dragFrom(
        Offset(rect.center.dx, rect.bottom - 4),
        const Offset(0, -60),
      );
      await tester.pump();
      expect(values.last, greaterThan(0.5), reason: 'below the icon');

      values.clear();
      await tester.dragFrom(
        Offset(rect.center.dx, rect.top + 4),
        const Offset(0, 60),
      );
      await tester.pump();
      expect(values.last, lessThan(0.5), reason: 'above the track');
    });

    testWidgets('a touch that goes nowhere changes nothing', (tester) async {
      // Landing on the column is not an adjustment. Jumping to the touch made
      // every stray contact something to undo — and it is what a catch area
      // this wide could not afford.
      final values = <double>[];
      await pumpChrome(
        tester,
        width: 420,
        brightness: 0.5,
        onBrightnessChanged: values.add,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(OnyxBrightnessSlider)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(values, isEmpty);
    });

    testWidgets('a drag past either end stays inside 0..1', (tester) async {
      final values = <double>[];
      await pumpChrome(
        tester,
        width: 420,
        brightness: 0.5,
        onBrightnessChanged: values.add,
      );

      final bar = find.byType(OnyxBrightnessSlider);
      await tester.drag(bar, const Offset(0, -600));
      await tester.pump();
      await tester.drag(bar, const Offset(0, 600));
      await tester.pump();

      expect(values, isNotEmpty);
      for (final v in values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    testWidgets('hides with the rest of the chrome', (tester) async {
      await pumpChrome(
        tester,
        width: 420,
        brightness: 0.5,
        visible: false,
      );

      final opacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byType(OnyxBrightnessSlider),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(opacity.opacity, 0);
    });
  });

  group('drawn smaller on an iPhone', () {
    test('scaling trims what is drawn and leaves what is touched', () {
      // The whole point of the split: a chrome that looks 10% smaller and is
      // 10% harder to press is not the same trade.
      const base = OnyxChromeMetrics.wide();
      final small = base.scaledBy(0.9);

      expect(small.titleSize, closeTo(base.titleSize * 0.9, 0.001));
      expect(small.iconSize, closeTo(base.iconSize * 0.9, 0.001));
      expect(small.gutter, closeTo(base.gutter * 0.9, 0.001));
      expect(small.hitSize, base.hitSize);
      expect(small.barThickness, base.barThickness);
      expect(small.isCompact, base.isCompact);
    });

    testWidgets('the icons come out smaller and the targets do not',
        (tester) async {
      Size targetOf(WidgetTester tester) => tester.getSize(
            find
                .ancestor(
                  of: find.byIcon(Icons.fullscreen_rounded),
                  matching: find.byType(GestureDetector),
                )
                .first,
          );

      // The glyph, not its box: the box is the target, and that is the half
      // that must not move.
      double glyphOf(WidgetTester tester) =>
          tester.widget<Icon>(find.byIcon(Icons.fullscreen_rounded)).size!;

      await pumpChrome(tester, width: 1280);
      final glyphAtFullSize = glyphOf(tester);
      final targetAtFullSize = targetOf(tester);

      await pumpChrome(tester, width: 1280, scale: 0.9);

      expect(glyphOf(tester), closeTo(glyphAtFullSize * 0.9, 0.001));
      expect(targetOf(tester), targetAtFullSize);
    });
  });

  group('driven by a remote', () {
    testWidgets('the volume control is left out of the television chrome',
        (tester) async {
      await pumpChrome(tester, width: 1280, isTv: true);

      // Both halves of it: the set owns the volume, and the slider was the one
      // focusable widget in this chrome — the remote landed on it and stayed.
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(find.byType(AppSlider), findsNothing);
    });

    testWidgets('the volume control stays everywhere else', (tester) async {
      await pumpChrome(tester, width: 1280);

      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('a phone is left out of it too', (tester) async {
      // Same reasoning as the television, different hardware: the handset has
      // volume keys under the fingers already holding it, and the top row is
      // short of slots.
      await pumpChrome(tester, width: 420, showVolume: false);

      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(find.byType(AppSlider), findsNothing);
    });

    testWidgets('the remote is handed the timeline on the way in',
        (tester) async {
      // Le lecteur d'Apple : pas de bouton lecture à l'écran, la télécommande
      // tient la barre, et OK met en pause (ADR-0124).
      var toggled = 0;
      final progress = FocusNode();
      addTearDown(progress.dispose);

      await pumpChrome(
        tester,
        width: 1280,
        isTv: true,
        progressFocusNode: progress,
        onPlayPause: () => toggled++,
      );

      progress.requestFocus();
      await tester.pump();
      expect(progress.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('every control in the bar can take the focus', (tester) async {
      await pumpChrome(
        tester,
        width: 1280,
        isTv: true,
        onSkipNext: () {},
        onSkipPrevious: () {},
        onOpenEpisodes: () {},
        onOpenWatchParty: () {},
        overview: 'Un résumé.',
      );

      // One per control: previous, subtitles, audio, settings, next, the
      // scrubber, and the three tabs. A count is what catches a control added
      // later without a way to reach it.
      final focusable = tester
          .widgetList<Focus>(find.byType(Focus))
          .where((f) => f.canRequestFocus)
          .length;
      expect(focusable, greaterThanOrEqualTo(9));
    });

    testWidgets('a hidden chrome holds no focus', (tester) async {
      final progress = FocusNode();
      addTearDown(progress.dispose);

      await pumpChrome(
        tester,
        width: 1280,
        isTv: true,
        visible: false,
        progressFocusNode: progress,
      );

      progress.requestFocus();
      await tester.pump();

      // Faded out, the bar is still in the tree. If its controls could still
      // be focused the remote would walk a control bar nobody can see.
      expect(progress.hasFocus, isFalse);
    });
  });

  group('the D-pad walks the television chrome', () {
    TvNavHarness.forEachEngine((engine) {
      /// Mounts the television chrome on the bench, with the remote on the
      /// timeline.
      Future<(TvNavHarness, FocusNode)> pumpTv(
        WidgetTester tester, {
        VoidCallback? onRewind,
        VoidCallback? onSkipNext,
        VoidCallback? onOpenEpisodes,
      }) async {
        final progress = FocusNode(debugLabel: 'progress');
        addTearDown(progress.dispose);
        final nav = await pumpTvChrome(
          tester,
          engine,
          progressFocusNode: progress,
          onRewind: onRewind,
          onSkipNext: onSkipNext,
          onOpenEpisodes: onOpenEpisodes,
        );
        progress.requestFocus();
        await TvNavHarness.settle(tester);
        return (nav, progress);
      }

      bool focusedOn(WidgetTester tester, Finder what) {
        final context = primaryFocus?.context;
        if (context == null) return false;
        return find
            .descendant(of: find.byWidget(context.widget), matching: what)
            .evaluate()
            .isNotEmpty;
      }

      testWidgets('left on the timeline seeks, it does not leave it',
          (tester) async {
        var rewound = 0;
        final (nav, progress) =
            await pumpTv(tester, onRewind: () => rewound++);

        await nav.press(TraversalDirection.left);
        expect(rewound, 1);
        expect(progress.hasFocus, isTrue);
      });

      testWidgets(
          'up from the timeline reaches the round buttons, where right '
          'walks to the last one and stops there', (tester) async {
        final (nav, progress) = await pumpTv(tester);

        await nav.press(TraversalDirection.up);
        expect(progress.hasFocus, isFalse);

        final settings = find.byIcon(Icons.more_horiz_rounded);
        var reached = focusedOn(tester, settings);
        for (var press = 0; press < 6 && !reached; press++) {
          await nav.press(TraversalDirection.right);
          reached = focusedOn(tester, settings);
        }
        expect(reached, isTrue,
            reason: 'the settings button was never reached');

        await nav.press(TraversalDirection.right);
        expect(focusedOn(tester, settings), isTrue,
            reason: 'the edge of a row is a wall');

        await nav.press(TraversalDirection.up);
        expect(focusedOn(tester, settings), isTrue,
            reason: 'nothing above the round buttons');

        await nav.press(TraversalDirection.down);
        expect(progress.hasFocus, isTrue);
      });

      testWidgets('with a next episode, its button ends the row',
          (tester) async {
        final (nav, _) = await pumpTv(tester, onSkipNext: () {});

        await nav.press(TraversalDirection.up);
        for (var press = 0; press < 6; press++) {
          await nav.press(TraversalDirection.right);
        }
        expect(
            focusedOn(tester, find.byIcon(Icons.skip_next_rounded)), isTrue);
      });

      testWidgets('down from the timeline reaches the tabs, and OK opens one',
          (tester) async {
        var opened = 0;
        final (nav, progress) =
            await pumpTv(tester, onOpenEpisodes: () => opened++);

        await nav.press(TraversalDirection.down);
        expect(focusedOn(tester, find.text('Épisodes')), isTrue);
        await nav.select(key: LogicalKeyboardKey.enter);
        expect(opened, 1);

        await nav.press(TraversalDirection.down);
        expect(focusedOn(tester, find.text('Épisodes')), isTrue,
            reason: 'nothing below the tabs');
        await nav.press(TraversalDirection.up);
        expect(progress.hasFocus, isTrue);
      });

      testWidgets('without tabs, down from the timeline is a wall',
          (tester) async {
        final (nav, progress) = await pumpTv(tester);

        await nav.press(TraversalDirection.down);
        expect(progress.hasFocus, isTrue);
      });
    });
  });

  group('the television chrome is laid out for the remote', () {
    // ADR-0124 : l'arrangement du lecteur d'Apple.
    testWidgets(
        'nothing in the middle: title and round buttons above the '
        'timeline, times below', (tester) async {
      await pumpChrome(tester, width: 960, height: 540, isTv: true);

      // Ni lecture/pause, ni ±10 s, ni Retour : la télécommande les porte.
      for (final icon in [
        Icons.pause_rounded,
        Icons.play_arrow_rounded,
        Icons.replay_10_rounded,
        Icons.forward_10_rounded,
        Icons.arrow_back_ios_new_rounded,
      ]) {
        expect(find.byIcon(icon), findsNothing, reason: '$icon');
      }

      final bar = tester.getRect(find.byType(OnyxProgressBar));
      final title = tester.getRect(find.text('Avatar : La Voie de l’eau'));
      final overline = tester.getRect(find.text('2022'));
      final elapsed = tester.getRect(find.text('42:00'));
      final remaining = tester.getRect(find.text('-01:18:00'));

      // Le titre en gras, sa ligne dessous, tous deux à gauche.
      expect(title.bottom, lessThanOrEqualTo(overline.top));
      expect(overline.bottom, lessThanOrEqualTo(bar.top));
      expect(title.left, bar.left);
      // Les boutons ronds à droite, au-dessus de la barre.
      for (final icon in [
        Icons.subtitles_rounded,
        Icons.graphic_eq_rounded,
        Icons.more_horiz_rounded,
      ]) {
        final button = tester.getRect(find.byIcon(icon));
        expect(button.bottom, lessThanOrEqualTo(bar.top), reason: '$icon');
        expect(button.left, greaterThan(480), reason: '$icon');
      }
      // Les temps dessous : écoulé à gauche, restant à droite, sans heure de
      // fin.
      expect(elapsed.top, greaterThanOrEqualTo(bar.bottom - 1));
      expect(elapsed.left, bar.left);
      expect(remaining.right, closeTo(bar.right, 0.5));
      // Tout tient dans le bas de l'image.
      expect(title.top, greaterThan(270));
    });

    testWidgets('no speed button: the rate is in the settings menu',
        (tester) async {
      await pumpChrome(tester, width: 960, height: 540, isTv: true);
      expect(find.byIcon(Icons.speed_rounded), findsNothing);
    });

    testWidgets(
        'a round button is glass at rest, white with dark ink under the '
        'remote', (tester) async {
      await pumpChrome(tester, width: 960, height: 540, isTv: true);

      final icon = find.byIcon(Icons.more_horiz_rounded);
      BoxDecoration disc() => tester
          .widgetList<AnimatedContainer>(find.ancestor(
            of: icon,
            matching: find.byType(AnimatedContainer),
          ))
          .first
          .decoration! as BoxDecoration;

      expect(disc().shape, BoxShape.circle);
      expect(disc().color, isNot(FocusFill.fill));
      expect(disc().color, isNot(Colors.transparent));
      expect(tester.getSize(find.ancestor(
        of: icon,
        matching: find.byType(AnimatedContainer),
      ).first), const Size.square(OnyxIconButton.glassSize));

      Focus.of(tester.element(icon)).requestFocus();
      await tester.pumpAndSettle();
      expect(disc().color, FocusFill.fill);
      expect(tester.widget<Icon>(icon).color, FocusFill.ink);
    });

    testWidgets(
        'the focused timeline stays white: it thickens and its marker '
        'grows', (tester) async {
      final progress = FocusNode();
      addTearDown(progress.dispose);
      await pumpChrome(
        tester,
        width: 960,
        height: 540,
        isTv: true,
        progressFocusNode: progress,
      );

      final bar = find.byType(OnyxProgressBar);
      bool accentFill() => tester
          .widgetList<DecoratedBox>(
              find.descendant(of: bar, matching: find.byType(DecoratedBox)))
          .any((box) =>
              (box.decoration as BoxDecoration).color == AppColors.accent);
      double thickness() => tester
          .getSize(find
              .descendant(of: bar, matching: find.byType(AnimatedContainer))
              .first)
          .height;
      double marker() => tester
          .getSize(find.descendant(
              of: bar, matching: find.byType(AnimatedPositioned)))
          .height;

      final restingThickness = thickness();
      final restingMarker = marker();

      progress.requestFocus();
      await tester.pumpAndSettle();

      expect(accentFill(), isFalse);
      expect(thickness(), greaterThan(restingThickness));
      expect(marker(), greaterThan(restingMarker));
    });

    testWidgets('drawn larger than the phone chrome', (tester) async {
      double titleSize() => tester
          .widgetList<Text>(find.text('Avatar : La Voie de l’eau'))
          .map((text) => text.style!.fontSize!)
          .reduce((a, b) => a > b ? a : b);

      await pumpChrome(tester, width: 960, height: 540, isTv: true);
      final tv = titleSize();

      await pumpChrome(tester, width: 700, height: 400, showVolume: false);
      expect(tv, greaterThan(titleSize()));
    });

    testWidgets('without a logo, nothing is drawn at the top left',
        (tester) async {
      await pumpChrome(tester, width: 960, height: 540, isTv: true);

      // Le titre n'est écrit qu'une fois, au-dessus de la barre.
      expect(find.text('Avatar : La Voie de l’eau'), findsOneWidget);
    });

    testWidgets('the tabs: only the ones with something to open',
        (tester) async {
      await pumpChrome(tester, width: 960, height: 540, isTv: true);
      expect(find.byType(OnyxChromeTab), findsNothing);

      var episodes = 0;
      var party = 0;
      await pumpChrome(
        tester,
        width: 960,
        height: 540,
        isTv: true,
        overview: 'Sur une lune lointaine, une famille défend son récif.',
        onOpenEpisodes: () => episodes++,
        onOpenWatchParty: () => party++,
      );

      final bar = tester.getRect(find.byType(OnyxProgressBar));
      for (final label in ['Infos', 'Épisodes', 'Regarder ensemble']) {
        expect(tester.getRect(find.text(label)).top, greaterThan(bar.bottom),
            reason: label);
      }
      expect(tester.getRect(find.text('Infos')).left, closeTo(bar.left, 0.5));

      await tester.tap(find.text('Épisodes'));
      await tester.tap(find.text('Regarder ensemble'));
      expect((episodes, party), (1, 1));
    });

    testWidgets('« Infos » unfolds the synopsis, and hiding the chrome folds it',
        (tester) async {
      const overview = 'Sur une lune lointaine, une famille défend son récif.';
      await pumpChrome(
        tester,
        width: 960,
        height: 540,
        isTv: true,
        overview: overview,
      );
      expect(find.text(overview), findsNothing);

      await tester.tap(find.text('Infos'));
      await tester.pumpAndSettle();
      expect(find.text(overview), findsOneWidget);

      await tester.tap(find.text('Infos'));
      await tester.pumpAndSettle();
      expect(find.text(overview), findsNothing);
    });

    testWidgets('the skip-intro offer is a glass capsule on a television',
        (tester) async {
      await pumpChrome(
        tester,
        width: 960,
        height: 540,
        isTv: true,
        onSkipIntro: () {},
      );

      final material = tester.widget<Material>(find
          .ancestor(
            of: find.text('Passer l’intro'),
            matching: find.byType(Material),
          )
          .first);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side, BorderSide.none);
      expect(shape.borderRadius, const BorderRadius.all(Radius.circular(21)));
    });

    testWidgets('no brightness bar, even when a brightness is supplied',
        (tester) async {
      await pumpChrome(
        tester,
        width: 960,
        height: 540,
        isTv: true,
        brightness: 0.5,
        onBrightnessChanged: (_) {},
      );

      expect(find.byType(OnyxBrightnessSlider), findsNothing);
    });

    testWidgets('no fullscreen toggle: there is no window', (tester) async {
      await pumpChrome(tester, width: 960, height: 540, isTv: true);

      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    });
  });
}
