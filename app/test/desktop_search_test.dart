import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/server_account.dart';
import 'package:onyx/navigation/shell_navigator.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/library/widgets/library_spotlight.dart';
import 'package:onyx/screens/requests/request_detail_screen.dart';
import 'package:onyx/screens/requests/widgets/request_media_card.dart';
import 'package:onyx/screens/search/search_chips.dart';
import 'package:onyx/screens/search/desktop/desktop_search_hotkey.dart';
import 'package:onyx/screens/search/desktop/desktop_search_sheet.dart';
import 'package:onyx/utils/responsive.dart';
import 'package:onyx/screens/shell/desktop_header_search.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:onyx/widgets/global/poster_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/search_catalog_fakes.dart';

/// La recherche du bureau (ADR-0139) : le champ de l'en-tête garde le focus,
/// un voile de verre descend sur la page sans la quitter, les flèches et
/// Entrée pilotent la grille depuis le champ, Échap referme.
///
/// Demande de l'utilisateur : « que cette recherche soit mieux intégrée sur
/// le PC », avec « l'idée d'avoir un Ctrl K ».
SearchCatalogApi _server() => SearchCatalogApi(
      movies: [
        libraryMovie(1, 'Dune', tmdbId: 438631, day: 3),
        libraryMovie(3, 'Drive', day: 2),
        libraryMovie(4, 'Dunkerque', day: 1),
      ],
      shows: [libraryMedia(11, 'Dark', type: MediaType.show, day: 4)],
      catalog: {
        'dune': [
          catalogTitle(438631, 'Dune', status: RequestMediaStatus.available),
          catalogTitle(693134, 'Dune : Deuxième partie'),
        ],
      },
    );

/// Un compte connecté à un serveur : ses recherches récentes sont à lui.
class _SignedIn extends FakeAuth {
  _SignedIn(super.api, super.permissions);

  @override
  ServerAccount? get activeServer => const ServerAccount(
      id: 'maison', url: 'http://maison.local', username: 'mathis');
}

