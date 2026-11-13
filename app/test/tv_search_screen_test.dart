import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/search/tv_search_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:onyx/widgets/global/tv_tab_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// La recherche d'un téléviseur (ADR-0126) : le champ en tête, qui ouvre le
/// clavier du système, et dessous les résultats rangés par rayons.
///
/// Demandes de l'utilisateur : « un truc comme l'app Emby sur Apple TV », et
/// « ça doit ouvrir le clavier Apple, pour qu'on puisse parler et utiliser la
/// dictée ». Ce banc ouvre la recherche par la loupe de la barre d'onglets,
/// à la taille d'une page de téléviseur.

class _Api extends ApiClient {
  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<List<HomeMediaItem>> getMovies() async => [
        _movie(1, 'Dune', day: 1),
        _movie(2, 'Dunkerque', day: 2),
        _movie(3, 'Drive', day: 3),
        _movie(4, 'Alien', day: 9),
        _movie(5, 'Blade Runner', day: 4),
      ];

  @override
  Future<List<Media>> getShows() async => [
        _media(11, 'Dark', MediaType.show, day: 5),
        _media(12, 'Severance', MediaType.show, day: 6),
      ];
}

Media _media(int id, String title, MediaType type, {required int day}) => Media(
      id: id,
      type: type,
      title: title,
      duration: 6000,
      createdAt: DateTime(2026, 3, day),
    );

HomeMediaItem _movie(int id, String title, {required int day}) => HomeMediaItem(
      media: _media(id, title, MediaType.movie, day: day),
      currentPositionSeconds: 0,
      isFinished: false,
      duration: 6000,
    );

/// La loupe dans sa barre d'onglets : OK dessus ouvre la recherche.
Widget _home() => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: TvRegion.tabs(
          child: TvTabBar(
            children: const [GlassCatalogSearch(tabBarTrigger: true)],
          ),
        ),
      ),
    );

Widget _around(Widget app) {
  final api = _Api();
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
      ChangeNotifierProvider(create: (_) => SearchProvider()),
    ],
    child: app,
  );
}

MediaCard? _focusedCard() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<MediaCard>();

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

