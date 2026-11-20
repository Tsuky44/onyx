import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/screens/library/library_screen.dart';
import 'package:onyx/screens/library/widgets/library_spotlight.dart';
import 'package:onyx/screens/library/widgets/library_spotlight_prefetch.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/utils/poster_grid_zoom.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une bibliothèque sur un grand écran du bureau (ADR-0140) : la fiche du
/// titre survolé à gauche, comme dans la recherche du bureau. Demande de
/// l'utilisateur : retrouver dans les onglets Films et Séries le volet de
/// résumé qu'il aimait dans la recherche.

class _Api extends ApiClient {
  @override
  Future<List<HomeMediaItem>> getLibraryMovies(MediaLibrary library) async =>
      [for (var i = 1; i <= 8; i++) _movie(i)];

  @override
  Future<MediaDetails> getMediaDetails(int mediaId) async => MediaDetails(
        id: mediaId,
        type: MediaType.movie,
        title: 'Film $mediaId',
        overview: 'Le résumé du film $mediaId.',
      );
}

HomeMediaItem _movie(int id) => HomeMediaItem(
      media: Media(
        id: id,
        type: MediaType.movie,
        title: 'Film $id',
        overview: 'Le résumé du film $id.',
        duration: 6000,
        createdAt: DateTime(2026, 1, 30 - id),
      ),
      currentPositionSeconds: 0,
      isFinished: false,
      duration: 6000,
    );

const _library = MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies);

Widget _screen() {
  final api = _Api();
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
    ],
    child: const MaterialApp(home: LibraryScreen(library: _library)),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_screen());
  await tester.pumpAndSettle();
}

String _presented(WidgetTester tester) =>
    tester.widget<LibrarySpotlight>(find.byType(LibrarySpotlight)).media.title;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MediaDetailsCache.clear();
    LibrarySpotlightPrefetch.resetForTest();
    PosterGridZoom.instance.resetForTest();
  });

  int columns(WidgetTester tester) =>
      (tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount;

  // Le volet de l'Apple TV, sur 1920 px (ADR-0156) : un bon tiers de
  // l'écran, et quatre affiches par ligne à côté. À taille réelle, il n'en
  // prenait qu'un quart, à côté de six colonnes.
  testWidgets('à 1920 px, le volet a les proportions de l’Apple TV',
      (tester) async {
    await _pumpAt(tester, const Size(1920, 1080));

    final pane = tester.getRect(find.byType(LibrarySpotlight));
    expect(pane.width, closeTo((48 + 374 + 48 + 170) * 1.5, 1));
    expect(columns(tester), 4);
    expect(tester.getTopLeft(find.byType(MediaCard).first).dx,
        greaterThan(1920 / 3));
  });

  testWidgets('le choix « 6 par ligne » de la grille pleine reste le sien',
      (tester) async {
    SharedPreferences.setMockInitialValues({'poster_grid_columns': 6});
    await _pumpAt(tester, const Size(1920, 1080));
    expect(columns(tester), 4,
        reason: 'à côté du volet, la grille a ses propres modes');

    await _pumpAt(tester, const Size(1000, 1000));
    expect(columns(tester), 6);
  });

  testWidgets('sur un grand écran, le volet présente le titre survolé',
      (tester) async {
    await _pumpAt(tester, const Size(1600, 1000));

    expect(find.byType(LibrarySpotlight), findsOneWidget);
    // Avant tout survol, la première affiche.
    expect(_presented(tester), 'Film 1');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final third = find
        .byWidgetPredicate((w) => w is MediaCard && w.media.title == 'Film 3');
    await mouse.moveTo(tester.getCenter(third));
    await tester.pumpAndSettle();

    expect(_presented(tester), 'Film 3');
    expect(find.text('Le résumé du film 3.'), findsOneWidget);
  });

  testWidgets(
      'les fiches des affiches à l\'écran sont prêtes avant le survol '
      '(ADR-0142)', (tester) async {
    await _pumpAt(tester, const Size(1600, 1000));

    // Aucun survol : le logo de chaque affiche se posera sans attendre.
    for (var id = 1; id <= 8; id++) {
      expect(MediaDetailsCache.isFresh(id), isTrue, reason: 'Film $id');
    }
  });

  testWidgets('sur une fenêtre étroite, la grille garde toute la largeur',
      (tester) async {
    await _pumpAt(tester, const Size(900, 1000));

    expect(find.byType(LibrarySpotlight), findsNothing);
    expect(find.byType(MediaCard), findsWidgets);
  });
}