/// L'en-tête du bureau au-dessus du navigateur de la coquille, avec les
/// raccourcis de `MaterialApp` comme dans `main.dart`.
Future<SearchCatalogApi> _pump(
  WidgetTester tester, {
  bool canRequest = false,
  Size size = const Size(1400, 900),
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = _server();
  final auth = _SignedIn(api, Permissions(requestMedia: canRequest));
  addTearDown(auth.dispose);
  await tester.binding.setSurfaceSize(size);
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
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        ...DesktopSearchHotkey.bindings,
      },
      actions: <Type, Action<Intent>>{
        ...WidgetsApp.defaultActions,
        OpenSearchIntent: DesktopSearchHotkey.action,
      },
      home: Scaffold(
        body: Column(
          children: [
            const Center(child: DesktopHeaderSearch(width: 500)),
            Expanded(
              child: Navigator(
                key: shellNavigatorKey,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Center(
                    child: Focus(autofocus: true, child: Text('Accueil')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

Finder get _field => find.byType(TextField);

bool _fieldHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(_field).focusNode!.hasFocus;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  // La pause dans la frappe qui interroge le catalogue, puis sa réponse.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// La mise en avant de l'affiche de [title].
PosterHighlight _highlightOf(WidgetTester tester, String title) => tester
    .widget<PosterCard>(find.byWidgetPredicate(
        (widget) => widget is PosterCard && widget.title == title))
    .highlight;

void main() {
  testWidgets(
      'cliquer le champ pose le voile sur la page sans la quitter, et le '
      'champ garde le focus', (tester) async {
    await _pump(tester);

    await tester.tap(_field);
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSearchSheet), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget,
        reason: 'la page d’avant reste dessous, floutée');
    expect(_fieldHasFocus(tester), isTrue);
    expect(find.text('Ajoutés récemment'), findsOneWidget,
        reason: 'rien de tapé : les derniers ajouts plutôt qu’une icône');
    expect(tester.widget<MediaCard>(find.byType(MediaCard).first).media.title,
        'Dark',
        reason: 'le dernier ajouté en tête');
  });

  testWidgets(
      'la frappe filtre la grille et sélectionne le premier titre, sans '
      'anneau tant que les flèches n’y sont pas', (tester) async {
    await _pump(tester);
    await _type(tester, 'Du');

    expect(
      [
        for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard)))
          card.media.title
      ],
      ['Dune', 'Dunkerque'],
    );
    expect(_highlightOf(tester, 'Dune'), PosterHighlight.lifted);
    expect(_highlightOf(tester, 'Dunkerque'), PosterHighlight.none);
  });

  testWidgets(
      'Bas fait entrer les flèches dans la grille, Haut depuis la première '
      'ligne rend la main au champ', (tester) async {
    await _pump(tester);
    await _type(tester, 'Du');

    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_highlightOf(tester, 'Dune'), PosterHighlight.ringed);
    expect(_fieldHasFocus(tester), isTrue,
        reason: 'le focus ne quitte jamais le champ');

    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_highlightOf(tester, 'Dune'), PosterHighlight.none);
    expect(_highlightOf(tester, 'Dunkerque'), PosterHighlight.ringed);

    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_highlightOf(tester, 'Dunkerque'), PosterHighlight.lifted,
        reason: 'hors de la grille, la sélection reste ce qu’Entrée ouvrirait');

    // Hors de la grille, Gauche et Droite reviennent au curseur du champ.
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_highlightOf(tester, 'Dunkerque'), PosterHighlight.lifted);
  });

  testWidgets(
      'le titre sélectionné se présente à gauche, comme le volet d’une '
      'bibliothèque sur téléviseur', (tester) async {
    await _pump(tester);
    await _type(tester, 'Du');

    LibrarySpotlight spotlight() =>
        tester.widget<LibrarySpotlight>(find.byType(LibrarySpotlight));
    expect(spotlight().media.title, 'Dune');
    expect(
      tester.getRect(find.byType(LibrarySpotlight)).left,
      lessThan(tester.getRect(find.byType(MediaCard).first).left),
      reason: 'le volet à gauche, les affiches à droite',
    );

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(spotlight().media.title, 'Dunkerque',
        reason: 'le volet suit la sélection');
  });

  // Comme le volet d'une bibliothèque (ADR-0156) : un bon tiers de l'écran
  // à 1920 px, et quatre affiches par ligne à côté.
  testWidgets('à 1920 px, le volet a les proportions de l’Apple TV',
      (tester) async {
    await _pump(tester, size: const Size(1920, 1080));
    await _type(tester, 'Du');

    // La marge de page lue là où le volet la lit : le banc règle la
    // surface, pas la MediaQuery.
    final padding =
        AppLayout.pagePadding(tester.element(find.byType(DesktopSearchSheet)));
    expect(tester.getRect(find.byType(LibrarySpotlight)).width,
        closeTo((padding * 2 + 374 + 170) * 1.5, 1));
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid).first);
    expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        4);
  });

  testWidgets('Échap referme le voile et rend la page d’avant', (tester) async {
    await _pump(tester);
    await _type(tester, 'Du');

    await _key(tester, LogicalKeyboardKey.escape);

    expect(find.byType(DesktopSearchSheet), findsNothing);
    expect(find.text('Accueil'), findsOneWidget);
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
    expect(_fieldHasFocus(tester), isFalse);
    final search =
        Provider.of<SearchProvider>(tester.element(_field), listen: false);
    expect(search.isExpanded, isFalse,
        reason: 'l’en-tête rend sa place aux onglets');
  });

  testWidgets('Ctrl K ouvre la recherche depuis la page', (tester) async {
    await _pump(tester);
    expect(_fieldHasFocus(tester), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(_fieldHasFocus(tester), isTrue);
    expect(find.byType(DesktopSearchSheet), findsOneWidget);
  });

  testWidgets('« / » ouvre la recherche depuis la page', (tester) async {
    await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pumpAndSettle();

    expect(_fieldHasFocus(tester), isTrue);
    expect(find.byType(DesktopSearchSheet), findsOneWidget);
  });

  testWidgets('les pastilles gardent les films ou les séries', (tester) async {
    await _pump(tester);
    await _type(tester, 'D');

    expect(find.byType(MediaCard), findsNWidgets(4));
    await tester.tap(find.text('Séries  1', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      [
        for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard)))
          card.media.title
      ],
      ['Dark'],
    );
    expect(_fieldHasFocus(tester), isTrue,
        reason: 'une pastille ne prend pas le focus du champ');

    // Une nouvelle frappe repart de « Tout ».
    await _type(tester, 'Dr');
    expect(find.byType(MediaCard), findsOneWidget);
    expect(
        tester.widget<MediaCard>(find.byType(MediaCard)).media.title, 'Drive');
  });

  testWidgets(
      'une recherche qui a servi revient parmi les recherches récentes, et '
      'un clic la retape', (tester) async {
    await _pump(tester);
    await _type(tester, 'Dune');

    // Une fiche ouverte depuis les résultats : la recherche a servi.
    shellNavigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Fiche')),
    ));
    await tester.pumpAndSettle();
    shellNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_fieldHasFocus(tester), isTrue,
        reason: 'revenu de la fiche, on continue de taper');

    await _type(tester, '');
    expect(find.text('Recherches récentes'), findsOneWidget);
    await tester.tap(find.widgetWithText(RecentSearchChip, 'Dune'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(_field).controller!.text, 'Dune');
    expect(find.byType(MediaCard), findsOneWidget);
  });

  testWidgets(
      'les titres absents suivent la bibliothèque, et Entrée ouvre leur '
      'fiche de demande', (tester) async {
    await _pump(tester, canRequest: true);
    await _type(tester, 'dune');

    expect(find.text('Pas sur le serveur'), findsOneWidget);
    expect(
      tester.getRect(find.text('Pas sur le serveur')).top,
      greaterThan(tester.getRect(find.byType(MediaCard)).bottom),
    );
    expect(
      [
        for (final card in tester
            .widgetList<RequestMediaCard>(find.byType(RequestMediaCard)))
          card.item.title
      ],
      ['Dune : Deuxième partie'],
    );

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(
        _highlightOf(tester, 'Dune : Deuxième partie'), PosterHighlight.ringed);

    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(RequestDetailScreen), findsOneWidget);
  });
}
