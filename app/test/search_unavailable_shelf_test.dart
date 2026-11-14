import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/navigation/shell_navigator.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/library/search_results_screen.dart';
import 'package:onyx/screens/requests/request_detail_screen.dart';
import 'package:onyx/screens/requests/widgets/request_media_card.dart';
import 'package:onyx/screens/search/tv_search_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:onyx/widgets/global/poster_card.dart';
import 'package:onyx/widgets/global/tv_tab_bar.dart';
import 'package:onyx/widgets/global/unavailable_badge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/search_catalog_fakes.dart';
import 'support/tv_nav_harness.dart';

/// Les titres que le serveur n'a pas, dans les recherches dessinées par
/// Flutter (ADR-0129) : celle d'un téléviseur et celle du téléphone et du
/// bureau. Ils portent le signe que l'app leur donne partout, l'affiche
/// voilée sous la pastille « Indispo », dans un rayon à eux sous ceux de la
/// bibliothèque, et ouvrent leur fiche de demande.
///
/// Demande de l'utilisateur : « si on cherche dans la recherche un média qui
/// n'est pas disponible sur le serveur il doit quand même apparaître mais
/// avec un signe distinctif ».
SearchCatalogApi _server() => SearchCatalogApi(
      movies: [
        libraryMovie(1, 'Dune', tmdbId: 438631),
        libraryMovie(3, 'Drive'),
      ],
      shows: [libraryMedia(11, 'Dark', type: MediaType.show)],
      catalog: {
        'dune': [
          catalogTitle(438631, 'Dune', status: RequestMediaStatus.available),
          catalogTitle(693134, 'Dune : Deuxième partie'),
          catalogTitle(90228, 'Dune : Prophétie',
              type: RequestMediaType.tv, status: RequestMediaStatus.pending),
        ],
        'arrival': [catalogTitle(329865, 'Premier Contact')],
      },
    );

Widget _providers(SearchCatalogApi api, AuthProvider auth, Widget app) {
  return MultiProvider(
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
    child: app,
  );
}

/// La pause dans la frappe qui interroge le catalogue, puis sa réponse.
Future<void> _catalogAnswers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// Les cartes du rayon des absents, dans l'ordre de l'écran.
List<RequestMediaCard> _unavailable(WidgetTester tester) =>
    tester.widgetList<RequestMediaCard>(find.byType(RequestMediaCard)).toList();

