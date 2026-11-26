import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:onyx/models/retro.dart';
import 'package:onyx/screens/retro/slides/retro_card_slide.dart';
import 'package:onyx/screens/retro/slides/retro_hours_slide.dart';
import 'package:onyx/screens/retro/slides/retro_slide.dart';
import 'package:onyx/screens/retro/widgets/retro_confetti.dart';
import 'package:onyx/screens/retro/widgets/retro_slide_transition.dart';

RetroStoryData _data() => RetroStoryData(
      report: RetroReport.fromJson({
        'year': 2026,
        'eligible': true,
        'watched_seconds': 312 * 3600,
        'plays': 410,
        'titles': 27,
        'movie_seconds': 3600,
        'top': [
          {'title': 'Severance', 'media_type': 'show', 'watched_seconds': 3600},
        ],
        'hours': [for (var h = 0; h < 24; h++) h == 21 ? 7200 : 600],
        'archetype': 'marathon',
        'server': {'members': 14, 'rank': 2, 'watched_seconds': 3600},
      }),
      name: 'Léa',
      serverBaseUrl: null,
    );

Widget _app(Widget child, {bool still = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), disableAnimations: still),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('le chiffre défile jusqu’à sa valeur', (tester) async {
    await tester.pumpWidget(_app(Builder(
        builder: (c) => const RetroHoursSlide().build(c, _data()))));
    expect(find.text('312'), findsNothing, reason: 'au départ, il est à 0');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('312'), findsOneWidget);
  });

  testWidgets('sous « réduire les animations », tout est là tout de suite',
      (tester) async {
    await tester.pumpWidget(_app(
      Builder(builder: (c) => const RetroHoursSlide().build(c, _data())),
      still: true,
    ));
    await tester.pump();
    expect(find.text('312'), findsOneWidget);
  });

  testWidgets('les confettis ne tombent que si l’on accepte le mouvement',
      (tester) async {
    Widget card(bool still) => _app(
          Builder(builder: (c) => const RetroCardSlide().build(c, _data())),
          still: still,
        );
    await tester.pumpWidget(card(true));
    expect(
      find.descendant(of: find.byType(RetroConfetti), matching: find.byType(CustomPaint)),
      findsNothing,
    );
    await tester.pumpWidget(Container());
    await tester.pumpWidget(card(false));
    expect(
      find.descendant(of: find.byType(RetroConfetti), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
  });

  testWidgets('l’écran suivant s’ouvre par-dessus l’ancien, qui s’en va ensuite',
      (tester) async {
    Widget at(int index) => _app(RetroSlideTransition(
          index: index,
          origin: const Offset(0.9, 0.5),
          child: Text('écran $index'),
        ));
    await tester.pumpWidget(at(0));
    await tester.pumpWidget(at(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('écran 0'), findsOneWidget);
    expect(find.text('écran 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('écran 0'), findsNothing);
    expect(find.text('écran 1'), findsOneWidget);
  });
}
