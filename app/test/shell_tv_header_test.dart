import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/desktop_window.dart';
import 'package:onyx/models/app_download.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/shell/shell_tabs.dart';
import 'package:onyx/screens/shell/shell_tv_header.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/account_menu.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';
import 'package:onyx/widgets/global/tv_tab_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'en-tête d'un téléviseur (ADR-0117) : la marque à gauche, la pilule des
/// onglets au centre, la recherche et le compte à droite.

class _Api extends ApiClient {
  @override
  Future<List<AppDownload>> getAppDownloads() async => [];

  @override
  Future<List<HomeMediaItem>> getMovies() async => [];

  @override
  Future<List<Media>> getShows() async => [];

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

List<MediaLibrary> _libraries(int count) => [
      for (var i = 1; i <= count; i++)
        MediaLibrary(
          id: i,
          name: count > 3 ? 'Bibliothèque numéro $i' : ['Films', 'Séries', 'Animés'][i - 1],
          kind: i.isEven ? LibraryKind.shows : LibraryKind.movies,
        ),
    ];

/// Monte l'en-tête sur la page d'un téléviseur : 1280 × 720, mode TV.
Future<Map<String, FocusNode>> _pump(
  WidgetTester tester, {
  required List<MediaLibrary> libraries,
  required String selected,
  List<String>? taps,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previous = TvMode.enabled.value;
  TvMode.enabled.value = true;
  addTearDown(() => TvMode.enabled.value = previous);

  final api = _Api();
  final nodes = <String, FocusNode>{};
  addTearDown(() {
    for (final node in nodes.values) {
      node.dispose();
    }
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(api)),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
      ChangeNotifierProvider(create: (_) => SearchProvider()),
    ],
    child: TvScope(
      isTv: true,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topCenter,
              child: ShellTvHeader(
                selected: selected,
                onTabSelected: (tab) => taps?.add(tab),
                libraries: libraries,
                homeProvider: context.watch<HomeProvider>(),
                authProvider: context.watch<AuthProvider>(),
                canDownload: true,
                canUseLists: true,
                canRequestMedia: true,
                nodeFor: (tab) =>
                    nodes.putIfAbsent(tab, () => FocusNode(debugLabel: tab)),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return nodes;
}

/// La capsule d'un onglet : son `AnimatedContainer`.
BoxDecoration _capsule(WidgetTester tester, String label) {
  final container = tester.widget<AnimatedContainer>(find.descendant(
    of: find.widgetWithText(TvTabBarItem, label),
    matching: find.byType(AnimatedContainer),
  ));
  return container.decoration! as BoxDecoration;
}

Color _ink(WidgetTester tester, String label) =>
    tester.widget<RichText>(find.descendant(
      of: find.widgetWithText(TvTabBarItem, label),
      matching: find.byType(RichText),
    )).text.style!.color!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la pilule des onglets est au centre, entre la marque et le compte',
      (tester) async {
    await _pump(tester, libraries: _libraries(3), selected: ShellTabs.home);

    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byType(TvTabBar));
    expect(bar.center.dx, closeTo(640, 0.5));
    expect(bar.height, tvShellHeaderBarHeight);
    expect(tester.getRect(find.byType(GlassBrand)).right, lessThan(bar.left));
    expect(tester.getRect(find.byType(GlassCatalogSearch)).left,
        greaterThan(bar.right));
    expect(tester.getRect(find.byType(AccountMenu)).left,
        greaterThan(bar.right));
    // Accueil, trois bibliothèques, Demandes, Listes, Téléchargements.
    expect(find.byType(TvTabBarItem), findsNWidgets(7));
    expect(find.text('mathis'), findsOneWidget);
  });

  testWidgets('sa hauteur est celle que les pages laissent libre en haut',
      (tester) async {
    await _pump(tester, libraries: _libraries(3), selected: ShellTabs.home);

    final context = tester.element(find.byType(ShellTvHeader));
    expect(
      tester.getSize(find.byType(ShellTvHeader)).height,
      shellHeaderHeight(context),
    );
  });

  testWidgets(
      'douze bibliothèques défilent dans la pilule sans pousser la recherche '
      'ni le compte hors de l’écran', (tester) async {
    final libraries = _libraries(12);
    final nodes = await _pump(
      tester,
      libraries: libraries,
      selected: ShellTabs.library(libraries[1]),
    );

    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byType(TvTabBar));
    expect(bar.center.dx, closeTo(640, 0.5));
    for (final type in [GlassBrand, GlassCatalogSearch, AccountMenu]) {
      final rect = tester.getRect(find.byType(type));
      expect(rect.left, greaterThanOrEqualTo(0), reason: '$type');
      expect(rect.right, lessThanOrEqualTo(1280), reason: '$type');
      expect(rect.overlaps(bar), isFalse, reason: '$type');
    }
    expect(find.byType(TvTabBarItem), findsNWidgets(1 + 12 + 3));

    // Le dernier onglet est hors de la pilule ; lui donner le focus l'amène.
    final last = nodes[ShellTabs.downloads]!;
    expect(tester.getRect(find.text('Téléchargements')).left,
        greaterThan(bar.right));
    last.requestFocus();
    await tester.pump();
    Scrollable.ensureVisible(last.context!);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Téléchargements')).right,
        lessThanOrEqualTo(bar.right));
  });

  testWidgets('l’onglet affiché porte une capsule de verre, les autres rien',
      (tester) async {
    final libraries = _libraries(3);
    await _pump(
      tester,
      libraries: libraries,
      selected: ShellTabs.library(libraries[0]),
    );

    expect(_capsule(tester, 'Films').color, isNot(Colors.transparent));
    expect(_capsule(tester, 'Films').color, isNot(FocusFill.fill));
    expect(_capsule(tester, 'Accueil').color, Colors.transparent);
  });

  testWidgets(
      'une seule capsule est blanche, celle de l’onglet focalisé, et son '
      'texte passe au noir', (tester) async {
    final libraries = _libraries(3);
    final nodes = await _pump(
      tester,
      libraries: libraries,
      selected: ShellTabs.home,
    );

    nodes[ShellTabs.library(libraries[1])]!.requestFocus();
    await tester.pumpAndSettle();

    expect(_capsule(tester, 'Séries').color, FocusFill.fill);
    expect(_ink(tester, 'Séries'), FocusFill.ink);
    expect(_capsule(tester, 'Accueil').color, isNot(FocusFill.fill));
    expect(_capsule(tester, 'Films').color, Colors.transparent);
  });

  testWidgets('s’arrêter sur un onglet l’affiche, sans OK', (tester) async {
    final libraries = _libraries(3);
    final taps = <String>[];
    final nodes = await _pump(
      tester,
      libraries: libraries,
      selected: ShellTabs.home,
      taps: taps,
    );

    nodes[ShellTabs.library(libraries[0])]!.requestFocus();
    await tester.pump();
    expect(taps, isEmpty);
    await tester.pump(TvTabBarItem.selectDelay);

    expect(taps, [ShellTabs.library(libraries[0])]);
  });

  testWidgets('traverser la barre sans s’arrêter ne monte aucun onglet',
      (tester) async {
    final libraries = _libraries(3);
    final taps = <String>[];
    final nodes = await _pump(
      tester,
      libraries: libraries,
      selected: ShellTabs.home,
      taps: taps,
    );

    for (final library in libraries) {
      nodes[ShellTabs.library(library)]!.requestFocus();
      await tester.pump(const Duration(milliseconds: 60));
    }
    nodes[ShellTabs.home]!.requestFocus();
    await tester.pump(const Duration(seconds: 1));

    expect(taps, isEmpty);
  });

  testWidgets('OK sur l’onglet focalisé le choisit, une seule fois',
      (tester) async {
    final libraries = _libraries(3);
    final taps = <String>[];
    final nodes = await _pump(
      tester,
      libraries: libraries,
      selected: ShellTabs.home,
      taps: taps,
    );

    nodes[ShellTabs.lists]!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 1));

    expect(taps, [ShellTabs.lists]);
  });
}
