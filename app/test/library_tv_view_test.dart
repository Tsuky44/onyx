import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/screens/library/library_screen.dart';
import 'package:onyx/screens/library/widgets/catalog_header.dart';
import 'package:onyx/screens/library/widgets/library_spotlight.dart';
import 'package:onyx/screens/library/widgets/library_tv_view.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:onyx/widgets/global/poster_card.dart';
import 'package:onyx/widgets/global/skeleton.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// Une bibliothèque sur téléviseur (ADR-0125) : la fiche du titre que la
/// télécommande désigne dans un volet à gauche, la grille d'affiches à droite.
///
/// Retours de l'utilisateur sur Apple TV : la grille de sept affiches par
/// ligne était « trop remplie, trop compacte » ; puis, la fiche posée en tête
/// d'écran, « on ne voit pas super bien » et le défilement était « trop
/// brut ». Ce banc monte le vrai [LibraryScreen] sous un onglet, à la taille
/// d'une page de téléviseur.

class _Api extends ApiClient {
  _Api(this.count);

  final int count;

  /// Les fiches demandées au catalogue, dans l'ordre.
  final List<int> detailsAsked = <int>[];

  /// Posé par un test qui veut voir la page pendant le chargement.
  Completer<void>? gate;

  @override
  Future<List<HomeMediaItem>> getLibraryMovies(MediaLibrary library) async {
    await gate?.future;
    return [for (var i = 1; i <= count; i++) _movie(i)];
  }

  @override
  Future<MediaDetails> getMediaDetails(int mediaId) async {
    detailsAsked.add(mediaId);
    return MediaDetails(
      id: mediaId,
      type: MediaType.movie,
      title: 'Film $mediaId',
      overview: 'Le résumé du catalogue pour le film $mediaId.',
      releaseDate: '2023-05-0$mediaId'.substring(0, 10),
      runtime: 128,
      voteAverage: 7.8,
      genres: const ['Thriller', 'Drame', 'Action'],
    );
  }

  @override
  Future<MediaTracks> getMediaTracks(int mediaId) async =>
      throw Exception('pas de pistes dans ce banc');
}

HomeMediaItem _movie(int id) => HomeMediaItem(
      media: Media(
        id: id,
        type: MediaType.movie,
        title: 'Film $id',
        overview: 'Le résumé de la bibliothèque pour le film $id.',
        duration: 6000,
        // Le plus récent d'abord : le film 1 est le premier de la grille.
        createdAt: DateTime(2026, 3, 1).subtract(Duration(days: id)),
      ),
      currentPositionSeconds: 0,
      isFinished: false,
      duration: 6000,
    );

const _library = MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies);

/// La hauteur de l'onglet posé au-dessus de la page.
const double _tabHeight = 48;

Widget _tab(_Api api) => MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
        ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
      ],
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TvRegion.tabs(
              child: Padding(
                padding: const EdgeInsets.only(left: 48),
                child: TvFocusable(
                  autofocus: true,
                  entry: true,
                  onSelect: () {},
                  child: const TvTestTile('Films', height: _tabHeight),
                ),
              ),
            ),
            const Expanded(
              child: TvRegion.page(
                child: LibraryScreen(library: _library, embedded: true),
              ),
            ),
          ],
        ),
      ),
    );

MediaCard? _focusedCard() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<MediaCard>();

String? _focused() =>
    _focusedCard()?.media.title ??
    focusedLabelOf(FocusManager.instance.primaryFocus);

/// Le rectangle de l'affiche de [title], à l'écran.
Rect _poster(WidgetTester tester, String title) => tester.getRect(
    find.byWidgetPredicate((w) => w is MediaCard && w.media.title == title));

/// L'en-tête commun des catalogues. `find.byType(CatalogHeader)` ne trouve pas
/// un `CatalogHeader<_SortOption>`, dont le type est privé à l'écran : d'où le
/// prédicat.
Finder get _catalogHeader =>
    find.byWidgetPredicate((widget) => widget is CatalogHeader);

