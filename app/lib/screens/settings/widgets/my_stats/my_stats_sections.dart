import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../l10n/locale_formats.dart';
import '../../../../l10n/tr.dart';
import '../../../../models/server_activity.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_type.dart';
import '../settings_ui.dart';
import 'my_stats_insights.dart';
import 'my_stats_titles.dart';

/// Les blocs « temps » de « Mes stats » : chiffres clés, habitudes, et ce qui
/// s'est accumulé depuis l'arrivée sur le serveur.

/// Les chiffres clés. [personal] manque sur un serveur plus ancien : les
/// tuiles qui en dépendent disparaissent.
class MyOverviewGrid extends StatelessWidget {
  const MyOverviewGrid(this.stats, {super.key});
  final PlaybackStats stats;

  String? _comparison(PersonalStats? p) {
    final previous = p?.previous;
    if (previous == null) return null;
    final delta = stats.watchedSeconds - previous.watchedSeconds;
    if (delta.abs() < 60) return tr('Autant que la période d’avant');
    return delta > 0
        ? tr('{0} de plus que la période d’avant', [formatWatchTime(delta)])
        : tr('{0} de moins que la période d’avant', [formatWatchTime(-delta)]);
  }

  @override
  Widget build(BuildContext context) {
    final p = stats.personal;
    final perDay = stats.days == 0 ? 0 : stats.watchedSeconds ~/ stats.days;
    final average = stats.plays == 0 ? 0 : stats.watchedSeconds ~/ stats.plays;
    return StatGrid(children: [
      StatTile(
        icon: Icons.schedule_rounded,
        label: tr('Temps regardé'),
        value: formatWatchTime(stats.watchedSeconds),
        hint: _comparison(p) ?? tr('≈ {0} par jour', [formatWatchTime(perDay)]),
      ),
      StatTile(
        icon: Icons.play_arrow_rounded,
        label: tr('Lectures'),
        value: '${stats.plays}',
        hint: stats.plays == 0
            ? null
            : tr('Séance moyenne : {0}', [formatWatchTime(average)]),
      ),
      if (p != null)
        StatTile(
          icon: Icons.local_fire_department_rounded,
          label: tr('Jours d’affilée'),
          value: '${p.streakCurrent}',
          hint:
              trPlural(p.streakBest, 'Record : {0} jour', 'Record : {0} jours'),
          color: AppColors.warning,
        ),
      StatTile(
        icon: Icons.movie_outlined,
        label: tr('Films vus'),
        value: '${stats.movies}',
        hint: p == null || p.averageMovieSeconds == 0
            ? null
            : tr('{0} en moyenne', [formatWatchTime(p.averageMovieSeconds)]),
        color: AppColors.warning,
      ),
      StatTile(
        icon: Icons.tv_rounded,
        label: tr('Épisodes vus'),
        value: '${stats.episodes}',
        hint: p == null
            ? null
            : trPlural(p.showsCount, 'de {0} série', 'de {0} séries'),
        color: AppColors.success,
      ),
      if (p != null)
        StatTile(
          icon: Icons.check_circle_outline_rounded,
          label: tr('Séries terminées'),
          value: '${p.showsFinished}',
          color: AppColors.success,
        ),
    ]);
  }
}

/// Quand on regarde : la grille jour × heure et ce qu'elle raconte.
class MyHabitsGroup extends StatelessWidget {
  const MyHabitsGroup(this.stats, {super.key});
  final PlaybackStats stats;

