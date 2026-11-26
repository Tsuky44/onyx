import 'server_activity.dart';

/// Le détail de « Mes stats » : la partie `personal` de `GET /api/me/stats`.
///
/// Un serveur plus ancien ne l'envoie pas : [PlaybackStats.personal] est
/// alors nul, et la page se contente des chiffres communs.
class PersonalStats {
  final bool allTime;

  /// Le jour de la première lecture du compte, s'il y en a une.
  final DateTime? firstPlay;

  /// La période de même durée juste avant ; nulle sur « Depuis le début ».
  final PeriodTotals? previous;
  final int streakCurrent;
  final int streakBest;

  /// 7 lignes (lundi d'abord) de 24 heures, en secondes vues.
  final List<List<int>> weekdayHour;
  final TitledSeconds? longestPlay;
  final MarathonStat? marathon;
  final int showsCount;
  final int showsFinished;
  final List<ShowProgress> shows;
  final List<UnfinishedMovie> unfinishedMovies;
  final int averageMovieSeconds;
  final List<DecadeStat> decades;
  final List<GenreStat> genres;
  final List<StatBucket> devices;
  final LifetimeStats lifetime;

  const PersonalStats({
    required this.allTime,
    required this.firstPlay,
    required this.previous,
    required this.streakCurrent,
    required this.streakBest,
    required this.weekdayHour,
    required this.longestPlay,
    required this.marathon,
    required this.showsCount,
    required this.showsFinished,
    required this.shows,
    required this.unfinishedMovies,
    required this.averageMovieSeconds,
    required this.decades,
    required this.genres,
    required this.devices,
    required this.lifetime,
  });

  factory PersonalStats.fromJson(Map<String, dynamic> json) {
    final streak = _map(json['streak']);
    final grid = _list(json['weekday_hour']);
    return PersonalStats(
      allTime: json['all_time'] == true,
      firstPlay: DateTime.tryParse(_str(json['first_play'])),
      previous: _maybe(json['previous'], PeriodTotals.fromJson),
      streakCurrent: _int(streak['current']),
      streakBest: _int(streak['best']),
      weekdayHour: [
        for (var d = 0; d < 7; d++)
          [
            for (var h = 0; h < 24; h++)
              d < grid.length && h < _list(grid[d]).length
                  ? _int(_list(grid[d])[h])
                  : 0,
          ],
      ],
      longestPlay: _maybe(json['longest_play'], TitledSeconds.fromJson),
      marathon: _maybe(json['marathon'], MarathonStat.fromJson),
      showsCount: _int(json['shows_count']),
      showsFinished: _int(json['shows_finished']),
      shows: _objects(json['shows'], ShowProgress.fromJson),
      unfinishedMovies:
          _objects(json['unfinished_movies'], UnfinishedMovie.fromJson),
      averageMovieSeconds: _int(json['average_movie_seconds']),
      decades: _objects(json['decades'], DecadeStat.fromJson),
      genres: _objects(json['genres'], GenreStat.fromJson),
      devices: _objects(json['devices'], StatBucket.fromJson),
      lifetime: LifetimeStats.fromJson(_map(json['lifetime'])),
    );
  }
}

class PeriodTotals {
  final int plays;
  final int watchedSeconds;
  const PeriodTotals(this.plays, this.watchedSeconds);
  factory PeriodTotals.fromJson(Map<String, dynamic> json) =>
      PeriodTotals(_int(json['plays']), _int(json['watched_seconds']));
}

class TitledSeconds {
  final String title;
  final int watchedSeconds;
  const TitledSeconds(this.title, this.watchedSeconds);
  factory TitledSeconds.fromJson(Map<String, dynamic> json) =>
      TitledSeconds(_str(json['title']), _int(json['watched_seconds']));
}

class MarathonStat {
  final String title;
  final DateTime? date;
  final int episodes;
  const MarathonStat(this.title, this.date, this.episodes);
  factory MarathonStat.fromJson(Map<String, dynamic> json) => MarathonStat(
        _str(json['title']),
        DateTime.tryParse(_str(json['date'])),
        _int(json['episodes']),
      );
}

/// Une série regardée sur la période, avec son avancement selon le serveur.
class ShowProgress {
  final int showId;
  final String title;
  final String posterUrl;
  final int watchedSeconds;
  final int episodesSeen;
  final int episodesTotal;
  final bool finished;

  const ShowProgress({
    required this.showId,
    required this.title,
    required this.posterUrl,
    required this.watchedSeconds,
    required this.episodesSeen,
    required this.episodesTotal,
    required this.finished,
  });

  factory ShowProgress.fromJson(Map<String, dynamic> json) => ShowProgress(
        showId: _int(json['show_id']),
        title: _str(json['title']),
        posterUrl: _str(json['poster_url']),
        watchedSeconds: _int(json['watched_seconds']),
        episodesSeen: _int(json['episodes_seen']),
        episodesTotal: _int(json['episodes_total']),
        finished: json['finished'] == true,
      );
}

class UnfinishedMovie {
  final int mediaId;
  final String title;
  final String posterUrl;
  final int percent;
  const UnfinishedMovie(this.mediaId, this.title, this.posterUrl, this.percent);
  factory UnfinishedMovie.fromJson(Map<String, dynamic> json) =>
      UnfinishedMovie(_int(json['media_id']), _str(json['title']),
          _str(json['poster_url']), _int(json['percent']));
}

class DecadeStat {
  final int decade;
  final int titles;
  final int watchedSeconds;
  const DecadeStat(this.decade, this.titles, this.watchedSeconds);
  factory DecadeStat.fromJson(Map<String, dynamic> json) => DecadeStat(
      _int(json['decade']),
      _int(json['titles']),
      _int(json['watched_seconds']));
}

/// Un genre TMDB (identifiant), que l'app nomme dans sa langue.
class GenreStat {
  final int genreId;
  final int titles;
  final int watchedSeconds;
  const GenreStat(this.genreId, this.titles, this.watchedSeconds);
  factory GenreStat.fromJson(Map<String, dynamic> json) => GenreStat(
      _int(json['genre_id']),
      _int(json['titles']),
      _int(json['watched_seconds']));
}

class LifetimeStats {
  final int plays;
  final int watchedSeconds;
  final TitledSeconds? longestPlay;
  final ({String title, int times})? mostRewatched;

  const LifetimeStats({
    required this.plays,
    required this.watchedSeconds,
    required this.longestPlay,
    required this.mostRewatched,
  });

  factory LifetimeStats.fromJson(Map<String, dynamic> json) {
    final rewatch = json['most_rewatched'];
    return LifetimeStats(
      plays: _int(json['plays']),
      watchedSeconds: _int(json['watched_seconds']),
      longestPlay: _maybe(json['longest_play'], TitledSeconds.fromJson),
      mostRewatched: rewatch is Map<String, dynamic>
          ? (title: _str(rewatch['title']), times: _int(rewatch['times']))
          : null,
    );
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';
List<Object?> _list(Object? v) => v is List ? v : const [];
Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const {};
T? _maybe<T>(Object? v, T Function(Map<String, dynamic>) parse) =>
    v is Map<String, dynamic> ? parse(v) : null;
List<T> _objects<T>(Object? v, T Function(Map<String, dynamic>) parse) => [
      for (final e in _list(v))
        if (e is Map<String, dynamic>) parse(e),
    ];
