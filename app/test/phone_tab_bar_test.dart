import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/search/phone/phone_search_row.dart';
import 'package:onyx/screens/search/phone/phone_search_screen.dart';
import 'package:onyx/screens/shell/mobile_bottom_nav.dart';
import 'package:onyx/screens/shell/phone_search.dart';
import 'package:onyx/screens/shell/shell_tabs.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/sliver_scroll_end.dart';
import 'package:provider/provider.dart';

/// La barre d'onglets du téléphone (ADR-0142) : une capsule de verre qui
/// flotte, un rond de recherche qui s'étire sur toute la largeur et devient
/// le champ, posé au-dessus du clavier ; la capsule se réduit quand la page
/// défile vers le bas.
class _FakeApiClient extends ApiClient {
  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<List<HomeMediaItem>> getMovies() async => [
        HomeMediaItem.fromJson({
          'id': 1,
          'type': 'movie',
          'title': 'Dune',
          'duration': 6000,
        }),
      ];

  @override
  Future<List<Media>> getShows() async => [];
}

const _phone = Size(390, 844);
const _films = MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies);

class _Harness {
  _Harness(this.session, this.navigatorKey);

  final PhoneSearchSession session;
  final GlobalKey<NavigatorState> navigatorKey;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool minimized = false,
  VoidCallback? onExpand,
  ValueNotifier<String>? selected,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  addTearDown(tester.view.reset);

  final api = _FakeApiClient();
  final search = SearchProvider();
  final navigatorKey = GlobalKey<NavigatorState>();
  final session = PhoneSearchSession(
    navigatorKey: navigatorKey,
  );
  addTearDown(session.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider.value(value: search),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Navigator(
                  key: navigatorKey,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const Center(child: Text('Accueil')),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<String>(
                  valueListenable: selected ?? ValueNotifier(ShellTabs.home),
                  builder: (context, tab, _) => MobileBottomNav(
                    selected: tab,
                    onTabSelected: (next) => selected?.value = next,
                    libraries: const [_films],
                    canRequestMedia: true,
                    canDownload: true,
                    search: session,
                    minimized: minimized,
                    onExpand: onExpand,
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
  return _Harness(session, navigatorKey);
}

final _round = find.byKey(const ValueKey('phone-search-round'));
final _lens = find.byKey(const ValueKey('phone-tab-lens'));
final _field = find.byType(PhoneSearchField);

void main() {
  testWidgets('une capsule qui flotte, le rond de la recherche à côté',
      (tester) async {
    await _pump(tester);

    final round = tester.getRect(_round);
    expect(round.width, MobileBottomNav.height);
    expect(round.right, closeTo(_phone.width - MobileBottomNav.side, 0.5));
    // Au-dessus du bas de l'écran, pas collée à lui.
    expect(_phone.height - round.bottom, greaterThanOrEqualTo(12));

    final home = tester.getRect(find.text('Accueil').last);
    expect(home.right, lessThan(round.left));
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Demandes'), findsOneWidget);
  });

  testWidgets(
      'le rond s’étire sur toute la largeur, devient le champ, et la page des '
      'résultats s’ouvre derrière', (tester) async {
    final h = await _pump(tester);

    await tester.tap(_round);
    await tester.pump();
    expect(h.session.isOpen, isTrue);
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(PhoneSearchField),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);
    final bubble = tester.getRect(find.byType(PhoneSearchField));
    expect(bubble.left, closeTo(MobileBottomNav.side, 1));
    expect(bubble.right, closeTo(_phone.width - MobileBottomNav.side, 1));
    // Les onglets se sont effacés sous la bulle.
    expect(find.text('Demandes').hitTestable(), findsNothing);

    // Le champ a la main : le clavier monte.
    expect(h.session.focusNode.hasFocus, isTrue);
    expect(find.byType(PhoneSearchScreen), findsOneWidget);

    // La page suit la frappe.
    await tester.enterText(field, 'dune');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PhoneSearchRow, 'Dune'), findsOneWidget);
  });

  testWidgets('la croix referme : page partie, frappe effacée, rond revenu',
      (tester) async {
    final h = await _pump(tester);
    await tester.tap(_round);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Fermer la recherche'));
    await tester.pumpAndSettle();

    expect(h.session.isOpen, isFalse);
    expect(h.session.controller.text, isEmpty);
    expect(find.byType(PhoneSearchScreen), findsNothing);
    expect(_round, findsOneWidget);
    expect(find.text('Demandes').hitTestable(), findsOneWidget);
  });

  testWidgets('Retour referme aussi la recherche', (tester) async {
    final h = await _pump(tester);
    await tester.tap(_round);
    await tester.pumpAndSettle();

    h.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(h.session.isOpen, isFalse);
    expect(_round, findsOneWidget);
  });

  testWidgets('la lentille glisse d’un onglet à l’autre, en s’étirant',
      (tester) async {
    final selected = ValueNotifier(ShellTabs.home);
    addTearDown(selected.dispose);
    await _pump(tester, selected: selected);

    final home = tester.getRect(_lens);
    expect(home.center.dx,
        closeTo(tester.getCenter(find.text('Accueil').last).dx, 1));

    await tester.tap(find.text('Demandes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final moving = tester.getRect(_lens);
    // En route : partie de l'accueil, pas encore arrivée, et plus large
    // qu'un onglet.
    expect(moving.left, greaterThan(home.left));
    expect(moving.width, greaterThan(home.width + 4));

    await tester.pumpAndSettle();
    final requests = tester.getRect(_lens);
    expect(requests.width, closeTo(home.width, 0.5));
    expect(requests.center.dx,
        closeTo(tester.getCenter(find.text('Demandes')).dx, 1));
  });

  testWidgets(
      'la croix referme à l’envers de l’ouverture : le clavier descend, puis '
      'la bulle redevient un rond', (tester) async {
    final h = await _pump(tester);
    await tester.tap(_round);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 1008);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Fermer la recherche'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Le clavier n'est pas encore descendu : la bulle reste entière, sur lui.
    expect(h.session.isOpen, isFalse);
    expect(_field, findsOneWidget);
    expect(tester.getRect(_field).left, closeTo(MobileBottomNav.side, 1));

    tester.view.resetViewInsets();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Il est parti : elle se resserre vers le rond, en route.
    final shrinking = tester
        .getSize(find.ancestor(of: _round, matching: find.byType(ClipRRect)))
        .width;
    expect(shrinking, greaterThan(MobileBottomNav.height + 10));
    expect(shrinking, lessThan(_phone.width - 2 * MobileBottomNav.side));

    await tester.pumpAndSettle();
    expect(_round, findsOneWidget);
    expect(find.text('Demandes').hitTestable(), findsOneWidget);
  });

  testWidgets(
      'une fiche ouverte depuis les résultats rend la capsule ; le retour '
      'redéploie la bulle sans rouvrir le clavier', (tester) async {
    final h = await _pump(tester);
    await tester.tap(_round);
    await tester.pumpAndSettle();
    expect(h.session.focusNode.hasFocus, isTrue);

    h.navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Fiche')),
    ));
    await tester.pumpAndSettle();
    expect(h.session.isOpen, isTrue);
    expect(h.session.isCovered, isTrue);
    expect(h.session.focusNode.hasFocus, isFalse);
    expect(_round, findsOneWidget);
    expect(_field, findsNothing);
    expect(find.text('Demandes').hitTestable(), findsOneWidget);

    h.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(h.session.isExpanded, isTrue);
    expect(_field, findsOneWidget);
    expect(h.session.focusNode.hasFocus, isFalse,
        reason: 'le clavier cacherait les résultats retrouvés');
  });

