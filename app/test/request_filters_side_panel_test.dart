import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/request_catalog_filters.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/screens/requests/requests_screen.dart';
import 'package:onyx/screens/requests/widgets/request_filter_bar.dart';
import 'package:onyx/widgets/global/filter_panel/onyx_filter_chip.dart';
import 'package:onyx/screens/requests/widgets/request_filters_bottom_sheet.dart';
import 'package:onyx/screens/requests/widgets/request_filters_fab.dart';
import 'package:onyx/screens/requests/widgets/request_filters_side_panel.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/filter_panel/onyx_filter_dock.dart';
import 'package:onyx/widgets/global/filter_panel/onyx_filter_panel.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un catalogue de 40 affiches qui note les filtres de chaque chargement.
class _Api extends ApiClient {
  final calls = <RequestCatalogFilters>[];

  @override
  Future<RequestCatalogPage> getRequestCatalog({
    required int page,
    required String type,
    String? query,
    RequestCatalogFilters filters = RequestCatalogFilters.defaults,
  }) async {
    calls.add(filters);
    return RequestCatalogPage(page: 1, totalPages: 1, results: [
      for (var i = 0; i < 40; i++)
        RequestMediaItem.fromJson({
          'id': i + 1,
          'mediaType': 'movie',
          'title': 'Film $i',
        }),
    ]);
  }

  @override
  Future<List<RequestGenre>> getRequestFilterGenres(String type) async =>
      const [
        RequestGenre(id: 28, name: 'Action'),
        RequestGenre(id: 18, name: 'Drame'),
      ];

  @override
  Future<List<RequestWatchProvider>> getRequestWatchProviders({
    required String type,
    required String region,
  }) async =>
      [
        for (var i = 0; i < 15; i++)
          RequestWatchProvider(providerId: i + 1, providerName: 'Service $i'),
      ];

  @override
  Future<bool> supportsMyRequests() async => false;
}

Future<_Api> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api();
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
    ],
    child: const MaterialApp(home: RequestsScreen()),
  ));
  await tester.pumpAndSettle();
  return api;
}

/// Déplie (ou replie) la section [title] du panneau : toutes sont repliées
/// à l'ouverture.
Future<void> _expand(WidgetTester tester, String title) async {
  final header = find.descendant(
      of: find.byType(RequestFiltersSidePanel), matching: find.text(title));
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pumpAndSettle();
}

Future<void> _settleFilters(WidgetTester tester) async {
  await tester.pump(RequestsScreen.filtersDebounce);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TvMode.enabled.value = false;
  });

  testWidgets(
      'sur grand écran, le bouton ouvre le panneau latéral et non la '
      'feuille du bas, et la page se resserre à côté', (tester) async {
    await _pump(tester, const Size(1400, 900));
    final pageWidth = tester.getSize(find.byType(CustomScrollView)).width;

    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();

    expect(find.byType(RequestFiltersSidePanel), findsOneWidget);
    expect(find.byType(RequestFiltersBottomSheet), findsNothing);
    // Le panneau a sa croix : le bouton flottant ne passe pas dessus.
    expect(find.byType(RequestFiltersFab), findsNothing);
    // Les capsules du haut restent.
    expect(find.byType(RequestFilterBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(CustomScrollView)).width,
      pageWidth - OnyxFilterPanel.width - OnyxFilterDock.margin,
    );

    await tester.tap(find.byTooltip('Fermer les filtres'));
    await tester.pumpAndSettle();
    expect(find.byType(RequestFiltersSidePanel), findsNothing);
    expect(find.byType(RequestFiltersFab), findsOneWidget);
    expect(tester.getSize(find.byType(CustomScrollView)).width, pageWidth);
  });

  testWidgets(
      'les filtres sont repliés à l’ouverture et disent leur valeur ; '
      'l’en-tête déplie le choix', (tester) async {
    await _pump(tester, const Size(1400, 900));
    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    final panel = find.byType(RequestFiltersSidePanel);

    expect(find.descendant(of: panel, matching: find.text('Action')),
        findsNothing);
    expect(find.text('Tous les genres'), findsOneWidget);
    expect(find.text('Toutes les dates'), findsOneWidget);
    expect(find.bySemanticsLabel('Service 0'), findsNothing);

    await _expand(tester, 'Genres');
    expect(find.descendant(of: panel, matching: find.text('Action')),
        findsOneWidget);

    await _expand(tester, 'Genres');
    expect(find.descendant(of: panel, matching: find.text('Action')),
        findsNothing);
  });

  testWidgets(
      'chaque choix du panneau part vers la grille : genre, décennie, '
      'tranche de durée, et une capsule allumée se retire au second clic',
      (tester) async {
    final api = await _pump(tester, const Size(1400, 900));
    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    final panel = find.byType(RequestFiltersSidePanel);

    await _expand(tester, 'Genres');
    await tester.tap(find.descendant(of: panel, matching: find.text('Action')));
    await _settleFilters(tester);
    expect(api.calls.last.genres, [28]);
    // Replié, l'en-tête nomme le genre coché.
    await _expand(tester, 'Genres');
    expect(find.descendant(of: panel, matching: find.text('Action')),
        findsOneWidget);

    await _expand(tester, 'Date de sortie');
    await tester.tap(find.text('2010 – 2019'));
    await _settleFilters(tester);
    expect(api.calls.last.startDate, '2010-01-01');
    expect(api.calls.last.endDate, '2019-12-31');

    await _expand(tester, 'Durée');
    await tester.ensureVisible(find.text('Plus de 2 h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plus de 2 h'));
    await _settleFilters(tester);
    expect(api.calls.last.minDuration, '120');
    expect(api.calls.last.maxDuration, '');

    await tester.tap(find.text('Plus de 2 h').last);
    await _settleFilters(tester);
    expect(api.calls.last.minDuration, '');
    expect(api.calls.last.genres, [28]);
  });

  testWidgets(
      'les services montrent les douze premiers, le reste attend '
      '« Voir les autres »', (tester) async {
    await _pump(tester, const Size(1400, 900));
    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    await _expand(tester, 'Disponible sur');

    expect(find.bySemanticsLabel('Service 11'), findsOneWidget);
    expect(find.bySemanticsLabel('Service 12'), findsNothing);

    final more = find.text('Voir les 3 autres services');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Service 14'), findsOneWidget);
  });

  testWidgets('une capsule du haut retirée vide aussi le panneau ouvert',
      (tester) async {
    final api = await _pump(tester, const Size(1400, 900));
    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    await _expand(tester, 'Date de sortie');
    await tester.tap(find.text('Avant 2000'));
    await _settleFilters(tester);
    expect(api.calls.last.endDate, '1999-12-31');

    await tester.tap(find.byTooltip('Retirer le filtre'));
    await _settleFilters(tester);
    expect(api.calls.last.endDate, '');
    final chip = tester.widget<OnyxFilterChip>(find.ancestor(
        of: find.text('Avant 2000'), matching: find.byType(OnyxFilterChip)));
    expect(chip.active, isFalse);
    expect(find.text('Toutes les dates'), findsOneWidget);
  });

  testWidgets(
      'plus étroit, le panneau passe par-dessus la page et un clic à côté '
      'le ferme', (tester) async {
    await _pump(tester, const Size(1000, 800));
    final pageWidth = tester.getSize(find.byType(CustomScrollView)).width;

    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    expect(find.byType(RequestFiltersSidePanel), findsOneWidget);
    expect(tester.getSize(find.byType(CustomScrollView)).width, pageWidth);

    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(find.byType(RequestFiltersSidePanel), findsNothing);
  });
}
