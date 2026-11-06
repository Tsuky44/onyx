import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/screens/library/library_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// L'onglet d'une bibliothèque à la télécommande, pendant et après le
/// chargement de sa grille.
///
/// Vu au simulateur Apple TV (phase 2 de la refonte dpad) : le premier Bas
/// après l'ouverture de l'onglet Films semblait perdu. Pendant le chargement,
/// le menu de tri était la seule cible sous l'en-tête ; Bas sautait au bout
/// de la ligne, sur ce petit menu à peine marqué, et le Bas suivant tombait
/// sur l'affiche la plus à droite de la grille arrivée entre-temps. Dans les
/// deux systèmes de navigation.

class _Api extends ApiClient {
  final Completer<List<HomeMediaItem>> movies =
      Completer<List<HomeMediaItem>>();

  @override
  Future<List<HomeMediaItem>> getLibraryMovies(MediaLibrary library) =>
      movies.future;
}

HomeMediaItem _movie(int id) => HomeMediaItem(
      media: Media(
        id: id,
        type: MediaType.movie,
        title: 'Film $id',
        duration: 6000,
        // Le plus récent d'abord : le film 1 est le premier de la grille.
        createdAt: DateTime(2026, 1, 30 - id),
      ),
      currentPositionSeconds: 0,
      isFinished: false,
      duration: 6000,
    );

const _library = MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies);

/// L'onglet de l'en-tête au-dessus de la page, comme `MainShell` les pose.
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
                  child: const TvTestTile('Films', height: 48),
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

String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  final card = node?.context?.findAncestorWidgetOfExactType<MediaCard>();
  return card?.media.title ?? focusedLabelOf(node);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TvNavHarness.forEachEngine((engine) {
    testWidgets(
        'pendant le chargement, Bas ne quitte pas l’onglet pour le menu de tri',
        (tester) async {
      final api = _Api();
      final nav = await TvNavHarness.pump(tester, _tab(api), engine: engine);
      expect(_focused(), 'Films');

      await nav.press(TraversalDirection.down);
      // Rien à atteindre encore : le focus reste visible, sur l'onglet.
      expect(_focused(), 'Films');

      api.movies.complete([for (var i = 1; i <= 12; i++) _movie(i)]);
      await tester.pumpAndSettle();

      // La grille arrivée, Bas y entre par le haut, sous l'onglet.
      await nav.press(TraversalDirection.down);
      expect(_focused(), 'Film 1');
    });
  });
}
