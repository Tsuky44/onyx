import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/request_catalog_filters.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/screens/requests/requests_screen.dart';
import 'package:onyx/screens/requests/widgets/request_filter_bar.dart';
import 'package:onyx/screens/requests/widgets/request_filter_chip.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un catalogue qui note chaque chargement et les filtres demandés.
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
    return const RequestCatalogPage(page: 1, totalPages: 1, results: []);
  }

  @override
  Future<List<RequestGenre>> getRequestFilterGenres(String type) async =>
      const [
        RequestGenre(id: 28, name: 'Action'),
        RequestGenre(id: 35, name: 'Comédie'),
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

Future<_Api> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
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

/// Laisse passer le délai des capsules et le chargement qui suit.
Future<void> _settleReload(WidgetTester tester) async {
  await tester.pump(RequestsScreen.filtersDebounce);
  await tester.pumpAndSettle();
}

Finder _chip(String label) => find.widgetWithText(RequestFilterChip, label);

RequestFilterChip _chipWidget(WidgetTester tester, String label) =>
    tester.widget<RequestFilterChip>(_chip(label));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TvMode.enabled.value = false;
  });

  testWidgets('les capsules remplacent le bouton flottant hors TV',
      (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    for (final label in ['Genres', 'Période', 'Langue', 'Streaming', 'Durée']) {
      expect(_chip(label), findsOneWidget, reason: label);
      expect(_chipWidget(tester, label).active, isFalse, reason: label);
    }
    expect(find.text('Trier : Popularité (décr.)'), findsOneWidget);
    expect(find.text('Tout effacer'), findsNothing);
  });

  testWidgets(
      'choix multiple : le menu des genres reste ouvert, la capsule compte, '
      'et la grille ne recharge qu’une fois après la dernière coche',
      (tester) async {
    final api = await _pumpScreen(tester);
    final before = api.calls.length;

    await tester.tap(_chip('Genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pump();
    await tester.tap(find.text('Drame'));
    await tester.pump();

    // Toujours ouvert après deux coches.
    expect(find.text('Comédie'), findsOneWidget);
    expect(_chipWidget(tester, 'Genres · 2').active, isTrue);
    expect(api.calls.length, before, reason: 'le délai n’est pas écoulé');

    await _settleReload(tester);
    expect(api.calls.length, before + 1);
    expect(api.calls.last.genres, [28, 18]);
    expect(find.text('Tout effacer'), findsOneWidget);
  });

  testWidgets('le ✕ d’une capsule active retire son filtre et recharge',
      (tester) async {
    final api = await _pumpScreen(tester);

    await tester.tap(_chip('Langue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japonais').last);
    await tester.pumpAndSettle();
    await _settleReload(tester);
    expect(_chipWidget(tester, 'Japonais').active, isTrue);
    expect(api.calls.last.language, 'ja');

    await tester.tap(find.byTooltip('Retirer le filtre'));
    await _settleReload(tester);

    expect(_chipWidget(tester, 'Langue').active, isFalse);
    expect(api.calls.last.language, 'all');
    expect(find.text('Tout effacer'), findsNothing);
  });

  testWidgets('« Tout effacer » retire les filtres mais garde le tri',
      (tester) async {
    final api = await _pumpScreen(tester);

    await tester.tap(find.text('Trier : Popularité (décr.)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note (décr.)').last);
    await tester.pumpAndSettle();
    await tester.tap(_chip('Durée'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Min'), '90');
    await tester.tapAt(const Offset(5, 995));
    await _settleReload(tester);
    expect(find.text('Dès 90 min'), findsOneWidget);

    await tester.tap(find.text('Tout effacer'));
    await _settleReload(tester);

    expect(api.calls.last.minDuration, isEmpty);
    expect(api.calls.last.sortBy, 'vote_average.desc');
    expect(find.text('Trier : Note (décr.)'), findsOneWidget);
  });

  test('« Tout effacer » ne compte pas le tri comme un filtre', () {
    const sorted = RequestCatalogFilters(sortBy: 'vote_average.desc');
    expect(RequestFilterBar.hasActive(sorted), isFalse);
    expect(
      RequestFilterBar.hasActive(sorted.copyWith(watchProviders: [8])),
      isTrue,
    );
  });
}
