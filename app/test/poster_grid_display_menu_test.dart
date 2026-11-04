import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/utils/poster_grid_zoom.dart';
import 'package:onyx/utils/responsive.dart';
import 'package:onyx/widgets/global/poster_grid_display_menu.dart';
import 'package:onyx/widgets/global/poster_grid_zoom_region.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le bouton « Affichage » propose quatre modes (4, 6, 8, 10 affiches par
/// ligne), et la grille de sa page suit celui qu'on choisit.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PosterGridZoom.instance.resetForTest();
  });

  Future<void> pumpPage(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosterGridZoomRegion(
            child: CustomScrollView(
              slivers: [
                const SliverPosterGridDisplayBar(),
                SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid(
                    gridDelegate: AppLayout.posterGridDelegate(
                      context,
                      constraints.crossAxisExtent,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const SizedBox.shrink(),
                      childCount: 60,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int columns(WidgetTester tester) {
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.text('Affichage'));
    await tester.pumpAndSettle();
  }

  testWidgets('le menu propose 4, 6, 8 et 10 par ligne', (tester) async {
    await pumpPage(tester);
    await openMenu(tester);

    for (final columns in [4, 6, 8, 10]) {
      expect(find.text('$columns par ligne'), findsOneWidget);
    }
    expect(PosterGridZoom.presets, [4, 6, 8, 10]);
  });

  for (final preset in [4, 6, 8, 10]) {
    testWidgets('choisir « $preset par ligne » règle la grille',
        (tester) async {
      await pumpPage(tester);
      await openMenu(tester);

      await tester.tap(find.text('$preset par ligne'));
      await tester.pumpAndSettle();

      expect(columns(tester), preset);
      expect(PosterGridZoom.instance.selected, preset);
    });
  }

  testWidgets('le choix est enregistré pour la prochaine séance',
      (tester) async {
    await pumpPage(tester);
    await openMenu(tester);
    await tester.tap(find.text('6 par ligne'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('poster_grid_columns'), 6);
  });
}
