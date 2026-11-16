import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/request_catalog_filters.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/screens/requests/requests_screen.dart';
import 'package:onyx/screens/requests/widgets/request_filter_bar.dart';
import 'package:onyx/screens/requests/widgets/request_filters_bottom_sheet.dart';
import 'package:onyx/screens/requests/widgets/request_filters_fab.dart';
import 'package:onyx/screens/requests/widgets/request_provider_logo.dart';
import 'package:onyx/services/api_client.dart';
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
      const [RequestWatchProvider(providerId: 8, providerName: 'Netflix')];

  @override
  Future<bool> supportsMyRequests() async => false;
}

Future<_Api> _pumpPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TvMode.enabled.value = false;
  });

  test('le compte du bouton compte les familles posées, pas le tri', () {
    const d = RequestCatalogFilters.defaults;
    expect(RequestFiltersBottomSheet.activeCount(d), 0);
    expect(
        RequestFiltersBottomSheet.activeCount(
            d.copyWith(sortBy: 'vote_average.desc')),
        0);
    expect(
        RequestFiltersBottomSheet.activeCount(d.copyWith(
          genres: [28, 18],
          startDate: '2020-01-01',
          watchProviders: [8],
        )),
        3);
  });

  testWidgets(
      'sur téléphone, le bouton Filtres reste à l’écran au défilement '
      'et remplace la rangée de capsules', (tester) async {
    await _pumpPhone(tester);

    expect(find.byType(RequestFilterBar), findsNothing);
    expect(find.byType(RequestFiltersFab), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(find.byType(RequestFiltersFab).hitTestable(), findsOneWidget);
  });

  testWidgets(
      'la feuille est un index des filtres : un détail par filtre, '
      'chaque coche part vers la grille, et le bouton prend le compte', (tester) async {
    final api = await _pumpPhone(tester);

    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    // L'index : une ligne par filtre, avec sa valeur.
    expect(find.text('Trier par'), findsOneWidget);
    expect(find.text('Disponible sur'), findsOneWidget);
    expect(find.text('Action'), findsNothing);

    await tester.tap(find.text('Genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pump(RequestsScreen.filtersDebounce);
    await tester.pumpAndSettle();
    expect(api.calls.last.genres, [28]);

    // Retour à l'index : la ligne nomme le genre coché.
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsOneWidget);

    await tester.tap(find.text('Voir les résultats'));
    await tester.pumpAndSettle();
    expect(find.text('Trier par'), findsNothing);
    expect(find.bySemanticsLabel('Filtres · 1'), findsOneWidget);
    // La pastille de la TV ne double pas le compte du bouton.
    expect(find.text('Filtres avancés actifs'), findsNothing);
  });

  testWidgets('« Disponible sur » montre le logo de chaque service',
      (tester) async {
    await _pumpPhone(tester);

    await tester.tap(find.byType(RequestFiltersFab));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disponible sur'));
    await tester.pumpAndSettle();

    expect(find.text('Netflix'), findsOneWidget);
    expect(
      find.ancestor(
          of: find.byType(RequestProviderLogo),
          matching: find.byType(InkWell)),
      findsWidgets,
    );
  });
}
