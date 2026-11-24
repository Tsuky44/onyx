// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/watch_list.dart';
import 'package:onyx/screens/lists/widgets/list_item_card.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/progress_pill.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une série commencée dit où l'on en est sur son affiche : l'épisode suivant
/// en pastille, les épisodes vus en barre (ADR-0162). Le serveur calcule, l'app
/// n'affiche que ce qu'il envoie.

WatchListItem _show({
  int watchedEpisodes = 0,
  int totalEpisodes = 0,
  int season = 0,
  int episode = 0,
  bool watched = false,
  String type = 'show',
  bool onServer = true,
}) =>
    WatchListItem.fromJson({
      'id': 1,
      'media_type': type,
      'tmdb_id': 101,
      'title': 'Dark',
      'poster_url': '',
      'release_date': '2017-12-01',
      'media_id': onServer ? 20 : 0,
      'watched': watched,
      'episodes_watched': watchedEpisodes,
      'episodes_total': totalEpisodes,
      'next_episode_season': season,
      'next_episode_number': episode,
      if (onServer)
        'media': {
          'id': 20,
          'type': type,
          'title': 'Dark',
          'file_path': '',
          'versions': <Object>[],
        },
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WatchListItem.isShowInProgress', () {
    test('une série à moitié vue est en cours', () {
      final item = _show(
          watchedEpisodes: 3, totalEpisodes: 8, season: 1, episode: 4);
      expect(item.isShowInProgress, isTrue);
      expect(item.episodesFraction, closeTo(3 / 8, 1e-9));
      expect(item.nextEpisodeCode, 'S1 E4');
    });

    test('une série jamais lancée ou finie n\'est pas en cours', () {
      expect(_show(totalEpisodes: 8, season: 1, episode: 1).isShowInProgress,
          isFalse);
      expect(
          _show(watchedEpisodes: 8, totalEpisodes: 8, watched: true)
              .isShowInProgress,
          isFalse);
    });

    test('un film, ou un serveur d\'avant l\'ADR-0162, n\'a rien à dire', () {
      expect(_show(type: 'movie').isShowInProgress, isFalse);
      final old = _show();
      expect(old.isShowInProgress, isFalse);
      expect(old.nextEpisodeCode, isNull);
    });
  });

  group('ListItemCard', () {
    Future<void> pump(WidgetTester tester, WatchListItem item) async {
      await tester.pumpWidget(MultiProvider(
        providers: [Provider<ApiClient>.value(value: ApiClient())],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 270,
              child: ListItemCard(
                item: item,
                onTap: (_) {},
                onMenu: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('une série commencée montre l\'épisode suivant et sa barre',
        (tester) async {
      await pump(tester,
          _show(watchedEpisodes: 3, totalEpisodes: 8, season: 1, episode: 4));
      expect(find.text('S1 E4'), findsOneWidget);
      expect(find.byType(ProgressPill), findsOneWidget);
    });

    testWidgets('une série jamais lancée n\'ajoute rien à son affiche',
        (tester) async {
      await pump(tester, _show(totalEpisodes: 8, season: 1, episode: 1));
      expect(find.text('S1 E1'), findsNothing);
      expect(find.byType(ProgressPill), findsNothing);
    });
  });
}