/// Les affiches du mur, dans l'ordre de l'écran.
List<String> _posters(WidgetTester tester) {
  final cards = find.byType(MediaCard).evaluate().toList()
    ..sort((a, b) {
      final ra = tester.getRect(find.byWidget(a.widget));
      final rb = tester.getRect(find.byWidget(b.widget));
      final byTop = ra.top.compareTo(rb.top);
      return byTop != 0 ? byTop : ra.left.compareTo(rb.left);
    });
  return [for (final card in cards) (card.widget as MediaCard).media.title];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TvNavHarness.forEachEngine((engine) {
    late List<String> textInput;

    Future<TvNavHarness> open(WidgetTester tester) async {
      textInput = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          textInput.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null));

      final nav = await TvNavHarness.pump(
        tester,
        _home(),
        around: _around,
        engine: engine,
      );
      // La page d'un téléviseur, et non la surface 1920 × 1080 du banc.
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      await nav.select();
      await tester.pumpAndSettle();
      expect(find.byType(TvSearchScreen), findsOneWidget);
      return nav;
    }

    /// Ce que le clavier du système rend : tapé ou dicté.
    Future<void> say(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'OK sur la loupe ouvre la recherche et, avec elle, le clavier du '
        'système', (tester) async {
      await open(tester);

      // Un seul OK : on parle ou l'on tape tout de suite.
      expect(textInput, contains('TextInput.show'));
      final field = _field(tester);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.canRequestFocus, isTrue);
      // Le champ est centré en tête de page.
      final rect = tester.getRect(find.byType(TextField));
      expect(rect.width, TvSearchScreen.fieldWidth);
      expect(rect.center.dx, 640);
      expect(rect.top, TvSearchScreen.fieldTop);
    });

    testWidgets(
        'rien de tapé : les derniers ajouts, le plus récent d\'abord, six '
        'par ligne', (tester) async {
      await open(tester);

      expect(find.text('Ajouts récents'), findsOneWidget);
      expect(_posters(tester).take(4),
          ['Alien', 'Severance', 'Dark', 'Blade Runner']);
      final cards = find.byType(MediaCard);
      final first = tester.getRect(cards.at(0));
      // (1280 − 2 × 48 − 5 × 24) / 6 : une affiche de l'accueil.
      expect(first.left, 48);
      expect(first.width, closeTo(177.3, 0.1));
      // Sous le champ et le titre de son rayon, sans les toucher.
      final title = tester.getRect(find.text('Ajouts récents'));
      expect(title.top,
          greaterThan(tester.getRect(find.byType(TextField)).bottom));
      expect(first.top - first.height * 0.1, greaterThan(title.bottom));
    });

    testWidgets(
        'ce qu\'on tape ou dicte cherche tout de suite, rangé par rayons',
        (tester) async {
      await open(tester);

      await say(tester, 'd');
      // « Blade Runner » aussi : la lettre peut être au milieu du titre.
      expect(find.text('Films · 4'), findsOneWidget);
      expect(find.text('Séries · 1'), findsOneWidget);
      expect(
        _posters(tester),
        unorderedEquals(['Dune', 'Dunkerque', 'Drive', 'Blade Runner', 'Dark']),
      );
      // Les films d'abord, puis les séries sous leur titre.
      expect(_posters(tester).last, 'Dark');
      expect(
        tester.getRect(find.text('Séries · 1')).top,
        greaterThan(tester
            .getRect(find.byWidgetPredicate(
                (w) => w is MediaCard && w.media.title == 'Dune'))
            .bottom),
      );

      await say(tester, 'du');
      expect(find.text('Films · 2'), findsOneWidget);
      // Un rayon sans résultat n'est pas dessiné.
      expect(find.textContaining('Séries'), findsNothing);
      expect(_posters(tester), unorderedEquals(['Dune', 'Dunkerque']));
    });

    testWidgets(
        'valider referme le clavier et pose la télécommande sur le premier '
        'résultat', (tester) async {
      final nav = await open(tester);
      await say(tester, 'du');
      textInput.clear();

      await nav.select();
      await tester.pumpAndSettle();

      expect(textInput, contains('TextInput.hide'));
      expect(_focusedCard()?.media.title, 'Dune');
      expect(_field(tester).focusNode!.hasFocus, isFalse);
    });

    testWidgets(
        'haut depuis les résultats revient au champ sans rouvrir le '
        'clavier ; OK le rouvre', (tester) async {
      final nav = await open(tester);
      await say(tester, 'du');
      await nav.select();
      await tester.pumpAndSettle();
      expect(_focusedCard(), isNotNull);
      textInput.clear();

      await nav.press(TraversalDirection.up);
      await tester.pumpAndSettle();
      expect(_focusedCard(), isNull);
      // Un bouton, pas un champ ouvert : traverser ne fait pas remonter le
      // clavier par-dessus les résultats.
      expect(_field(tester).focusNode!.hasFocus, isFalse);
      expect(textInput, isNot(contains('TextInput.show')));

      await nav.select();
      await tester.pumpAndSettle();
      expect(textInput, contains('TextInput.show'));
      expect(_field(tester).focusNode!.hasFocus, isTrue);
      // Ce qui était tapé est toujours là, pour l'affiner.
      expect(_field(tester).controller!.text, 'du');

      // Et Bas retrouve l'affiche quittée.
      await nav.select();
      await tester.pumpAndSettle();
      expect(_focusedCard()?.media.title, 'Dune');
    });

    testWidgets(
        'rien ne correspond : la page le dit, et valider ne mène '
        'nulle part', (tester) async {
      final nav = await open(tester);

      await say(tester, 'zzz');
      expect(find.text('Aucun résultat'), findsOneWidget);
      expect(
        find.text('Aucun film ou série ne correspond à « zzz ».'),
        findsOneWidget,
      );
      expect(find.byType(MediaCard), findsNothing);

      await nav.select();
      await tester.pumpAndSettle();
      expect(find.byType(TvSearchScreen), findsOneWidget);
      expect(_focusedCard(), isNull);
    });

    testWidgets('Retour depuis les résultats referme la recherche',
        (tester) async {
      final nav = await open(tester);
      await say(tester, 'du');
      await nav.select();
      await tester.pumpAndSettle();
      expect(_focusedCard(), isNotNull);

      await nav.popRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TvSearchScreen), findsNothing);
      // La télécommande retrouve la loupe.
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TvTabBarItem>(),
        isNotNull,
      );
    });
  });
}
