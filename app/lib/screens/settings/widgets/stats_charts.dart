import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../models/server_activity.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_focus.dart';
import 'media_thumb.dart';
import 'settings_ui.dart';

/// Les graphiques des statistiques, partagés par celles du serveur
/// (`stats_page.dart`) et « Mes stats » (`my_stats_page.dart`).

/// Le pas d'une barre du graphique par jour.
enum ChartStep { day, week, month }

/// Au-delà de quelques mois, une barre par jour devient un trait d'un pixel
/// et des centaines de cibles de focus : la série se regroupe par semaine,
/// puis par mois. Une barre porte la date de son premier jour.
({ChartStep step, List<DailyStat> bars}) groupDailyForChart(
    List<DailyStat> daily) {
  if (daily.length <= 92) return (step: ChartStep.day, bars: daily);
  final step = daily.length <= 400 ? ChartStep.week : ChartStep.month;
  final bars = <DailyStat>[];
  DateTime? start;
  var plays = 0, watched = 0;
  // En jours du calendrier : un passage à l'heure d'été fait une journée de
  // 23 h, que `difference().inDays` compterait pour zéro.
  int dayNumber(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  bool sameBar(DateTime from, DateTime day) => step == ChartStep.week
      ? dayNumber(day) - dayNumber(from) < 7
      : day.year == from.year && day.month == from.month;
  for (final day in daily) {
    if (start != null && !sameBar(start, day.date)) {
      bars.add(DailyStat(start, plays, watched));
      plays = 0;
      watched = 0;
      start = null;
    }
    start ??= day.date;
    plays += day.plays;
    watched += day.watchedSeconds;
  }
  if (start != null) bars.add(DailyStat(start, plays, watched));
  return (step: step, bars: bars);
}

/// Ce que désigne une barre : un jour, une semaine ou un mois.
String chartBarLabel(ChartStep step, DateTime date) => switch (step) {
      ChartStep.day => formatDay(date),
      ChartStep.week => tr('semaine du {0}', [formatShortDate(date)]),
      ChartStep.month => LocaleFormats.monthYear(date),
    };

class DailyWatchChart extends StatefulWidget {
  const DailyWatchChart(this.daily, {super.key});
  final List<DailyStat> daily;

  @override
  State<DailyWatchChart> createState() => _DailyWatchChartState();
}

class _DailyWatchChartState extends State<DailyWatchChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final grouped = groupDailyForChart(widget.daily);
    final daily = grouped.bars;
    if (daily.isEmpty) return const SizedBox(height: 160);
    final maxValue = daily.map((d) => d.watchedSeconds).fold<int>(0, math.max);
    final focus = _hovered == null ? null : daily[_hovered!];
    final total = daily.fold<int>(0, (s, d) => s + d.watchedSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              focus == null
                  ? formatWatchTime(total)
                  : formatWatchTime(focus.watchedSeconds),
              style: const TextStyle(
                  fontSize: AppType.title3, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            // Sur un téléphone, « lundi 14 septembre · 3 lectures » ne tient
            // pas à côté du total.
            Flexible(
              child: Text(
                focus == null
                    ? tr('sur la période')
                    : '${chartBarLabel(grouped.step, focus.date)} · ${trPlural(focus.plays, '{0} lecture', '{0} lectures')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: AppType.subhead),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: LayoutBuilder(builder: (context, constraints) {
            final gap = daily.length > 60
                ? 1.0
                : daily.length > 20
                    ? 3.0
                    : 6.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, day) in daily.indexed) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hovered = i),
                      onExit: (_) => setState(() => _hovered = null),
                      // Chaque jour se lit au survol ou au toucher ; à la
                      // télécommande, c'est le focus qui le désigne (le chiffre
                      // du dessus suit la barre), sans anneau sur une barre de
                      // quelques pixels.
                      child: TvFocusable(
                        showRing: false,
                        focusScale: 1.0,
                        onFocusChange: (focused) => setState(() {
                          if (focused) {
                            _hovered = i;
                          } else if (_hovered == i) {
                            _hovered = null;
                          }
                        }),
                        // Un lecteur d'écran lit la barre par ce nom, pas
                        // par sa hauteur (ADR-0054).
                        child: Semantics(
                          label: tr('{0} · {1}', [
                            chartBarLabel(grouped.step, day.date),
                            formatWatchTime(day.watchedSeconds),
                          ]),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                                () => _hovered = _hovered == i ? null : i),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(
                                  end: maxValue == 0
                                      ? 0
                                      : day.watchedSeconds / maxValue,
                                ),
                                duration: AppMotion.move(context,
                                    Duration(milliseconds: 350 + i * 6)),
                                curve: Curves.easeOutCubic,
                                builder: (_, value, __) => Container(
                                  height: math.max(3, 150 * value),
                                  decoration: BoxDecoration(
                                    color: day.watchedSeconds == 0
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : _hovered == i
                                            ? AppColors.accentMuted
                                            : AppColors.primary.withValues(
                                                alpha: _hovered == null
                                                    ? 0.9
                                                    : 0.5),
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(
                                          daily.length > 60 ? 1 : 4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatShortDate(daily.first.date),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: AppType.caption)),
            Text(formatShortDate(daily.last.date),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: AppType.caption)),
          ],
        ),
      ],
    );
  }
}