  @override
  Widget build(BuildContext context) {
    final p = stats.personal!;
    final slot = favoriteSlot(p.weekdayHour);
    final night = lateNightShare(stats.hourOfDay);
    return SettingsGroup(
      title: tr('Mes habitudes'),
      footer: tr('Selon l’heure de début de chaque lecture.'),
      children: [
        StatsRowFocus(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: WeekdayHourGrid(p.weekdayHour),
          ),
        ),
        if (slot != null)
          StatsFact(
            icon: Icons.event_available_rounded,
            title: tr('Créneau préféré'),
            subtitle: tr('{0}, {1}',
                [weekdayName(slot.weekday), dayPartName(slot.part)]),
          ),
        if (p.longestPlay case final longest?)
          StatsFact(
            icon: Icons.hourglass_bottom_rounded,
            title: tr('Plus longue séance'),
            subtitle: tr('{0} · {1}',
                [formatWatchTime(longest.watchedSeconds), longest.title]),
          ),
        if (recordDay(stats.daily) case final day?)
          StatsFact(
            icon: Icons.emoji_events_outlined,
            title: tr('Jour record'),
            subtitle: tr('{0} · {1}',
                [formatWatchTime(day.watchedSeconds), formatDay(day.date)]),
          ),
        if (night >= 0.01)
          StatsFact(
            icon: Icons.bedtime_outlined,
            title: tr('Après minuit'),
            subtitle: tr('{0} % de votre temps, entre minuit et 5 h',
                [(night * 100).round()]),
          ),
      ],
    );
  }
}

/// Sept lignes (lundi d'abord), vingt-quatre heures : plus la case est
/// claire, plus on a regardé à ce moment-là.
class WeekdayHourGrid extends StatelessWidget {
  const WeekdayHourGrid(this.grid, {super.key});
  final List<List<int>> grid;

  @override
  Widget build(BuildContext context) {
    final maxValue =
        grid.expand((row) => row).fold<int>(0, (m, v) => math.max(m, v));
    const label =
        TextStyle(color: AppColors.textMuted, fontSize: AppType.caption);
    return Semantics(
      label: tr('Grille des heures de visionnage par jour de la semaine'),
      child: Column(
        children: [
          for (var day = 0; day < 7; day++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                SizedBox(
                    width: 40, child: Text(weekdayShort(day), style: label)),
                for (var hour = 0; hour < 24; hour++) ...[
                  if (hour > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Tooltip(
                      message: tr('{0}, {1} h : {2}', [
                        weekdayName(day),
                        hour,
                        formatWatchTime(grid[day][hour]),
                      ]),
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: grid[day][hour] == 0
                              ? Colors.white.withValues(alpha: 0.05)
                              : Color.lerp(
                                  AppColors.primary.withValues(alpha: 0.25),
                                  AppColors.accentMuted,
                                  maxValue == 0
                                      ? 0
                                      : grid[day][hour] / maxValue,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 40),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final h in const ['0 h', '6 h', '12 h', '18 h', '23 h'])
                    Text(h, style: label),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Tout ce qui s'est accumulé depuis la première lecture.
class MyLifetimeGroup extends StatelessWidget {
  const MyLifetimeGroup(this.personal, {super.key});
  final PersonalStats personal;

  @override
  Widget build(BuildContext context) {
    final life = personal.lifetime;
    final days = life.watchedSeconds / 86400;
    return SettingsGroup(
      title: tr('Depuis mon arrivée'),
      children: [
        StatsFact(
          icon: Icons.all_inclusive_rounded,
          title: formatWatchTime(life.watchedSeconds),
          subtitle: [
            if (days >= 1)
              trPlural(days.floor(), 'soit {0} jour devant l’écran',
                  'soit {0} jours devant l’écran'),
            trPlural(life.plays, '{0} lecture', '{0} lectures'),
            if (personal.firstPlay case final first?)
              tr('depuis le {0}', [LocaleFormats.longDate(first)]),
          ].join(' · '),
        ),
        if (life.longestPlay case final longest?)
          StatsFact(
            icon: Icons.emoji_events_outlined,
            title: tr('Plus longue séance'),
            subtitle: tr('{0} · {1}',
                [formatWatchTime(longest.watchedSeconds), longest.title]),
          ),
        if (life.mostRewatched case final rewatch?)
          StatsFact(
            icon: Icons.replay_rounded,
            title: tr('Le plus revu'),
            subtitle: trPlural(rewatch.times, '{1}, vu {0} fois',
                '{1}, vu {0} fois', [rewatch.title]),
          ),
      ],
    );
  }
}
