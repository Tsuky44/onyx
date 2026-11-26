import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:onyx/screens/retro/hooks/retro_story_controller.dart';
import 'package:onyx/screens/retro/widgets/retro_story_chrome.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/theme/app_icons.dart';

Widget _chrome(RetroStoryController story, {bool tv = false}) => MaterialApp(
      home: TvScope(
        isTv: tv,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: story,
            builder: (_, __) => RetroStoryChrome(
              story: story,
              ink: Colors.white,
              year: 2026,
              onClose: () {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('le bouton pause garde l’écran affiché, puis le relance',
      (tester) async {
    final story = RetroStoryController(count: 3);
    await tester.pumpWidget(_chrome(story));

    await tester.tap(find.byIcon(AppIcons.pause));
    await tester.pump();
    expect(story.paused, isTrue);

    story.tick(const Duration(seconds: 20));
    expect(story.index, 0);
    expect(story.progress, 0);

    await tester.tap(find.byIcon(AppIcons.play));
    await tester.pump();
    expect(story.paused, isFalse);
    expect(find.byIcon(AppIcons.pause), findsOneWidget);
  });

  testWidgets('au téléviseur, pas de bouton : seul le témoin de pause',
      (tester) async {
    final story = RetroStoryController(count: 3);
    await tester.pumpWidget(_chrome(story, tv: true));
    expect(find.byIcon(AppIcons.pause), findsNothing);

    story.togglePause();
    await tester.pump();
    expect(find.byIcon(AppIcons.pause), findsOneWidget);
    expect(find.byIcon(AppIcons.play), findsNothing);
  });
}
