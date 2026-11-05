import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/request_catalog_filters.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/screens/requests/requests_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiClient {
  @override
  Future<RequestCatalogPage> getRequestCatalog({
    required int page,
    required String type,
    String? query,
    RequestCatalogFilters filters = RequestCatalogFilters.defaults,
  }) async =>
      const RequestCatalogPage(page: 1, totalPages: 1, results: []);

  @override
  Future<bool> supportsMyRequests() async => false;
}

Future<void> _pump(WidgetTester tester) async {
  final api = _Api();
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
    ],
    child: const MaterialApp(home: RequestsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => TvMode.enabled.value = false);

  testWidgets(
      'sur un téléviseur, les filtres avancés sont un bouton de l’en-tête, '
      'pas un bouton flottant hors d’atteinte', (tester) async {
    TvMode.enabled.value = true;
    await _pump(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    final button = find.widgetWithText(TextButton, 'Filtres avancés');
    expect(button, findsOneWidget);

    // Atteignable : il prend le focus comme n'importe quel bouton.
    Focus.of(tester.element(find.text('Filtres avancés'))).requestFocus();
    await tester.pump();
    expect(
      Focus.of(tester.element(find.text('Filtres avancés'))).hasFocus,
      isTrue,
    );
  });

  testWidgets('ailleurs, le bouton flottant reste', (tester) async {
    await _pump(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('le choix « Tout / Films / Séries » visé porte l’anneau de focus',
      (tester) async {
    TvMode.enabled.value = true;
    await _pump(tester);

    Focus.of(tester.element(find.text('Films'))).requestFocus();
    // Le focus se pose à une frame, l'anneau se dessine à la suivante.
    await tester.pump();
    await tester.pump();

    final ring = tester.widget<DecoratedBox>(find
        .ancestor(of: find.text('Films'), matching: find.byType(DecoratedBox))
        .first);
    final border = (ring.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.accent);
  });
}
