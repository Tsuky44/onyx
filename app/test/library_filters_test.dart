import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/screens/library/library_filters.dart';
import 'package:onyx/screens/library/library_screen.dart';
import 'package:onyx/screens/library/widgets/library_filters_panel.dart';
import 'package:onyx/screens/library/widgets/library_spotlight.dart';
import 'package:onyx/screens/library/widgets/library_spotlight_prefetch.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/utils/poster_grid_zoom.dart';
import 'package:onyx/utils/search_match.dart';
import 'package:onyx/widgets/global/filter_panel/onyx_filter_panel.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le tri et les filtres d'une bibliothèque : le panneau des Demandes, à
/// droite à la place du volet du titre survolé sur grand écran, dans une
/// feuille du bas sur téléphone. Demande de l'utilisateur (2026-11-25).

HomeMediaItem _movie(
  int id, {
  required String release,
  int minutes = 100,
  int position = 0,
  bool finished = false,
}) =>
    HomeMediaItem(
      media: Media(
        id: id,
        type: MediaType.movie,
        title: 'Film $id',
        releaseDate: release,
        duration: minutes * 60,
        createdAt: DateTime(2026, 1, 30 - id),
      ),
      currentPositionSeconds: position,
      isFinished: finished,
      duration: minutes * 60,
    );

final _movies = [
  _movie(1, release: '2022-05-01', minutes: 130),
  _movie(2, release: '2015-03-01', minutes: 95, position: 600),
  _movie(3, release: '1994-10-14', minutes: 154, finished: true),
  _movie(4, release: '2019-12-31', minutes: 80),
];

class _Api extends ApiClient {
  @override
  Future<List<HomeMediaItem>> getLibraryMovies(MediaLibrary library) async =>
      _movies;

  @override
  Future<MediaDetails> getMediaDetails(int mediaId) async => MediaDetails(
        id: mediaId,
        type: MediaType.movie,
        title: 'Film $mediaId',
      );
}

const _library = MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies);

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api();
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
    ],
    child: const MaterialApp(home: LibraryScreen(library: _library)),
  ));
  await tester.pumpAndSettle();
}

List<String> _shown(WidgetTester tester) => [
      for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard)))
        card.media.title,
    ];

Future<void> _tapIn(WidgetTester tester, String text) async {
  final target = find.descendant(
      of: find.byType(LibraryFiltersPanel), matching: find.text(text));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MediaDetailsCache.clear();
    LibrarySpotlightPrefetch.resetForTest();
    PosterGridZoom.instance.resetForTest();
    TvMode.enabled.value = false;
  });

  group('LibraryFilters.apply', () {
    final entries = [
      for (final m in _movies) (media: m.media, movie: m),
    ];
    List<String> titles(LibraryFilters f) => [
          for (final e in f.apply(entries, titleKey: titleSortKey))
            e.media.title,
        ];

    test('le visionnage sépare non vus, en cours et vus', () {
      expect(titles(const LibraryFilters(watch: LibraryWatchFilter.unwatched)),
          ['Film 1', 'Film 4']);
      expect(titles(const LibraryFilters(watch: LibraryWatchFilter.inProgress)),
          ['Film 2']);
      expect(titles(const LibraryFilters(watch: LibraryWatchFilter.watched)),
          ['Film 3']);
    });

    test('une décennie garde ses deux bornes, une durée ses minutes', () {
      expect(titles(const LibraryFilters(from: '2010-01-01', to: '2019-12-31')),
          ['Film 2', 'Film 4']);
      expect(titles(const LibraryFilters(minDuration: '120')),
          ['Film 1', 'Film 3']);
    });

    test('le tri par date de sortie met la plus récente en tête', () {
      expect(titles(const LibraryFilters(sort: LibrarySort.release)),
          ['Film 1', 'Film 4', 'Film 2', 'Film 3']);
    });

    test('le tri ne compte pas parmi les filtres posés', () {
      expect(const LibraryFilters(sort: LibrarySort.title).activeCount, 0);
      expect(
          const LibraryFilters(
                  watch: LibraryWatchFilter.watched, minDuration: '90')
              .activeCount,
          2);
    });
  });

  testWidgets(
      'sur grand écran, le panneau s’ouvre à droite à la place du volet du '
      'titre survolé, et le volet revient à la fermeture', (tester) async {
    await _pumpAt(tester, const Size(1600, 1000));
    expect(find.byType(LibrarySpotlight), findsOneWidget);

    await tester.tap(find.text('Filtres'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryFiltersPanel), findsOneWidget);
    expect(find.byType(LibrarySpotlight), findsNothing);
    final panel = tester.getRect(find.byType(OnyxFilterPanel));
    expect(panel.right, greaterThan(1500));
    // Les affiches restent à gauche du panneau.
    for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard))) {
      expect(tester.getRect(find.byWidget(card)).right,
          lessThan(panel.left));
    }

    await tester.tap(find.byTooltip('Fermer les filtres'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryFiltersPanel), findsNothing);
    expect(find.byType(LibrarySpotlight), findsOneWidget);
  });

  testWidgets(
      'un filtre du panneau resserre la grille et le bouton prend le compte',
      (tester) async {
    await _pumpAt(tester, const Size(1600, 1000));
    await tester.tap(find.text('Filtres'));
    await tester.pumpAndSettle();

    await _tapIn(tester, 'Visionnage');
    await _tapIn(tester, 'Non vus');
    expect(_shown(tester), ['Film 1', 'Film 4']);
    expect(find.text('Filtres · 1'), findsOneWidget);

    await _tapIn(tester, 'Tout effacer');
    expect(_shown(tester), hasLength(4));
  });

  testWidgets(
      'aucun titre ne passe : la page le dit et propose d’effacer',
      (tester) async {
    await _pumpAt(tester, const Size(1600, 1000));
    await tester.tap(find.text('Filtres'));
    await tester.pumpAndSettle();
    await _tapIn(tester, 'Visionnage');
    await _tapIn(tester, 'Vus');
    await _tapIn(tester, 'Durée');
    await _tapIn(tester, 'Moins de 1 h 30');

    expect(find.text('Aucun titre ne correspond'), findsOneWidget);
    await tester.tap(find.text('Effacer les filtres'));
    await tester.pumpAndSettle();
    expect(_shown(tester), hasLength(4));
  });

  testWidgets(
      'sur téléphone, le bouton ouvre une feuille du bas, repliée, et la '
      'grille suit derrière', (tester) async {
    await _pumpAt(tester, const Size(390, 844));

    await tester.tap(find.byTooltip('Trier et filtrer'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Tous les titres'), findsOneWidget);
    expect(find.text('Non vus'), findsNothing);

    await _tapIn(tester, 'Visionnage');
    await _tapIn(tester, 'En cours');
    await tester.tap(find.byTooltip('Fermer les filtres'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(_shown(tester), ['Film 2']);
  });
}
