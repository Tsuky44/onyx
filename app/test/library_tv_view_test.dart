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

/// Une bibliothèque sur téléviseur (ADR-0123) : la fiche du titre que la
/// télécommande désigne en tête, une rangée de six affiches dessous.
///
/// Retour de l'utilisateur sur Apple TV : la grille de sept affiches par
/// ligne, trois rangées pleines à l'écran, était « trop remplie, trop
/// compacte ». Ce banc monte le vrai [LibraryScreen] sous un onglet, à la
/// taille d'une page de téléviseur.

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

    testWidgets('six affiches par ligne, une rangée et le haut de la suivante',
        (tester) async {
      await open(tester, _Api(20));

      final first = _poster(tester, 'Film 1');
      final sixth = _poster(tester, 'Film 6');
      final seventh = _poster(tester, 'Film 7');
      // (1280 − 2 × 48 − 5 × 24) / 6 : la largeur d'une affiche de l'accueil.
      expect(first.width, closeTo(177.3, 0.1));
      expect(first.height, closeTo(266, 0.1));
      expect(first.left, 48);
      expect(sixth.top, first.top);
      expect(sixth.right, closeTo(1280 - 48, 0.1));
      expect(seventh.left, first.left);
      expect(seventh.top - first.bottom, LibraryTvView.rowGap);
      // La rangée suivante pointe en bas de l'écran, sans y tenir.
      expect(seventh.top, lessThan(720));
      expect(seventh.bottom, greaterThan(720));
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
        'la fiche présente la première affiche, puis celle que la '
        'télécommande désigne', (tester) async {
      final api = _Api(20);
      final nav = await open(tester, api);

      expect(_inSpotlight(find.text('FILMS · 20 TITRES')), findsOneWidget);
      expect(_inSpotlight(find.text('Film 1')), findsOneWidget);

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
      for (var i = 0; i < 4; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(_focused(), 'Film 5');
      expect(api.detailsAsked, isEmpty);

      await tester.pump(LibrarySpotlight.settle);
      await tester.pump();
      expect(api.detailsAsked, [5]);
    });

    testWidgets('descendre pose la rangée suivante à la place de la première',
        (tester) async {
      final nav = await open(tester, _Api(40));
      final firstRow = _poster(tester, 'Film 1').top;

      await nav.press(TraversalDirection.down);
      expect(_focused(), 'Film 1');

      for (final title in ['Film 7', 'Film 13', 'Film 19']) {
        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(_focused(), title);
        final poster = _poster(tester, title);
        if (engine == TvNavEngine.legacy) {
          // L'affiche focalisée se pose toujours à la même hauteur, et la
          // rangée du dessus est sortie de la grille.
          expect(poster.top, closeTo(firstRow, 0.5), reason: title);
        } else {
          // dpad ne sait que ramener « au plus près » : l'affiche est entière
          // à l'écran, c'est ce qu'on lui demande.
          expect(poster.top, greaterThanOrEqualTo(firstRow - 0.5));
          expect(poster.bottom, lessThanOrEqualTo(720));
        }
      }
    });

    testWidgets('la dernière rangée monte elle aussi à la place de la première',
        (tester) async {
      // Treize films : la troisième rangée n'en a qu'un.
      final nav = await open(tester, _Api(13));
      final firstRow = _poster(tester, 'Film 1').top;

      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
      }
      expect(_focused(), 'Film 13');
      if (engine == TvNavEngine.legacy) {
        expect(_poster(tester, 'Film 13').top, closeTo(firstRow, 0.5));
      }
      expect(_poster(tester, 'Film 13').bottom, lessThanOrEqualTo(720));
    });

    testWidgets('le tri est une capsule au-dessus de la grille, à droite',
        (tester) async {
      await open(tester, _Api(20));

      final sort = tester.getRect(find.byType(OutlinedButton));
      final firstRow = _poster(tester, 'Film 1');
      expect(sort.right, closeTo(1280 - 48, 0.1));
      // Au-dessus de l'affiche soulevée (10 % de 266 px).
      expect(sort.bottom, lessThan(firstRow.top - 26));
      expect(
        find.descendant(
            of: find.byType(OutlinedButton), matching: find.text('Récents')),
        findsOneWidget,
      );
    });

    testWidgets('à la télécommande, le tri choisi rend le focus à sa capsule',
        (tester) async {
      final nav = await open(tester, _Api(20));
      await nav.press(TraversalDirection.down);
      for (var i = 0; i < 5; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(_focused(), 'Film 6');

      // La capsule est au-dessus de la dernière colonne.
      await nav.press(TraversalDirection.up);
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
      // Rien à trier, et le tri serait la seule cible sous l'en-tête.
      expect(find.byType(OutlinedButton), findsNothing);
      final boxes = find.byType(SkeletonBox);
      expect(boxes, findsNWidgets(12));
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
