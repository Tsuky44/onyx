import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:onyx/models/retro.dart';
import 'package:onyx/screens/retro/hooks/retro_story_controller.dart';
import 'package:onyx/screens/retro/services/retro_share.dart';
import 'package:onyx/screens/retro/widgets/retro_story_chrome.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/tv/tv_mode.dart';

RetroReport _report() => RetroReport.fromJson({
      'year': 2026,
      'eligible': true,
      'watched_seconds': 312 * 3600,
      'plays': 410,
      'titles': 27,
      'top': [
        {
          'media_id': 1,
          'title': 'Severance',
          'media_type': 'show',
          'poster_url': '',
          'watched_seconds': 17 * 3600,
          'episodes': 19,
          'times': 0,
        },
      ],
      'months': List.filled(12, 3600),
      'hours': List.filled(24, 3600),
      'weekdays': List.filled(7, 3600),
      'archetype': 'marathon',
      'server': {'members': 1, 'rank': 1},
    });

/// Largeur et hauteur d'un PNG, lues dans son en-tête (IHDR).
(int, int) _pngSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return (data.getUint32(16), data.getUint32(20));
}

Widget _chrome(
  RetroStoryController story, {
  bool tv = false,
  bool saves = false,
  void Function(Rect)? onShare,
}) =>
    MaterialApp(
      home: TvScope(
        isTv: tv,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: story,
            builder: (_, __) => RetroStoryChrome(
              story: story,
              ink: Colors.white,
              background: Colors.black,
              year: 2026,
              onClose: () {},
              onShare: onShare,
              shareSaves: saves,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('l’image de récap sort au format story, 1080 × 1920',
      (tester) async {
    final view = tester.view;
    final png = await tester.runAsync(
      () => RetroShare.image(view, report: _report(), name: 'Léa'),
    );
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
    expect(_pngSize(png), (1080, 1920));
  });

  testWidgets('le dernier écran propose de partager et de revoir',
      (tester) async {
    final story = RetroStoryController(count: 3);
    Rect? origin;
    await tester.pumpWidget(_chrome(story, onShare: (at) => origin = at));
    expect(find.byIcon(AppIcons.replay), findsNothing,
        reason: 'pas avant la fin');

    story.goTo(2);
    // Les boutons attendent que la carte du dernier écran soit révélée.
    story.tick(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    final share = find.byIcon(AppIcons.share);
    expect(share, findsOneWidget);
    await tester.tap(share);
    expect(origin, isNotNull);
    expect(origin!.isEmpty, isFalse,
        reason: 'la feuille de partage d’un iPad s’accroche au bouton');

    await tester.tap(find.byIcon(AppIcons.replay));
    await tester.pump();
    expect(story.index, 0);
  });

  testWidgets('sur un PC, le bouton enregistre l’image', (tester) async {
    final story = RetroStoryController(count: 3)
      ..goTo(2)
      ..tick(const Duration(seconds: 10));
    await tester.pumpWidget(_chrome(story, saves: true, onShare: (_) {}));
    expect(find.byIcon(AppIcons.download), findsOneWidget);
    expect(find.byIcon(AppIcons.share), findsNothing);
  });

  testWidgets('au téléviseur, rien à partager', (tester) async {
    final story = RetroStoryController(count: 3)..goTo(2);
    await tester.pumpWidget(_chrome(story, tv: true, onShare: (_) {}));
    expect(find.byIcon(AppIcons.share), findsNothing);
    expect(find.byIcon(AppIcons.download), findsNothing);
    expect(find.byIcon(AppIcons.replay), findsNothing);
  });
}
