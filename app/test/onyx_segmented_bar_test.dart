import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_theme.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_progress_bar.dart';

/// La barre de lecture se coupe à chaque chapitre (ADR-0139) : un vide entre
/// deux tronçons, pas un trait posé sur une barre continue.
void main() {
  OnyxSegmentedBarPainter painterFor(List<double> marks, double width) =>
      OnyxSegmentedBarPainter(
        cuts: OnyxSegmentedBarPainter.cutsFor(marks, width),
        buffered: 0.5,
        played: 0.25,
        playedColor: Colors.white,
      );

  test('sans chapitre, un seul tronçon d’un bord à l’autre', () {
    expect(painterFor(const [], 1000).segments(1000), [(0.0, 1000.0)]);
  });

  test('chaque chapitre ouvre un vide, centré sur son début', () {
    final segments = painterFor(const [0.0, 0.25, 0.5], 1000).segments(1000);

    const half = OnyxSegmentedBarPainter.gap / 2;
    expect(segments, [
      (0.0, 250 - half),
      (250 + half, 500 - half),
      (500 + half, 1000.0),
    ]);
  });

  test('un chapitre au bord, ou collé au précédent, ne coupe pas', () {
    // Le premier chapitre commence à zéro, le dernier peut finir à la fin :
    // un tronçon de deux points ne se lit pas, il ferait un point parasite.
    final cuts = OnyxSegmentedBarPainter.cutsFor(
      const [0.0, 0.001, 0.5, 0.502, 0.999, 1.0],
      1000,
    );
    expect(cuts, [500.0]);
  });

  test('les chapitres arrivent dans le désordre sans changer la coupe', () {
    expect(
      OnyxSegmentedBarPainter.cutsFor(const [0.6, 0.2], 1000),
      [200.0, 600.0],
    );
  });

  testWidgets('la barre du lecteur se dessine en tronçons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              child: OnyxProgressBar(
                progress: 0.25,
                buffered: 0.5,
                duration: const Duration(minutes: 40),
                chapterMarks: const [0.0, 0.2, 0.7],
                metrics: const OnyxChromeMetrics.wide(),
                onSeek: (_) {},
                marker: true,
              ),
            ),
          ),
        ),
      ),
    );

    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is OnyxSegmentedBarPainter,
      ),
    );
    final painter = paint.painter! as OnyxSegmentedBarPainter;
    expect(painter.cuts, [100.0, 350.0]);
    expect(painter.played, 0.25);
  });
}
