import '../../../../l10n/tr.dart';
import '../../../../models/server_activity.dart';

/// Ce que « Mes stats » déduit des séries que le serveur envoie déjà : le jour
/// record, le créneau préféré, la part de la nuit. Des fonctions pures, testées
/// sans monter la page (`test/my_stats_insights_test.dart`).

/// Le moment d'une journée, pour nommer un créneau.
enum DayPart { morning, afternoon, evening, night }

DayPart dayPartOf(int hour) => switch (hour) {
      >= 5 && < 12 => DayPart.morning,
      >= 12 && < 18 => DayPart.afternoon,
      >= 18 => DayPart.evening,
      _ => DayPart.night,
    };

/// Le jour de la semaine (0 = lundi) et le moment de la journée où l'on a le
/// plus regardé. Nul sans aucune lecture.
({int weekday, DayPart part})? favoriteSlot(List<List<int>> weekdayHour) {
  ({int weekday, DayPart part})? best;
  var bestSeconds = 0;
  for (var day = 0; day < weekdayHour.length; day++) {
    final byPart = <DayPart, int>{};
    for (var hour = 0; hour < weekdayHour[day].length; hour++) {
      final part = dayPartOf(hour);
      byPart[part] = (byPart[part] ?? 0) + weekdayHour[day][hour];
    }
    for (final MapEntry(key: part, value: seconds) in byPart.entries) {
      if (seconds > bestSeconds) {
        bestSeconds = seconds;
        best = (weekday: day, part: part);
      }
    }
  }
  return best;
}

/// La part du temps vu entre minuit et 5 h, de 0 à 1.
double lateNightShare(List<int> hourOfDay) {
  final total = hourOfDay.fold<int>(0, (s, v) => s + v);
  if (total == 0) return 0;
  var night = 0;
  for (var h = 0; h < 5 && h < hourOfDay.length; h++) {
    night += hourOfDay[h];
  }
  return night / total;
}

/// Le jour où l'on a le plus regardé, nul sur une période vide.
DailyStat? recordDay(List<DailyStat> daily) {
  DailyStat? best;
  for (final day in daily) {
    if (day.watchedSeconds > (best?.watchedSeconds ?? 0)) best = day;
  }
  return best;
}

/// « Lundi »… à partir de 0 = lundi.
String weekdayName(int weekday) => switch (weekday) {
      0 => tr('Lundi'),
      1 => tr('Mardi'),
      2 => tr('Mercredi'),
      3 => tr('Jeudi'),
      4 => tr('Vendredi'),
      5 => tr('Samedi'),
      _ => tr('Dimanche'),
    };

/// Un jour abrégé, pour la grille : une initiale confondrait mardi et
/// mercredi.
String weekdayShort(int weekday) => switch (weekday) {
      0 => tr('lun.'),
      1 => tr('mar.'),
      2 => tr('mer.'),
      3 => tr('jeu.'),
      4 => tr('ven.'),
      5 => tr('sam.'),
      _ => tr('dim.'),
    };

String dayPartName(DayPart part) => switch (part) {
      DayPart.morning => tr('le matin'),
      DayPart.afternoon => tr('l’après-midi'),
      DayPart.evening => tr('le soir'),
      DayPart.night => tr('la nuit'),
    };
