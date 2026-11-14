import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/library/movie_detail_screen.dart';
import 'package:onyx/screens/requests/request_detail_screen.dart';
import 'package:onyx/screens/search/tv_search_screen.dart';
import 'package:onyx/screens/search/tv_system_search_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/services/tv_system_search.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:onyx/widgets/global/tv_tab_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/search_catalog_fakes.dart';
import 'support/tv_nav_harness.dart';

/// La recherche de l'Apple TV (ADR-0129) : l'écran de recherche du système,
/// que l'hôte natif présente par-dessus Flutter. Ce banc joue l'hôte : il
/// note ce que Dart lui demande par le canal `onyx/tv_search`, et lui dit ce
/// qu'on tape, ce qu'on choisit et quand on s'en va.
///
/// Demande de l'utilisateur : « je veux la même recherche que YouTube, on a
/// le clavier ou on peut utiliser l'iPhone pour noter ou sinon Siri et on a
/// les résultats ici », et « si on cherche un média qui n'est pas disponible
/// sur le serveur il doit quand même apparaître mais avec un signe
/// distinctif ».
class _Host {
  _Host(this.tester, {this.accepts = true}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        calls.add(call);
        return call.method == 'present' ? accepts : null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));
  }

  static const MethodChannel _channel = MethodChannel('onyx/tv_search');

  final WidgetTester tester;

  /// Faux pour un hôte qui ne montre pas l'écran.
  final bool accepts;
  final List<MethodCall> calls = <MethodCall>[];

  List<String> get methods => [for (final call in calls) call.method];

  /// Ce que l'écran montre : le dernier contenu reçu. Les messages ont
  /// traversé le codec du canal, comme vers le vrai hôte.
  Map<Object?, Object?> get content {
    for (final call in calls.reversed) {
      if (call.method == 'update') return call.arguments as Map;
      if (call.method == 'present') {
        return (call.arguments as Map)['content'] as Map;
      }
    }
    return fail('l’hôte n’a rien reçu à montrer');
  }

  List<Map<Object?, Object?>> get shelves =>
      (content['sections'] as List).cast<Map<Object?, Object?>>();

  List<String> get shelfTitles =>
      [for (final shelf in shelves) shelf['title'] as String];

  List<Map<Object?, Object?>> posters(String shelfId) => [
        for (final shelf in shelves)
          if (shelf['id'] == shelfId)
            ...(shelf['items'] as List).cast<Map<Object?, Object?>>(),
      ];

  Map<Object?, Object?> poster(String title) => [
        for (final shelf in shelves)
          ...(shelf['items'] as List).cast<Map<Object?, Object?>>(),
      ].firstWhere((item) => item['title'] == title);

  /// Ce que l'écran natif fait savoir : `query`, `select`, `closed`.
  Future<void> says(String method, [Object? arguments]) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    await tester.pump();
  }
}

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

