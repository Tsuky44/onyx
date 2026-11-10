import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/navigation/shell_navigator.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/library/search_results_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:onyx/widgets/global/search_results_route.dart';
import 'package:onyx/widgets/global/staggered_entrance.dart';
import 'package:provider/provider.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient([this.movies = 1]);

  final int movies;

  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<List<HomeMediaItem>> getMovies() async => [
        for (var i = 0; i < movies; i++)
          HomeMediaItem.fromJson({
            'id': i + 1,
            'type': 'movie',
            'title': i == 0 ? 'Dune' : 'Dune $i',
            'duration': 6000,
          }),
      ];

  @override
  Future<List<Media>> getShows() async => [];
}

/// La barre de verre du grand écran au-dessus du navigateur de la coquille,
/// comme dans `MainShell`.
Future<void> _pumpShell(WidgetTester tester, {int movies = 1}) async {
  final api = _FakeApiClient(movies);
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const GlassCatalogSearch(staysAbovePages: true),
              Expanded(
                child: Navigator(
                  key: shellNavigatorKey,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const Center(child: Text('Accueil')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _fieldHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

void main() {
  testWidgets('taper dans la barre ouvre la vue de résultats en pleine page',
      (tester) async {
    await _pumpShell(tester);

    await tester.enterText(find.byType(TextField), 'Du');
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(find.text('Résultats pour « Du »'), findsOneWidget);
    expect(_fieldHasFocus(tester), isTrue,
        reason: 'la frappe continue dans la barre pendant que la vue s’ouvre');
  });

  testWidgets(
      'la vue s’approche en fondu au lieu de glisser comme une page ordinaire',
      (tester) async {
    await _pumpShell(tester);

    await tester.enterText(find.byType(TextField), 'Du');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final page = find.byType(SearchResultsScreen);
    final fade = tester.widget<FadeTransition>(
        find.ancestor(of: page, matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, inExclusiveRange(0.0, 1.0),
        reason: 'à mi-chemin, la vue apparaît par-dessus la page d’avant');
    final scale = tester.widget<ScaleTransition>(
        find.ancestor(of: page, matching: find.byType(ScaleTransition)).first);
    expect(
        scale.scale.value, inExclusiveRange(SearchResultsRoute.startScale, 1.0),
        reason: 'la vue s’approche à peine, jamais un glissement');
    // L'accueil reste dessous pendant le fondu.
    expect(find.text('Accueil'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('l’en-tête des résultats se pose juste après la page',
      (tester) async {
    await _pumpShell(tester);

    await tester.enterText(find.byType(TextField), 'Du');
    await tester.pump();
    // Avant `headerStart` : la page se fond déjà, l'en-tête attend.
    await tester.pump(const Duration(milliseconds: 40));

    double headerOpacity() => tester
        .widget<FadeTransition>(find
            .ancestor(
              of: find.text('Résultats pour « Du »'),
              matching: find.byType(FadeTransition),
            )
            .first)
        .opacity
        .value;

    expect(headerOpacity(), 0.0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(headerOpacity(), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(headerOpacity(), 1.0);
  });

  testWidgets(
      'toutes les affiches du premier écran entrent en cascade, dernière ligne comprise',
      (tester) async {
    await _pumpShell(tester, movies: 40);

    await tester.enterText(find.byType(TextField), 'Du');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final screen = tester.getRect(find.byType(SearchResultsScreen));
    final onScreen = find.byType(StaggeredEntrance).evaluate().where((e) {
      final box = e.renderObject! as RenderBox;
      return screen.overlaps(box.localToGlobal(Offset.zero) & box.size);
    }).toList();
    expect(onScreen.length, greaterThan(16),
        reason:
            'le premier écran dépasse les seize cartes de l’ancienne limite');
    for (final card in onScreen) {
      final fades = find.descendant(
        of: find.byWidget(card.widget),
        matching: find.byType(Opacity),
      );
      expect(fades, findsWidgets,
          reason: 'une carte sans cascade arrive d’un coup, avant les autres');
      expect(tester.widget<Opacity>(fades.first).opacity, lessThan(1.0));
    }
    await tester.pumpAndSettle();
  });

  testWidgets('vider la barre rend la page d’avant et garde le focus du champ',
      (tester) async {
    await _pumpShell(tester);

    await tester.enterText(find.byType(TextField), 'Du');
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultsScreen), findsNothing);
    expect(find.text('Accueil'), findsOneWidget);
    expect(_fieldHasFocus(tester), isTrue,
        reason: 'on efface souvent pour retaper autre chose');

    // Retaper rouvre la vue.
    await tester.enterText(find.byType(TextField), 'Dune');
    await tester.pumpAndSettle();
    expect(find.text('Résultats pour « Dune »'), findsOneWidget);
  });

  testWidgets(
      'vider la barre depuis une fiche ouverte des résultats rend la page d’avant',
      (tester) async {
    await _pumpShell(tester);

    await tester.enterText(find.byType(TextField), 'Du');
    await tester.pumpAndSettle();
    shellNavigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Fiche')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Fiche'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('Fiche'), findsNothing);
    expect(find.byType(SearchResultsScreen), findsNothing);
    expect(find.text('Accueil'), findsOneWidget);
  });
}
