import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/server_account.dart';
import 'package:onyx/navigation/shell_navigator.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/search/phone/phone_search_row.dart';
import 'package:onyx/screens/search/phone/phone_search_screen.dart';
import 'package:onyx/screens/search/search_chips.dart';
import 'package:onyx/screens/search/search_layout.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/search_catalog_fakes.dart';

/// La recherche du téléphone (ADR-0145) : une page à elle, ouverte par la
/// loupe de la barre du haut, son champ seul à prendre la frappe.
///
/// Demande de l'utilisateur : « la recherche sur téléphone est super mal
/// gérée […] trouve une solution plus pratique et utilisable pour les
/// utilisateurs téléphone ». Les titres absents du serveur sont éprouvés par
/// `search_unavailable_shelf_test.dart`.

/// Un compte connecté à un serveur : ses recherches récentes sont retenues.
class _SignedIn extends FakeAuth {
  _SignedIn(super.api, super.permissions);

  @override
  ServerAccount? get activeServer => const ServerAccount(
        id: 'serveur',
        url: 'http://localhost:8080',
        username: 'mathis',
      );
}

SearchCatalogApi _server({int extraMovies = 0}) => SearchCatalogApi(
      movies: [
        libraryMovie(1, 'Dune', day: 3),
        libraryMovie(3, 'Drive', day: 2),
        for (var i = 0; i < extraMovies; i++)
          libraryMovie(100 + i, 'Film $i', day: 1),
      ],
      shows: [libraryMedia(11, 'Dark', type: MediaType.show, day: 4)],
    );

Future<void> _pump(WidgetTester tester, {int extraMovies = 0}) async {
  final api = _server(extraMovies: extraMovies);
  final auth = _SignedIn(api, const Permissions());
  addTearDown(auth.dispose);
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(
        create: (_) => WatchListsProvider(api)..debugMarkSupported(),
      ),
      ChangeNotifierProvider<DownloadManager>.value(
          value: DownloadManager.instance),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
      ChangeNotifierProvider(create: (_) => SearchProvider()),
      ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const GlassCatalogSearch(),
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
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(GlassCatalogSearch));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  // La page apprend la frappe à l'image suivante ; puis la pause qui
  // interroge le catalogue de demandes.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// Les titres des lignes, dans l'ordre de l'écran.
List<String> _rows(WidgetTester tester) => [
      for (final row
          in tester.widgetList<PhoneSearchRow>(find.byType(PhoneSearchRow)))
        switch (row.hit) {
          LibraryHit(:final media) => media.title,
          UnavailableHit(:final item) => item.title,
        },
    ];

bool _fieldFocused(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la loupe ouvre la page, le champ prêt à taper', (tester) async {
    await _pump(tester);

    expect(find.byType(PhoneSearchScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_fieldFocused(tester), isTrue);
  });

  testWidgets(
      'rien de tapé : les derniers ajouts, du plus récent au plus ancien',
      (tester) async {
    await _pump(tester);

    expect(find.text('Ajoutés récemment'), findsOneWidget);
    expect(_rows(tester), ['Dark', 'Dune', 'Drive']);
  });

  testWidgets('une ligne dit l’année et le type du titre', (tester) async {
    await _pump(tester);
    await _type(tester, 'dark');

    expect(_rows(tester), ['Dark']);
    expect(find.text('2021  ·  Série'), findsOneWidget);
  });

  testWidgets('vider le champ garde la page ouverte', (tester) async {
    await _pump(tester);
    await _type(tester, 'dune');
    await _type(tester, '');

    expect(find.byType(PhoneSearchScreen), findsOneWidget);
    expect(find.text('Ajoutés récemment'), findsOneWidget);
  });

  testWidgets('« Annuler » referme la page', (tester) async {
    await _pump(tester);
    await _type(tester, 'dune');

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSearchScreen), findsNothing);
    expect(find.text('Accueil'), findsOneWidget);
  });

  testWidgets(
      'les pastilles gardent les séries, et une nouvelle frappe repart de '
      '« Tout »', (tester) async {
    await _pump(tester);
    await _type(tester, 'd');
    expect(_rows(tester), unorderedEquals(['Dune', 'Drive', 'Dark']));

    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is SearchFilterChip && widget.label == 'Séries',
    ));
    await tester.pumpAndSettle();
    expect(_rows(tester), ['Dark']);

    await _type(tester, 'du');
    expect(_rows(tester), ['Dune']);
  });

  testWidgets('faire défiler les résultats baisse le clavier', (tester) async {
    await _pump(tester, extraMovies: 20);
    await _type(tester, 'film');
    expect(_fieldFocused(tester), isTrue);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_fieldFocused(tester), isFalse);
  });

  testWidgets(
      'une recherche qui a servi revient en pastille, et la toucher la '
      'retape', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null));
    await _pump(tester);
    // La fiche qui s'ouvre a besoin de la largeur d'un écran : sous la
    // police des tests, sa rangée d'acteurs déborde d'un téléphone.
    await tester.binding.setSurfaceSize(const Size(1000, 860));
    await _type(tester, 'dune');

    await tester.tap(find.widgetWithText(PhoneSearchRow, 'Dune'));
    await tester.pumpAndSettle();
    shellNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    // La croix du champ : la page reste, et propose la recherche d'avant.
    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSearchScreen), findsOneWidget);
    expect(find.text('Recherches récentes'), findsOneWidget);
    await tester.tap(find.text('dune'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'dune');
    expect(_rows(tester), ['Dune']);
  });
}
