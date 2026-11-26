import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../l10n/tmdb_genres.dart';
import '../../../../l10n/tr.dart';
import '../../../../models/models.dart';
import '../../../../models/server_activity.dart';
import '../../../../navigation/detail_flight.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_type.dart';
import '../../../../tv/tv_focus.dart';
import '../media_thumb.dart';
import '../settings_ui.dart';
import '../stats_charts.dart';

/// Les blocs « titres » de « Mes stats » : séries, films à finir, décennies,
/// genres et appareils.

/// Une ligne de statistique atteignable à la télécommande : sans elle, une
/// liste en lecture seule resterait hors de portée du focus, donc du
/// défilement. [onSelect] ouvre la fiche quand la ligne en a une.
class StatsRowFocus extends StatelessWidget {
  const StatsRowFocus({super.key, required this.child, this.onSelect});

  final Widget child;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final row = TvFocusable(
      onSelect: onSelect,
      focusScale: 1.0,
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
    if (onSelect == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        child: row,
      ),
    );
  }
}

/// Une ligne d'information (« Plus gros marathon »), en lecture seule.
class StatsFact extends StatelessWidget {
  const StatsFact({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => StatsRowFocus(
        child: SettingsTile(
          icon: icon,
          iconColor: iconColor,
          title: title,
          subtitle: subtitle,
        ),
      );
}

void _openTitle(BuildContext context, int id, MediaType type, String title,
    String posterUrl) {
  openMediaDetail(
    context,
    Media(
      id: id,
      type: type,
      title: title,
      duration: 0,
      posterUrl: posterUrl.isEmpty ? null : posterUrl,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
    measureCard: false,
  );
}

class MyShowsGroup extends StatelessWidget {
  const MyShowsGroup(this.stats, {super.key});
  final PersonalStats stats;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: tr('Mes séries'),
      footer: stats.showsCount > stats.shows.length
          ? tr('Les {0} séries les plus regardées sur {1}.',
              [stats.shows.length, stats.showsCount])
          : null,
      children: [
        if (stats.shows.isEmpty)
          SettingsEmptyNote(tr('Aucune série regardée sur cette période.'))
        else
          for (final show in stats.shows)
            StatsRowFocus(
              onSelect: () => _openTitle(context, show.showId, MediaType.show,
                  show.title, show.posterUrl),
              child: _ShowRow(show),
            ),
        if (stats.marathon case final marathon?)
          StatsFact(
            icon: Icons.local_fire_department_rounded,
            iconColor: AppColors.warning,
            title: tr('Plus gros marathon'),
            subtitle: [
              trPlural(marathon.episodes, '{0} épisode de {1}',
                  '{0} épisodes de {1}', [marathon.title]),
              if (marathon.date case final date?) formatDay(date),
            ].join(' · '),
          ),
      ],
    );
  }
}

class _ShowRow extends StatelessWidget {
  const _ShowRow(this.show);
  final ShowProgress show;

  @override
  Widget build(BuildContext context) {
    final total = show.episodesTotal;
    final ratio =
        total == 0 ? 0.0 : (show.episodesSeen / total).clamp(0.0, 1.0);
    final color = show.finished ? AppColors.success : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          MediaThumb(posterUrl: show.posterUrl, width: 34, isShow: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(show.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: AppType.body)),
                  ),
                  Text(
                    show.finished
                        ? tr('Terminée')
                        : total == 0
                            ? formatWatchTime(show.watchedSeconds)
                            : tr('{0} / {1} ép.', [show.episodesSeen, total]),
                    style: TextStyle(
                      color: show.finished
                          ? AppColors.success
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: AppType.footnote,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  tr('{0} regardées sur la période',
                      [formatWatchTime(show.watchedSeconds)]),
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.footnote),
                ),
                if (total > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      color: color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyMoviesGroup extends StatelessWidget {
  const MyMoviesGroup(this.stats, {super.key});
  final PersonalStats stats;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: tr('Films à finir'),
      footer: stats.averageMovieSeconds > 0
          ? tr('Vos films durent {0} en moyenne.',
              [formatWatchTime(stats.averageMovieSeconds)])
          : null,
      children: [
        if (stats.unfinishedMovies.isEmpty)
          SettingsEmptyNote(tr('Aucun film en cours : tout est fini.'))
        else
          for (final movie in stats.unfinishedMovies)
            StatsRowFocus(
              onSelect: () => _openTitle(context, movie.mediaId,
                  MediaType.movie, movie.title, movie.posterUrl),
              child: StatBarRow(
                leading: MediaThumb(posterUrl: movie.posterUrl, width: 34),
                label: movie.title,
                detail: tr('Vu à {0} %', [movie.percent]),
                value: movie.percent,
                max: 100,
                valueLabel: '${movie.percent} %',
              ),
            ),
      ],
    );
  }
}

/// Les décennies de sortie des titres regardés, en colonnes.
class MyDecadesGroup extends StatelessWidget {
  const MyDecadesGroup(this.decades, {super.key});
  final List<DecadeStat> decades;

