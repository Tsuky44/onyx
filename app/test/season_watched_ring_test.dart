import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/library/widgets/season_tabs.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/season_progress_ring.dart';
import 'package:provider/provider.dart';

/// Le tour du rond d'une bulle de saison se remplit en blanc de ce que
/// l'utilisateur a vu : rien de vu laisse le filet seul, tout vu le ferme.
Media _season(int number, {int? available, int? watched}) => Media(
      id: number,
      type: MediaType.season,
      title: 'Saison $number',
      seasonNumber: number,
      duration: 0,
      availableEpisodeCount: available,
      watchedEpisodeCount: watched,
      createdAt: DateTime(2026),
    );

void main() {
  test('la part vue est le rapport des épisodes terminés aux disponibles', () {
    expect(_season(1).watchedFraction, 0);
    expect(_season(1, available: 8, watched: 0).watchedFraction, 0);
    expect(_season(1, available: 8, watched: 2).watchedFraction, 0.25);
    expect(_season(1, available: 8, watched: 8).watchedFraction, 1);
    // Un épisode vu dont le fichier a disparu ne dépasse pas le tour.
    expect(_season(1, available: 8, watched: 9).watchedFraction, 1);
  });

  testWidgets('chaque bulle remplit son tour de la part vue de sa saison',
      (tester) async {
    final seasons = [
      _season(1, available: 8, watched: 8),
      _season(2, available: 8, watched: 2),
      _season(3, available: 8, watched: 0),
    ];
    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: ApiClient(),
        child: MaterialApp(
          home: Scaffold(
            body: SeasonTabs(
              seasons: seasons,
              selected: null,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final rings = tester
        .widgetList<SeasonProgressRing>(find.byType(SeasonProgressRing))
        .map((ring) => ring.progress)
        .toList();
    expect(rings, [1, 0.25, 0]);
  });
}
