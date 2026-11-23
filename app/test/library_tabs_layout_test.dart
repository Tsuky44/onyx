import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/app_download.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/navigation/shell_navigator.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/library/library_screen.dart';
import 'package:onyx/screens/shell/desktop_header_search.dart';
import 'package:onyx/screens/shell/shell_desktop_header.dart';
import 'package:onyx/screens/shell/shell_tabs.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/account_menu.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le nombre de bibliothèques et leurs noms sont ceux de l'administrateur du
/// serveur (ADR-0058) : la mise en page ne peut compter ni sur deux onglets,
/// ni sur des noms courts.

class _Api extends ApiClient {
  @override
  Future<List<AppDownload>> getAppDownloads() async => [];

  @override
  Future<List<HomeMediaItem>> getMovies() async => [];

  @override
  Future<List<Media>> getShows() async => [];

  @override
  Future<List<Media>> getLibraryShows(MediaLibrary library) async => [
        Media.fromJson({'id': 1, 'type': 'show', 'title': 'Kaamelott'}),
      ];

  @override
  Future<IndexerStatus> getIndexerStatus() async => IndexerStatus.fromJson({});
}

class _Auth extends AuthProvider {
  _Auth(super.api);

  @override
  User? get currentUser =>
      User(id: 1, username: 'mathis', permissions: Permissions.all);

  @override
  Permissions get permissions => Permissions.all;
}

Widget _providers(_Api api, Widget child) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(api)),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
      ChangeNotifierProvider(create: (_) => SearchProvider()),
      // La recherche du bureau demande au catalogue de demandes ce qu'il
      // connaît, pour un compte qui en a le droit.
      ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'en-tête : douze bibliothèques défilent sans pousser la recherche ni le '
      'compte hors de l’écran', (tester) async {
    _size(tester, const Size(1100, 700));
    final api = _Api();
    final libraries = [
      for (var i = 1; i <= 12; i++)
        MediaLibrary(
          id: i,
          name: 'Bibliothèque numéro $i',
          kind: i.isEven ? LibraryKind.shows : LibraryKind.movies,
        ),
    ];
    final selected = <String>[];
    final nodes = <String, FocusNode>{};
    addTearDown(() {
      for (final node in nodes.values) {
        node.dispose();
      }
    });

    await tester.pumpWidget(_providers(
      api,
      Builder(
        builder: (context) => Align(
          alignment: Alignment.topCenter,
          child: ShellDesktopHeader(
            selected: ShellTabs.library(libraries[1]),
            onTabSelected: selected.add,
            libraries: libraries,
            homeProvider: context.watch<HomeProvider>(),
            authProvider: context.watch<AuthProvider>(),
            canDownload: true,
            canRequestMedia: true,
            nodeFor: (tab) => nodes.putIfAbsent(tab, FocusNode.new),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final type in [DesktopHeaderSearch, AccountMenu]) {
      final rect = tester.getRect(find.byType(type));
      expect(rect.left, greaterThan(0), reason: '$type');
      expect(rect.right, lessThanOrEqualTo(1100), reason: '$type');
    }
    // Chaque bibliothèque a son onglet, sous son nom, et il se choisit.
    expect(find.byType(GlassNavTab), findsNWidgets(1 + 12 + 2));
    await tester.tap(find.text('Bibliothèque numéro 1'));
    expect(selected, [ShellTabs.library(libraries[0])]);
  });

  testWidgets(
      'en-tête : la recherche ouverte prend la place des onglets, au centre, '
      'et garde un retour vers la page quittée (ADR-0139)', (tester) async {
    _size(tester, const Size(1400, 800));
    final api = _Api();
    const libraries = [
      MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies),
      MediaLibrary(id: 2, name: 'Séries', kind: LibraryKind.shows),
    ];
    final selected = <String>[];
    final nodes = <String, FocusNode>{};
    addTearDown(() {
      for (final node in nodes.values) {
        node.dispose();
      }
    });

    // Comme dans `MainShell` : la recherche s'ouvre dans le navigateur de
    // la coquille, sous l'en-tête qui reste au-dessus.
    await tester.pumpWidget(_providers(
      api,
      Builder(
        builder: (context) => Stack(
          children: [
            Positioned.fill(
              child: Navigator(
                key: shellNavigatorKey,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const SizedBox.expand(),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ShellDesktopHeader(
                selected: ShellTabs.library(libraries[1]),
                onTabSelected: selected.add,
                libraries: libraries,
                homeProvider: context.watch<HomeProvider>(),
                authProvider: context.watch<AuthProvider>(),
                canDownload: true,
                canRequestMedia: true,
                nodeFor: (tab) => nodes.putIfAbsent(tab, FocusNode.new),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final idle = tester.getRect(find.byType(DesktopHeaderSearch));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final open = tester.getRect(find.byType(DesktopHeaderSearch));
    expect(open.width, greaterThan(idle.width + 200),
        reason: 'le champ s’élargit en s’ouvrant');
    expect(open.center.dx, lessThan(idle.center.dx),
        reason: 'il glisse vers le centre de l’en-tête');

    // Les onglets s'effacent : ils ne se choisissent plus.
    await tester.tap(find.text('Films'), warnIfMissed: false);
    expect(selected, isEmpty);
    // Sous Windows et macOS, ce clic tombe sur le verre, qui déplace la
    // fenêtre et attend un éventuel second clic pour l'agrandir (ADR-0157) :
    // on laisse passer ce délai, sans quoi son minuteur survit au test.
    await tester.pump(kDoubleTapTimeout);

    // Le retour rappelle la page quittée et y ramène.
    await tester.tap(find.text('Séries').last);
    expect(selected, [ShellTabs.library(libraries[1])]);
  });

  testWidgets(
      'catalogue : un nom de quarante caractères tient sur un téléphone',
      (tester) async {
    _size(tester, const Size(360, 780));
    final api = _Api();
    const library = MediaLibrary(
      id: 5,
      name: 'Documentaires animaliers et de voyage 4K',
      kind: LibraryKind.shows,
    );

    await tester
        .pumpWidget(_providers(api, const LibraryScreen(library: library)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Documentaires animaliers'), findsOneWidget);
    expect(find.text('Kaamelott'), findsOneWidget);

    // Une série n'a pas de position de lecture à elle : pas de tri « En cours ».
    await tester.tap(find.byTooltip('Trier'));
    await tester.pumpAndSettle();
    expect(find.text('En cours'), findsNothing);
    expect(find.text('A → Z'), findsOneWidget);
  });
}