  @override
  Widget build(BuildContext context) {
    final maxTitles = decades.fold<int>(0, (m, d) => math.max(m, d.titles));
    return SettingsGroup(
      title: tr('Mes décennies'),
      footer: tr('Selon l’année de sortie des films et des séries regardés.'),
      padded: true,
      children: [
        if (decades.isEmpty)
          SettingsEmptyNote(
              tr('Aucune date de sortie connue sur cette période.'))
        else
          StatsRowFocus(
            child: SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, d) in decades.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: trPlural(d.titles, '{0} titre', '{0} titres'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${d.titles}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: AppType.caption)),
                            const SizedBox(height: 4),
                            Container(
                              height: maxTitles == 0
                                  ? 3
                                  : math.max(3, 72 * d.titles / maxTitles),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_decadeLabel(d.decade),
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: AppType.caption)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// « 90s » pour le siècle dernier, « 2010s » ensuite : « 10s » ne se lit pas.
  static String _decadeLabel(int decade) => decade < 2000
      ? tr('{0}s', ['${decade % 100}'.padLeft(2, '0')])
      : tr('{0}s', [decade]);
}

class MyGenresGroup extends StatelessWidget {
  const MyGenresGroup(this.genres, {super.key, required this.hasPlays});
  final List<GenreStat> genres;
  final bool hasPlays;

  @override
  Widget build(BuildContext context) {
    final named = [
      for (final g in genres)
        if (tmdbGenreLabel(g.genreId) case final label?) (label, g),
    ];
    return SettingsGroup(
      title: tr('Mes genres'),
      footer: named.isEmpty
          ? null
          : tr('Un titre compte dans chacun de ses genres.'),
      children: [
        if (named.isEmpty)
          SettingsEmptyNote(hasPlays
              ? tr('Les genres de vos titres arrivent : le serveur les lit '
                  'peu à peu chez TMDB.')
              : tr('Aucune lecture sur cette période.'))
        else
          for (final (label, g) in named)
            StatsRowFocus(
              child: StatBarRow(
                leading:
                    const SettingsIcon(Icons.local_offer_outlined, size: 30),
                label: label,
                detail: trPlural(g.titles, '{0} titre', '{0} titres'),
                value: g.watchedSeconds,
                max: named.first.$2.watchedSeconds,
              ),
            ),
      ],
    );
  }
}

class MyDevicesGroup extends StatelessWidget {
  const MyDevicesGroup(this.devices, {super.key});
  final List<StatBucket> devices;

  /// « Android TV 1.4.2 » → « Android TV » : la version ne dit rien ici.
  static String _app(String client) {
    final words = client.split(' ');
    if (words.length > 1 && RegExp(r'^\d').hasMatch(words.last)) {
      words.removeLast();
    }
    return words.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: tr('Où je regarde'),
      children: [
        if (devices.isEmpty)
          SettingsEmptyNote(tr('Aucune lecture sur cette période.'))
        else
          for (final d in devices)
            StatsRowFocus(
              child: StatBarRow(
                leading: SettingsIcon(deviceIconFor(d.secondary), size: 30),
                label: d.label.isEmpty
                    ? (d.secondary.isEmpty
                        ? tr('Appareil sans nom')
                        : _app(d.secondary))
                    : d.label,
                detail: [
                  if (d.label.isNotEmpty && d.secondary.isNotEmpty)
                    _app(d.secondary),
                  trPlural(d.plays, '{0} lecture', '{0} lectures'),
                ].join(' · '),
                value: d.watchedSeconds,
                max: devices.first.watchedSeconds,
              ),
            ),
      ],
    );
  }
}