class HourWatchChart extends StatelessWidget {
  const HourWatchChart(this.hours, {super.key});
  final List<int> hours;

  @override
  Widget build(BuildContext context) {
    final maxValue = hours.fold<int>(0, math.max);
    return Column(
      children: [
        SizedBox(
          height: 70,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < 24; h++) ...[
                if (h > 0) const SizedBox(width: 3),
                Expanded(
                  child: Tooltip(
                    message: '${h}h – ${h + 1}h : ${formatWatchTime(hours[h])}',
                    child: Container(
                      height: maxValue == 0
                          ? 3
                          : math.max(3, 70 * hours[h] / maxValue),
                      decoration: BoxDecoration(
                        color: hours[h] == 0
                            ? Colors.white.withValues(alpha: 0.06)
                            : Color.lerp(
                                AppColors.primary.withValues(alpha: 0.35),
                                AppColors.accentMuted,
                                maxValue == 0 ? 0 : hours[h] / maxValue,
                              ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in const ['0h', '6h', '12h', '18h', '23h'])
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: AppType.caption)),
          ],
        ),
      ],
    );
  }
}

class RankedMediaRow extends StatelessWidget {
  const RankedMediaRow(
      {super.key, required this.rank, required this.media, required this.max});

  final int rank;
  final StatBucket media;
  final int max;

  @override
  Widget build(BuildContext context) {
    return StatBarRow(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank <= 3 ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          MediaThumb(
            posterUrl: media.posterUrl,
            width: 34,
            isShow: media.mediaType == 'show',
          ),
        ],
      ),
      label: media.label,
      detail: [
        if (media.secondary.isNotEmpty) media.secondary,
        trPlural(media.plays, '{0} lecture', '{0} lectures'),
      ].join(' · '),
      value: media.watchedSeconds,
      max: max,
    );
  }
}

/// Une ligne de classement avec sa barre proportionnelle.
class StatBarRow extends StatelessWidget {
  const StatBarRow({
    super.key,
    required this.leading,
    required this.label,
    required this.detail,
    required this.value,
    required this.max,
    this.valueLabel,
  });

  final Widget leading;
  final String label;
  final String detail;
  final int value;
  final int max;

  /// Le chiffre à droite ; un temps de visionnage par défaut.
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: AppType.body),
                      ),
                    ),
                    Text(
                      valueLabel ?? formatWatchTime(value),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppType.subhead,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppType.footnote)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: ratio),
                    duration: AppMotion.move(
                        context, const Duration(milliseconds: 500)),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
