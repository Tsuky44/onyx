import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/widgets/tabs/player_episodes_tab.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/services/download_preferences.dart';
import 'package:onyx/services/network_status.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/widgets/global/media_download_button.dart';
import 'package:onyx/widgets/global/season_download_button.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

/// L'onglet « Épisodes » du lecteur (ADR-0130) : une rangée de cartes posée
/// sur l'épisode en cours, les saisons en boutons, et, hors téléviseur, de
/// quoi télécharger sans repasser par la fiche de la série.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomeMediaItem episode(int id, {bool watched = false}) => HomeMediaItem(
        media: Media(
          id: id,
          type: MediaType.episode,
          title: 'Épisode $id',
          duration: 2400,
          seasonNumber: 1,
          episodeNumber: id,
          isAvailable: true,
          createdAt: DateTime(2026),
        ),
        currentPositionSeconds: 0,
        duration: 2400,
        isFinished: watched,
        showId: 7,
        showTitle: 'Ma série',
      );

  Media season(int id, int number) => Media(
        id: id,
        type: MediaType.season,
        title: 'Saison $number',
        duration: 0,
        seasonNumber: number,
        isAvailable: true,
        createdAt: DateTime(2026),
      );

  Widget providers(Widget child) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: ApiClient()),
          ChangeNotifierProvider<DownloadManager>.value(
              value: DownloadManager.instance),
          ChangeNotifierProvider<DownloadPreferences>.value(
              value: DownloadPreferences.instance),
          ChangeNotifierProvider<NetworkStatus>(create: (_) => NetworkStatus()),
        ],
        child: child,
      );

  Widget tab({
    required List<HomeMediaItem> episodes,
    int current = 2,
    List<Media> seasons = const [],
    int selectedSeason = 0,
    ValueChanged<int>? onSeasonChanged,
    ValueChanged<HomeMediaItem>? onEpisodeSelected,
    bool loading = false,
  }) =>
      Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            height: 238,
            child: PlayerEpisodesTab(
              showTitle: 'Ma série',
              currentEpisodeId: current,
              seasons: seasons,
              selectedSeasonId: selectedSeason,
              onSeasonChanged: onSeasonChanged ?? (_) {},
              episodes: episodes,
              isLoading: loading,
              onEpisodeSelected: onEpisodeSelected ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets('chaque épisode et la suite de la saison se téléchargent d’ici',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final episodes = [for (var i = 1; i <= 4; i++) episode(i, watched: i == 1)];
    await tester.pumpWidget(providers(
      MaterialApp(home: tab(episodes: episodes)),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SeasonDownloadButton), findsOneWidget);
    expect(find.text('Télécharger les non vus · 3 épisodes'), findsOneWidget);
    // Une seule rangée, la saison entière : un bouton par épisode.
    expect(find.byType(MediaDownloadButton), findsNWidgets(4));
  });

  testWidgets('l’épisode en cours est marqué, celui déjà vu aussi',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final episodes = [for (var i = 1; i <= 4; i++) episode(i, watched: i == 1)];
    await tester.pumpWidget(providers(
      MaterialApp(home: tab(episodes: episodes)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 · Épisode 1'), findsOneWidget);
    expect(find.text('40min · Vu'), findsOneWidget);
    // Sur l'image et dans la ligne de l'épisode qu'on regarde.
    expect(find.text('En cours'), findsOneWidget);
    expect(find.text('40min · En cours'), findsOneWidget);
  });

  testWidgets('la rangée s’ouvre sur l’épisode en cours, pas sur le premier',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final episodes = [for (var i = 1; i <= 24; i++) episode(i)];
    await tester.pumpWidget(providers(
      MaterialApp(home: tab(episodes: episodes, current: 12)),
    ));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.text('12 · Épisode 12'));
    expect(card.left, closeTo(24, 1),
        reason: 'la carte en cours est la première visible');
    expect(find.text('1 · Épisode 1'), findsNothing);
  });

  testWidgets('pendant le chargement, un rond ; sans épisode, on le dit',
      (tester) async {
    await tester.pumpWidget(providers(
      MaterialApp(home: tab(episodes: const [], loading: true)),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(providers(
      MaterialApp(home: tab(episodes: const [])),
    ));
    await tester.pump();
    expect(find.text('Aucun épisode disponible'), findsOneWidget);
  });

  group('sur un téléviseur', () {
    TvNavHarness.forEachEngine((engine) {
      testWidgets(
          'la télécommande entre sur l’épisode en cours, OK lance celui '
          'qu’elle tient, et rien ne se télécharge', (tester) async {
        final chosen = <int>[];
        final entry = FocusNode(debugLabel: 'au-dessus');
        addTearDown(entry.dispose);
        final episodes = [for (var i = 1; i <= 6; i++) episode(i)];

        final nav = await TvNavHarness.pump(
          tester,
          providers(Scaffold(
            backgroundColor: Colors.black,
            body: TvRegion.controlRows(
              child: Column(
                children: [
                  TvRegion.controls(
                    child: Focus(
                      focusNode: entry,
                      child: const SizedBox(width: 200, height: 60),
                    ),
                  ),
                  SizedBox(
                    height: 238,
                    child: PlayerEpisodesTab(
                      showTitle: 'Ma série',
                      currentEpisodeId: 3,
                      seasons: [season(10, 1), season(11, 2)],
                      selectedSeasonId: 10,
                      onSeasonChanged: (_) {},
                      episodes: episodes,
                      isLoading: false,
                      onEpisodeSelected: (item) => chosen.add(item.media.id),
                    ),
                  ),
                ],
              ),
            ),
          )),
          engine: engine,
        );
        await tester.pumpAndSettle();
        expect(find.byType(MediaDownloadButton), findsNothing);
        expect(find.byType(SeasonDownloadButton), findsNothing);

        entry.requestFocus();
        await TvNavHarness.settle(tester);

        // D'abord les saisons, sur celle qui est affichée.
        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(focusedLabelOf(primaryFocus!), 'Saison 1');

        // Puis les épisodes, sur celui qu'on regarde : sa carte est la seule
        // à porter la marque « En cours », son premier texte.
        await nav.press(TraversalDirection.down);
        await tester.pumpAndSettle();
        expect(focusedLabelOf(primaryFocus!), 'En cours');

        await nav.press(TraversalDirection.right);
        await tester.pumpAndSettle();
        await nav.select();
        expect(chosen, [4]);
      });

      testWidgets('OK sur une autre saison la demande', (tester) async {
        final asked = <int>[];
        final nav = await TvNavHarness.pump(
          tester,
          providers(tab(
            episodes: [for (var i = 1; i <= 3; i++) episode(i)],
            seasons: [season(10, 1), season(11, 2)],
            selectedSeason: 10,
            onSeasonChanged: asked.add,
          )),
          engine: engine,
        );
        await tester.pumpAndSettle();

        // De la saison affichée, un pas à droite.
        nodeLabelled('player-season-now').requestFocus();
        await TvNavHarness.settle(tester);
        await nav.select();
        expect(asked, isEmpty,
            reason: 'la saison affichée ne se redemande pas');

        await nav.press(TraversalDirection.right);
        await tester.pumpAndSettle();
        await nav.select();

        expect(asked, [11]);
      });
    });
  });
}