Finder _inSpotlight(Finder finder) =>
    find.descendant(of: find.byType(LibrarySpotlight), matching: finder);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MediaDetailsCache.clear();
  });

  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> open(WidgetTester tester, _Api api) async {
      final nav = await TvNavHarness.pump(tester, _tab(api), engine: engine);
      // La page d'un téléviseur, et non la surface 1920 × 1080 du banc.
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryTvView), findsOneWidget);
      return nav;
    }

    testWidgets(
        'quatre affiches par ligne à droite du volet, deux rangées et le '
        'haut de la troisième', (tester) async {
      await open(tester, _Api(20));

      final view = tester.getRect(find.byType(LibraryTvView));
      final first = _poster(tester, 'Film 1');
      final fourth = _poster(tester, 'Film 4');
      final fifth = _poster(tester, 'Film 5');
      // Le volet : 48 de gouttière, 374 de texte, 48 avant la grille. Puis
      // (1280 − 470 − 48 − 3 × 24) / 4.
      expect(first.left, 470);
      expect(first.width, closeTo(172.5, 0.1));
      expect(first.height, closeTo(258.75, 0.1));
      expect(fourth.top, first.top);
      expect(fourth.right, closeTo(1280 - 48, 0.1));
      expect(fifth.left, first.left);
      expect(fifth.top - first.bottom, LibraryTvView.rowGap);
      // La grille prend toute la hauteur : deux rangées entières, et sur
      // les 720 px d'un écran (ce banc en prend 48 pour son onglet) la
      // troisième pointe en bas.
      expect(fifth.bottom, lessThan(view.bottom));
      final thirdRow = fifth.bottom + LibraryTvView.rowGap - view.top;
      expect(thirdRow, lessThan(720 - 24));
      expect(thirdRow + first.height, greaterThan(720));
      // Plus de titre de page ni de cartouche sur les affiches : la fiche les
      // remplace.
      expect(_catalogHeader, findsNothing);
      expect(
        tester.widgetList<PosterCard>(find.byType(PosterCard)).every(
              (card) => card.hoverDetails == null,
            ),
        isTrue,
      );
    });

    testWidgets(
        'la fiche du volet présente la première affiche, puis celle que la '
        'télécommande désigne', (tester) async {
      final api = _Api(20);
      final nav = await open(tester, api);

      expect(_inSpotlight(find.text('FILMS · 20 TITRES')), findsOneWidget);
      expect(_inSpotlight(find.text('Film 1')), findsOneWidget);
      // Le texte tient dans le volet, à gauche de la grille.
      final title = tester.getRect(_inSpotlight(find.text('Film 1')));
      expect(title.left, 48);
      expect(title.right, lessThanOrEqualTo(48 + LibraryTvView.textWidth));

      await nav.press(TraversalDirection.down);
      expect(_focused(), 'Film 1');
      await nav.press(TraversalDirection.right);
      await nav.press(TraversalDirection.right);
      expect(_focused(), 'Film 3');

      // Ce que la bibliothèque sait déjà s'écrit tout de suite.
      expect(_inSpotlight(find.text('Film 3')), findsOneWidget);
      expect(_inSpotlight(find.text('Film 1')), findsNothing);
      expect(
        _inSpotlight(
            find.text('Le résumé de la bibliothèque pour le film 3.')),
        findsOneWidget,
      );
      expect(_inSpotlight(find.text('Thriller, Drame')), findsNothing);

      // Le focus posé, la fiche du catalogue arrive : genres (deux au plus),
      // note, durée.
      await tester.pump(LibrarySpotlight.settle);
      await tester.pump();
      expect(api.detailsAsked, contains(3));
      expect(_inSpotlight(find.text('Thriller, Drame')), findsOneWidget);
      expect(_inSpotlight(find.text('7,8')), findsOneWidget);
      expect(
        _inSpotlight(find.text('Le résumé du catalogue pour le film 3.')),
        findsOneWidget,
      );
    });

    testWidgets('traverser une rangée ne demande pas une fiche par affiche',
        (tester) async {
      final api = _Api(20);
      final nav = await open(tester, api);

      await nav.press(TraversalDirection.down);
      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(_focused(), 'Film 4');
      expect(api.detailsAsked, isEmpty);

      await tester.pump(LibrarySpotlight.settle);
      await tester.pump();
      expect(api.detailsAsked, [4]);
    });

    testWidgets('descendre pose la rangée suivante à la place de la première',
        (tester) async {
      final nav = await open(tester, _Api(40));
      final firstRow = _poster(tester, 'Film 1').top;
      final view = tester.getRect(find.byType(LibraryTvView));

      await nav.press(TraversalDirection.down);
      expect(_focused(), 'Film 1');

      for (final title in ['Film 5', 'Film 9', 'Film 13']) {
        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(_focused(), title);
        final poster = _poster(tester, title);
        if (engine == TvNavEngine.legacy) {
          // L'affiche focalisée se pose toujours à la même hauteur : chaque
          // pas fait défiler la grille d'une rangée, ni plus ni moins.
          expect(poster.top, closeTo(firstRow, 0.5), reason: title);
        } else {
          // dpad ne sait que ramener « au plus près » : l'affiche est entière
          // à l'écran, c'est ce qu'on lui demande.
          expect(poster.top, greaterThanOrEqualTo(firstRow - 0.5));
          expect(poster.bottom, lessThanOrEqualTo(view.bottom));
        }
      }
    });

    testWidgets('la dernière rangée reste entière à l\'écran', (tester) async {
      // Treize films : la quatrième rangée n'en a qu'un.
      final nav = await open(tester, _Api(13));
      final view = tester.getRect(find.byType(LibraryTvView));

      for (var i = 0; i < 4; i++) {
        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
      }
      expect(_focused(), 'Film 13');
      expect(_poster(tester, 'Film 13').bottom, lessThan(view.bottom));
      // La rangée du dessus reste visible : la grille ne finit pas sur un
      // écran presque vide.
      expect(_poster(tester, 'Film 9').top, greaterThanOrEqualTo(view.top));
    });

    testWidgets(
        'le tri est une capsule en haut du volet, sur la ligne de la '
        'première rangée', (tester) async {
      await open(tester, _Api(20));

      final sort = tester.getRect(find.byType(OutlinedButton));
      final first = _poster(tester, 'Film 1');
      expect(sort.left, 48);
      expect(sort.right, lessThan(first.left));
      expect(sort.top, first.top);
      // Au-dessus du surtitre de la fiche, sans le toucher.
      final eyebrow =
          tester.getRect(_inSpotlight(find.text('FILMS · 20 TITRES')));
      expect(sort.bottom, lessThan(eyebrow.top));
      expect(
        find.descendant(
            of: find.byType(OutlinedButton), matching: find.text('Récents')),
        findsOneWidget,
      );
    });

    testWidgets(
        'gauche depuis la première colonne mène au tri, droite ramène à '
        'l\'affiche quittée', (tester) async {
      final nav = await open(tester, _Api(20));
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.down);
      await tester.pumpAndSettle();
      expect(_focused(), 'Film 5');

      await nav.press(TraversalDirection.left);
      expect(_focused(), 'Récents');
      // La fiche présente toujours l'affiche quittée.
      expect(_inSpotlight(find.text('Film 5')), findsOneWidget);

      await nav.press(TraversalDirection.right);
      await tester.pumpAndSettle();
      expect(_focused(), 'Film 5');

      // Bas depuis le tri rentre lui aussi dans la rangée quittée : le focus
      // part dans le sens de la flèche.
      await nav.press(TraversalDirection.left);
      expect(_focused(), 'Récents');
      await nav.press(TraversalDirection.down);
      await tester.pumpAndSettle();
      expect(_focused(), 'Film 5');
    });

    testWidgets('haut depuis le tri monte aux onglets', (tester) async {
      final nav = await open(tester, _Api(20));
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.left);
      expect(_focused(), 'Récents');

      await nav.press(TraversalDirection.up);
      await tester.pumpAndSettle();
      expect(_focused(), 'Films');
      // Et Bas, depuis l'onglet, entre dans la grille, pas sur le tri.
      await nav.press(TraversalDirection.down);
      await tester.pumpAndSettle();
      expect(_focusedCard(), isNotNull);
    });

    testWidgets('un geste qui court le long de la rangée s\'arrête à son bord',
        (tester) async {
      final nav = await open(tester, _Api(20));
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.right);
      await nav.press(TraversalDirection.right);
      expect(_focused(), 'Film 3');

      // Trois pas vers la gauche coup sur coup : le troisième ne finit pas
      // sur le tri.
      await nav.press(TraversalDirection.left);
      await nav.press(TraversalDirection.left);
      await nav.press(TraversalDirection.left);
      expect(_focused(), 'Film 1');

      // Le focus posé, gauche y mène.
      await tester.pump(LibraryTvView.rest);
      await nav.press(TraversalDirection.left);
      expect(_focused(), 'Récents');
    });

    testWidgets('à la télécommande, le tri choisi rend le focus à sa capsule',
        (tester) async {
      final nav = await open(tester, _Api(20));
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.left);
      expect(_focused(), 'Récents');
      await nav.select();
      await tester.pumpAndSettle();
      await nav.press(TraversalDirection.down);
      await nav.select();
      await tester.pumpAndSettle();

      // La grille est retriée, et la télécommande n'a pas perdu sa place.
      expect(
        find.descendant(
            of: find.byType(OutlinedButton), matching: find.text('A → Z')),
        findsOneWidget,
      );
      expect(_focused(), 'A → Z');

      // L'affiche quittée n'existe plus : droite entre par la première.
      await nav.press(TraversalDirection.right);
      await tester.pumpAndSettle();
      expect(_focused(), 'Film 1');
    });

    testWidgets('pendant le chargement, la page a déjà sa forme',
        (tester) async {
      final api = _Api(20)..gate = Completer<void>();
      await TvNavHarness.pump(tester, _tab(api), engine: engine);
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pump();
      await tester.pump();

      expect(find.byType(LibraryTvView), findsOneWidget);
      expect(find.byType(LibrarySpotlight), findsNothing);
      expect(find.byType(MediaCard), findsNothing);
      // Rien à trier.
      expect(find.byType(OutlinedButton), findsNothing);
      // Le nom de la bibliothèque tient la place du titre de la fiche.
      expect(
        find.descendant(
            of: find.byType(LibraryTvView), matching: find.text('Films')),
        findsOneWidget,
      );
      final boxes = find.byType(SkeletonBox);
      // Deux rangées entières au moins.
      expect(boxes, findsAtLeastNWidgets(8));
      final loadingFirst = tester.getRect(boxes.first);

      api.gate!.complete();
      await tester.pumpAndSettle();

      // Les affiches arrivent là où étaient les cases.
      expect(_poster(tester, 'Film 1'), loadingFirst);
    });

    testWidgets('choisir un tri repart de la première affiche',
        (tester) async {
      final nav = await open(tester, _Api(20));
      await nav.press(TraversalDirection.down);
      await nav.press(TraversalDirection.right);
      expect(_inSpotlight(find.text('Film 2')), findsOneWidget);

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      // Le libellé d'une ligne de menu ne reçoit pas le toucher lui-même :
      // c'est sa ligne qui le prend.
      await tester.tap(find.text('A → Z').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      // « Film 1 », « Film 10 », « Film 11 »… : l'ordre des titres.
      expect(_poster(tester, 'Film 10').left,
          greaterThan(_poster(tester, 'Film 1').left));
      expect(_poster(tester, 'Film 10').top, _poster(tester, 'Film 1').top);
      expect(_inSpotlight(find.text('Film 1')), findsOneWidget);
    });
  });

  testWidgets('hors téléviseur, la bibliothèque garde sa grille et son en-tête',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api(20);
    await tester.pumpWidget(MaterialApp(
      home: TvScope(
        isTv: false,
        child: MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => AuthProvider(api)),
            ChangeNotifierProvider(create: (_) => HomeProvider(api)),
            ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
          ],
          child: const LibraryScreen(library: _library),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryTvView), findsNothing);
    expect(_catalogHeader, findsOneWidget);
  });
}