  testWidgets('le rond touché depuis une fiche ramène aux résultats',
      (tester) async {
    final h = await _pump(tester);
    await tester.tap(_round);
    await tester.pumpAndSettle();
    h.navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Fiche')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(_round);
    await tester.pumpAndSettle();
    expect(find.text('Fiche'), findsNothing);
    expect(find.byType(PhoneSearchScreen), findsOneWidget);
    expect(h.session.isExpanded, isTrue);
    expect(h.session.focusNode.hasFocus, isTrue);
  });

  testWidgets('pendant la recherche, la bulle reste au-dessus du clavier',
      (tester) async {
    final h = await _pump(tester);
    await tester.tap(_round);
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 1008);
    await tester.pumpAndSettle();

    expect(h.session.isOpen, isTrue);
    expect(find.byType(PhoneSearchField), findsOneWidget);
    final bubble = tester.getRect(find.byType(PhoneSearchField));
    expect(bubble.bottom, lessThanOrEqualTo(_phone.height - 1008 / 3));
  });

  testWidgets('la capsule réduite ne garde que l’onglet affiché',
      (tester) async {
    var expanded = 0;
    await _pump(tester, minimized: true, onExpand: () => expanded++);

    final minimized = find.byKey(const ValueKey('phone-tab-bar-minimized'));
    expect(minimized, findsOneWidget);
    expect(find.text('Demandes'), findsNothing);
    expect(tester.getSize(minimized).width,
        lessThanOrEqualTo(MobileBottomNav.height));
    expect(_round, findsOneWidget);

    await tester.tap(minimized);
    expect(expanded, 1);
  });

  testWidgets('la page qui défile vers le bas réduit la capsule, remonter la '
      'rend', (tester) async {
    final minimized = ValueNotifier(false);
    addTearDown(minimized.dispose);
    await tester.pumpWidget(MaterialApp(
      home: TabBarScrollWatch(
        minimized: minimized,
        child: ListView(
          children: [for (var i = 0; i < 60; i++) SizedBox(height: 80, child: Text('$i'))],
        ),
      ),
    ));

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(minimized.value, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(minimized.value, isFalse);
  });

  testWidgets('les pages finissent au-dessus de la capsule', (tester) async {
    double? extent;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(bottom: 84)),
      child: Builder(builder: (context) {
        extent = SliverScrollEnd.extentOf(context);
        return const SizedBox();
      }),
    ));
    expect(extent, 48 + 84);
    expect(
      MobileBottomNav.reserveFor(
        const EdgeInsets.only(bottom: 34),
        keyboardOpen: false,
        searching: false,
      ),
      20 + MobileBottomNav.height + 12,
    );
    // Les trois boutons de navigation d'Android : au-dessus d'eux, pas dessus.
    expect(
      MobileBottomNav.bottomFor(const EdgeInsets.only(bottom: 48)),
      greaterThan(48),
    );
    expect(
      MobileBottomNav.reserveFor(
        EdgeInsets.zero,
        keyboardOpen: true,
        searching: false,
      ),
      0,
      reason: 'un autre champ a le clavier : la barre s’efface',
    );
  });
}