String _badgeOf(WidgetTester tester, String title) {
  final card = find.byWidgetPredicate(
    (widget) => widget is RequestMediaCard && widget.item.title == title,
  );
  final badge = find.descendant(
    of: card,
    matching: find.byType(UnavailableBadge),
  );
  return tester
      .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
      .data!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sur un téléviseur', () {
    TvNavHarness.forEachEngine((engine) {
      Future<TvNavHarness> open(
        WidgetTester tester, {
        bool canRequest = true,
      }) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          (call) async => null,
        );
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, null));
        final api = _server();
        final auth = FakeAuth(api, Permissions(requestMedia: canRequest));
        addTearDown(auth.dispose);
        final nav = await TvNavHarness.pump(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: TvRegion.tabs(
                child: TvTabBar(
                  children: const [GlassCatalogSearch(tabBarTrigger: true)],
                ),
              ),
            ),
          ),
          engine: engine,
          around: (app) => _providers(api, auth, app),
        );
        // La page d'un téléviseur, et non la surface 1920 × 1080 du banc.
        tester.view.physicalSize = const Size(1280, 720);
        await tester.pumpAndSettle();
        await nav.select();
        await tester.pumpAndSettle();
        expect(find.byType(TvSearchScreen), findsOneWidget);
        return nav;
      }

      Future<void> say(WidgetTester tester, String text) async {
        await tester.enterText(find.byType(TextField), text);
        await _catalogAnswers(tester);
      }

      testWidgets(
          'les titres absents ont leur rayon sous ceux de la bibliothèque, '
          'voilés, pastille « Indispo » ou « Demandé »', (tester) async {
        await open(tester);
        await say(tester, 'dune');

        expect(find.text('Films · 1'), findsOneWidget);
        expect(find.text('Pas sur le serveur · 2'), findsOneWidget);
        expect(
          tester.getRect(find.text('Pas sur le serveur · 2')).top,
          greaterThan(tester.getRect(find.byType(MediaCard)).bottom),
        );
        expect(
          [for (final card in _unavailable(tester)) card.item.title],
          ['Dune : Deuxième partie', 'Dune : Prophétie'],
        );
        // Le voile commun à tous les titres absents de l'app.
        for (final poster in tester.widgetList<PosterCard>(
          find.descendant(
            of: find.byType(RequestMediaCard),
            matching: find.byType(PosterCard),
          ),
        )) {
          expect(poster.dimmed, isTrue);
        }
        expect(_badgeOf(tester, 'Dune : Deuxième partie'), 'Indispo');
        expect(_badgeOf(tester, 'Dune : Prophétie'), 'Demandé');
        final requested = tester.widget<Text>(find.text('Demandé'));
        expect(requested.style!.color, AppColors.warning);
        // Le titre de la bibliothèque, lui, n'est ni voilé ni marqué.
        expect(
          tester
              .widget<PosterCard>(find.descendant(
                of: find.byType(MediaCard),
                matching: find.byType(PosterCard),
              ))
              .dimmed,
          isFalse,
        );
      });

      testWidgets(
          'Bas depuis la bibliothèque descend dans le rayon des absents, et '
          'OK ouvre la fiche de demande', (tester) async {
        final nav = await open(tester);
        await say(tester, 'dune');

        // Valider pose la télécommande sur le premier résultat.
        await nav.select();
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<MediaCard>()
              ?.media
              .title,
          'Dune',
        );

        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<RequestMediaCard>()
              ?.item
              .title,
          'Dune : Deuxième partie',
        );

        await nav.select();
        await tester.pumpAndSettle();
        expect(find.byType(RequestDetailScreen), findsOneWidget);
      });

      testWidgets(
          'la bibliothèque n’a rien : le rayon des absents est seul, sans '
          '« Aucun résultat »', (tester) async {
        await open(tester);
        await say(tester, 'arrival');

        expect(find.text('Aucun résultat'), findsNothing);
        expect(find.text('Pas sur le serveur · 1'), findsOneWidget);
        expect(find.byType(MediaCard), findsNothing);
      });

      testWidgets(
          'un compte qui ne peut rien demander ne voit que la bibliothèque',
          (tester) async {
        await open(tester, canRequest: false);
        await say(tester, 'dune');

        expect(find.text('Films · 1'), findsOneWidget);
        expect(find.textContaining('Pas sur le serveur'), findsNothing);
        expect(find.byType(RequestMediaCard), findsNothing);
      });
    });
  });

  group('sur le bureau et le téléphone', () {
    Future<void> pump(WidgetTester tester, {bool canRequest = true}) async {
      final api = _server();
      final auth = FakeAuth(api, Permissions(requestMedia: canRequest));
      addTearDown(auth.dispose);
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_providers(
        api,
        auth,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const GlassCatalogSearch(staysAbovePages: true),
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
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await _catalogAnswers(tester);
      expect(find.byType(SearchResultsScreen), findsOneWidget);
    }

    testWidgets(
        'sous les résultats de la bibliothèque, le rayon des titres absents',
        (tester) async {
      await pump(tester);
      await type(tester, 'dune');

      expect(find.text('1 résultat'), findsOneWidget);
      expect(find.text('Pas sur le serveur'), findsOneWidget);
      expect(find.text('Ouvrez un titre pour le demander'), findsOneWidget);
      expect(
        tester.getRect(find.text('Pas sur le serveur')).top,
        greaterThan(tester.getRect(find.byType(MediaCard)).bottom),
      );
      expect(
        [for (final card in _unavailable(tester)) card.item.title],
        ['Dune : Deuxième partie', 'Dune : Prophétie'],
      );
      expect(_unavailable(tester).every((card) => card.marksUnavailable),
          isTrue);
      expect(_badgeOf(tester, 'Dune : Deuxième partie'), 'Indispo');
      expect(_badgeOf(tester, 'Dune : Prophétie'), 'Demandé');
    });

    testWidgets(
        'la bibliothèque n’a rien : la page le dit, et montre ce qui peut '
        'se demander', (tester) async {
      await pump(tester);
      await type(tester, 'arrival');

      expect(find.text('Aucun résultat'), findsNothing);
      expect(find.text('Rien dans la bibliothèque'), findsOneWidget);
      expect(find.byType(MediaCard), findsNothing);
      expect(_unavailable(tester).single.item.title, 'Premier Contact');
    });

    testWidgets('toucher un titre absent ouvre sa fiche de demande',
        (tester) async {
      await pump(tester);
      await type(tester, 'arrival');

      await tester.tap(find.byType(RequestMediaCard));
      await tester.pumpAndSettle();
      expect(find.byType(RequestDetailScreen), findsOneWidget);
    });

    testWidgets(
        'un compte qui ne peut rien demander garde la recherche d’avant',
        (tester) async {
      await pump(tester, canRequest: false);
      await type(tester, 'dune');

      expect(find.text('1 résultat'), findsOneWidget);
      expect(find.text('Pas sur le serveur'), findsNothing);
      expect(find.byType(RequestMediaCard), findsNothing);

      await tester.enterText(find.byType(TextField), 'arrival');
      await _catalogAnswers(tester);
      expect(find.text('Aucun résultat'), findsOneWidget);
    });
  });
}
