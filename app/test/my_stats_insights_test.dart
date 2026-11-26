import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/l10n/tmdb_genres.dart';
import 'package:onyx/models/server_activity.dart';
import 'package:onyx/screens/settings/widgets/my_stats/my_stats_insights.dart';
import 'package:onyx/screens/settings/widgets/stats_charts.dart';

List<List<int>> _emptyGrid() => [
      for (var d = 0; d < 7; d++) List.filled(24, 0),
    ];

void main() {
  group('créneau préféré', () {
    test('aucune lecture, aucun créneau', () {
      expect(favoriteSlot(_emptyGrid()), isNull);
    });

    test('additionne les heures d’un même moment de la journée', () {
      final grid = _emptyGrid();
      grid[6][20] = 3000; // dimanche soir : deux séances
      grid[6][22] = 3000;
      grid[2][14] = 5000; // mercredi après-midi : une seule, plus longue
      expect(favoriteSlot(grid), (weekday: 6, part: DayPart.evening));
    });

    test('minuit à 5 h est la nuit, pas le soir', () {
      expect(dayPartOf(0), DayPart.night);
      expect(dayPartOf(4), DayPart.night);
      expect(dayPartOf(5), DayPart.morning);
      expect(dayPartOf(12), DayPart.afternoon);
      expect(dayPartOf(18), DayPart.evening);
      expect(dayPartOf(23), DayPart.evening);
    });
  });

  test('la part de la nuit compte de minuit à 5 h', () {
    final hours = List.filled(24, 0);
    expect(lateNightShare(hours), 0);
    hours[1] = 1000;
    hours[21] = 3000;
    expect(lateNightShare(hours), 0.25);
  });

  test('le jour record est celui où l’on a le plus regardé', () {
    final days = [
      DailyStat(DateTime(2026, 9, 1), 1, 600),
      DailyStat(DateTime(2026, 9, 2), 3, 9000),
      DailyStat(DateTime(2026, 9, 3), 2, 4000),
    ];
    expect(recordDay(days)?.date, DateTime(2026, 9, 2));
    expect(recordDay([DailyStat(DateTime(2026, 9, 1), 0, 0)]), isNull);
  });

  group('graphique par jour', () {
    List<DailyStat> days(int n) => [
          for (var i = 0; i < n; i++)
            DailyStat(DateTime(2026, 1, 1 + i), 1, 60),
        ];

    test('trois mois restent un jour par barre', () {
      final grouped = groupDailyForChart(days(90));
      expect(grouped.step, ChartStep.day);
      expect(grouped.bars, hasLength(90));
    });

    // Un an de barres d'un pixel, et autant de cibles de focus, ne se lisait
    // plus : une barre par semaine.
    test('un an se regroupe par semaine, sans perdre une minute', () {
      final grouped = groupDailyForChart(days(365));
      expect(grouped.step, ChartStep.week);
      expect(grouped.bars, hasLength(53));
      expect(grouped.bars.first.watchedSeconds, 7 * 60);
      expect(
          grouped.bars.fold<int>(0, (s, d) => s + d.watchedSeconds), 365 * 60);
    });

    test('au-delà, une barre par mois', () {
      final grouped = groupDailyForChart(days(800));
      expect(grouped.step, ChartStep.month);
      expect(grouped.bars.first.date, DateTime(2026, 1, 1));
      expect(grouped.bars.first.plays, 31);
      expect(grouped.bars[1].date, DateTime(2026, 2, 1));
    });
  });

  test('un genre TMDB inconnu n’a pas de nom, donc pas de ligne', () {
    expect(tmdbGenreLabel(878), 'Science-fiction');
    expect(tmdbGenreLabel(999999), isNull);
  });
}