SearchCatalogApi _server({int moviesNamedDune = 0}) => SearchCatalogApi(
      movies: [
        libraryMovie(1, 'Dune',
            tmdbId: 438631,
            day: 1,
            posterUrl: 'https://image.tmdb.org/t/p/original/dune.jpg',
            watchedSeconds: 2700),
        libraryMovie(3, 'Dunkerque', day: 2, finished: true),
        libraryMovie(4, 'Drive', day: 3),
        libraryMovie(5, 'Alien', day: 9),
        libraryMovie(6, 'Blade Runner', day: 4),
        for (var i = 0; i < moviesNamedDune; i++)
          libraryMovie(100 + i, 'Dune, copie $i'),
      ],
      shows: [
        libraryMedia(11, 'Dark', type: MediaType.show, day: 5),
        libraryMedia(12, 'Severance', type: MediaType.show, day: 6),
      ],
      catalog: {
        'dune': [
          catalogTitle(438631, 'Dune', status: RequestMediaStatus.available),
          catalogTitle(693134, 'Dune : Deuxième partie'),
          catalogTitle(90228, 'Dune : Prophétie',
              type: RequestMediaType.tv, status: RequestMediaStatus.pending),
        ],
      },
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TvSystemSearch.debugSupported = true;
    MediaDetailsCache.clear();
  });
  tearDown(() {
    TvSystemSearch.debugSupported = null;
    MediaDetailsCache.clear();
  });

  TvNavHarness.forEachEngine((engine) {
    late SearchCatalogApi api;

    /// Ouvre la recherche par la loupe, sur un compte qui peut demander des
    /// titres ou non.
    Future<(TvNavHarness, _Host)> open(
      WidgetTester tester, {
      bool canRequest = true,
      bool hostAccepts = true,
      SearchCatalogApi? server,
    }) async {
      api = server ?? _server();
      final host = _Host(tester, accepts: hostAccepts);
      final auth = FakeAuth(api, Permissions(requestMedia: canRequest));
      addTearDown(auth.dispose);
      final lists = WatchListsProvider(api)..debugMarkSupported();
      addTearDown(lists.dispose);
      final nav = await TvNavHarness.pump(
        tester,
        _home(),
        engine: engine,
        around: (app) => MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<WatchListsProvider>.value(value: lists),
            ChangeNotifierProvider<DownloadManager>.value(
                value: DownloadManager.instance),
            ChangeNotifierProvider(create: (_) => HomeProvider(api)),
            ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
            ChangeNotifierProvider(create: (_) => SearchProvider()),
            ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();
      await nav.select();
      await tester.pumpAndSettle();
      return (nav, host);
    }

    /// La pause dans la frappe qui interroge le catalogue, puis sa réponse.
    Future<void> catalogAnswers(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    testWidgets(
        'OK sur la loupe présente l’écran de recherche du système, les '
        'derniers ajouts sous son clavier', (tester) async {
      final (_, host) = await open(tester);

      expect(find.byType(TvSystemSearchScreen), findsOneWidget);
      // Ni champ ni clavier de Flutter : ceux de tvOS sont devant.
      expect(find.byType(TvSearchScreen), findsNothing);
      expect(find.byType(TextField), findsNothing);

      final present = host.calls.firstWhere((c) => c.method == 'present');
      final arguments = present.arguments as Map;
      expect(arguments['placeholder'], 'Rechercher un film ou une série…');
      // Les couleurs de l'app, pas celles du système.
      expect(
        (arguments['colors'] as Map)['background'],
        AppColors.background.toARGB32(),
      );
      expect(host.shelfTitles, ['Ajouts récents']);
      expect(
        [for (final item in host.posters('recent')) item['title']].take(4),
        ['Alien', 'Severance', 'Dark', 'Blade Runner'],
      );
    });

    testWidgets(
        'ce qu’on tape, dicte ou saisit depuis un iPhone cherche tout de '
        'suite, rangé par rayons', (tester) async {
      final (_, host) = await open(tester);

      await host.says('query', 'd');
      expect(host.shelfTitles, ['Films · 4', 'Séries · 1']);
      expect(
        [for (final item in host.posters('movies')) item['title']],
        unorderedEquals(['Dune', 'Dunkerque', 'Drive', 'Blade Runner']),
      );
      expect(host.poster('Dark')['subtitle'], '2021');

      await host.says('query', 'zzz');
      expect(host.shelves, isEmpty);
      expect(host.content['emptyTitle'], 'Aucun résultat');
      expect(
        host.content['emptyMessage'],
        'Aucun film ou série ne correspond à « zzz ».',
      );
    });

    testWidgets(
        'un titre que le serveur n’a pas a son rayon : affiche voilée, '
        'pastille « Indispo », ou « Demandé » s’il est déjà en route',
        (tester) async {
      final (_, host) = await open(tester);

      await host.says('query', 'dune');
      expect(host.shelfTitles, ['Films · 1'],
          reason: 'la bibliothèque répond sans attendre le catalogue');
      await catalogAnswers(tester);

      expect(api.asked, ['dune']);
      expect(host.shelfTitles, ['Films · 1', 'Pas sur le serveur · 2']);
      // Le titre que la bibliothèque a déjà n'y revient pas.
      expect(
        [for (final item in host.posters('unavailable')) item['title']],
        ['Dune : Deuxième partie', 'Dune : Prophétie'],
      );

      final absent = host.poster('Dune : Deuxième partie');
      expect(absent['dimmed'], isTrue);
      expect(absent['badge'], 'Indispo');
      expect(absent['badgeTint'], isNull);
      expect(absent['subtitle'], 'Film · 2024');

      final requested = host.poster('Dune : Prophétie');
      expect(requested['dimmed'], isTrue);
      expect(requested['badge'], 'Demandé');
      expect(requested['badgeTint'], AppColors.warning.toARGB32());
      expect(requested['subtitle'], 'Série · 2024');

      final held = host.poster('Dune');
      expect(held['dimmed'], isFalse);
      expect(held['badge'], isNull);
    });

    testWidgets(
        'un compte qui ne peut rien demander ne voit que la bibliothèque',
        (tester) async {
      final (_, host) = await open(tester, canRequest: false);

      await host.says('query', 'dune');
      await catalogAnswers(tester);

      expect(api.asked, isEmpty);
      expect(host.shelfTitles, ['Films · 1']);
    });

    testWidgets(
        'une affiche dit où l’on en est du film, et son image est demandée '
        'à la taille où l’écran la dessine', (tester) async {
      final (_, host) = await open(tester);
      await host.says('query', 'dun');

      final dune = host.poster('Dune');
      expect(dune['progress'], closeTo(0.45, 0.001));
      expect(dune['watched'], isFalse);
      // 14 % de 1920 px : la plus petite taille de TMDB qui les couvre.
      expect(dune['poster'], 'https://image.tmdb.org/t/p/w300/dune.jpg');

      final dunkerque = host.poster('Dunkerque');
      expect(dunkerque['watched'], isTrue);
      expect(dunkerque['progress'], isNull);
    });

    testWidgets(
        'un rayon s’arrête à sa limite, et son titre dit le vrai compte',
        (tester) async {
      final (_, host) =
          await open(tester, server: _server(moviesNamedDune: 150));

      await host.says('query', 'dune');
      expect(host.shelfTitles, ['Films · 151']);
      expect(
        host.posters('movies'),
        hasLength(TvSystemSearchScreen.shelfLimit),
      );
    });

    testWidgets(
        'choisir une affiche ouvre sa fiche : l’écran du système se retire, '
        'puis revient quand la fiche se referme', (tester) async {
      final (nav, host) = await open(tester);
      await host.says('query', 'dune');
      host.calls.clear();

      await host.says('select', 'm1');
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailScreen), findsOneWidget);
      expect(host.methods, contains('hide'));
      expect(host.methods, isNot(contains('close')));

      host.calls.clear();
      await nav.back();
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailScreen), findsNothing);
      expect(find.byType(TvSystemSearchScreen), findsOneWidget);
      expect(host.methods, contains('show'));
      expect(host.methods, isNot(contains('hide')));
    });

    testWidgets(
        'choisir un titre que le serveur n’a pas ouvre sa fiche de demande',
        (tester) async {
      final (_, host) = await open(tester);
      await host.says('query', 'dune');
      await catalogAnswers(tester);

      await host.says('select', 'rmovie693134');
      await tester.pumpAndSettle();

      expect(find.byType(RequestDetailScreen), findsOneWidget);
      expect(host.methods, contains('hide'));
    });

    testWidgets(
        'au retour d’une fiche de demande, le catalogue est relu : '
        '« Indispo » devient « Demandé »', (tester) async {
      final (nav, host) = await open(tester);
      await host.says('query', 'dune');
      await catalogAnswers(tester);
      await host.says('select', 'rmovie693134');
      await tester.pumpAndSettle();

      // Le titre a été demandé depuis sa fiche.
      api.catalog['dune'] = [
        catalogTitle(693134, 'Dune : Deuxième partie',
            status: RequestMediaStatus.pending),
      ];
      await nav.back();
      await tester.pumpAndSettle();

      expect(api.asked, ['dune', 'dune']);
      expect(host.poster('Dune : Deuxième partie')['badge'], 'Demandé');
    });

    testWidgets(
        'Retour sur la télécommande referme la recherche et rend la loupe',
        (tester) async {
      final (_, host) = await open(tester);
      host.calls.clear();

      await host.says('closed');
      await tester.pumpAndSettle();

      expect(find.byType(TvSystemSearchScreen), findsNothing);
      // L'écran s'est déjà retiré de lui-même : il n'y a rien à refermer.
      expect(host.methods, isNot(contains('close')));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'tv-search-header-button',
      );
    });

    testWidgets(
        'une touche Retour arrivée jusqu’à Flutter referme aussi l’écran du '
        'système : on ne reste jamais devant une page vide', (tester) async {
      final (nav, host) = await open(tester);
      host.calls.clear();

      await nav.back();
      await tester.pumpAndSettle();

      expect(find.byType(TvSystemSearchScreen), findsNothing);
      expect(host.methods, contains('close'));
    });

    testWidgets(
        'si l’hôte ne montre pas l’écran, la recherche dessinée par Flutter '
        'prend sa place', (tester) async {
      final (_, host) = await open(tester, hostAccepts: false);

      expect(host.methods, contains('present'));
      expect(find.byType(TvSearchScreen), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Ajouts récents'), findsOneWidget);
    });

    testWidgets('hors Apple TV, la loupe ouvre la recherche de Flutter',
        (tester) async {
      TvSystemSearch.debugSupported = false;
      final (_, host) = await open(tester);

      expect(host.calls, isEmpty);
      expect(find.byType(TvSystemSearchScreen), findsNothing);
      expect(find.byType(TvSearchScreen), findsOneWidget);
    });
  });
}
