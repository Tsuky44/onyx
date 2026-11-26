import 'personal_stats.dart' show MarathonStat;
import 'server_activity.dart' show StatBucket;

/// Le Rétro de fin d'année (ADR 2026-11-26-tsuky-retro-annuel).
///
/// Le serveur calcule tout, y compris le profil de fin ; l'app le raconte.
/// Voir `server/handlers/retro*.go` et `docs/retro-annuel.md`.

/// `GET /api/me/retro` : ce que l'accueil doit savoir pour montrer la diapo,
/// l'anneau de l'avatar ou la carte « Revoir ».
class RetroStatus {
  final int year;

  /// Visible maintenant : du 1er décembre au 15 janvier.
  final bool open;

  /// Au moins 5 h de lecture sur l'année.
  final bool eligible;

  /// Déjà ouvert, sur n'importe quel appareil du compte.
  final bool seen;

  /// Le premier instant où il ne se montre plus.
  final DateTime? endsAt;

  const RetroStatus({
    required this.year,
    required this.open,
    required this.eligible,
    required this.seen,
    required this.endsAt,
  });

  /// Rien ne s'affiche hors saison ni sous le seuil.
  bool get available => open && eligible;

  RetroStatus copyWith({bool? seen}) => RetroStatus(
        year: year,
        open: open,
        eligible: eligible,
        seen: seen ?? this.seen,
        endsAt: endsAt,
      );

  factory RetroStatus.fromJson(Map<String, dynamic> json) => RetroStatus(
        year: _int(json['year']),
        open: json['open'] == true,
        eligible: json['eligible'] == true,
        seen: json['seen'] == true,
        endsAt: DateTime.tryParse(_str(json['ends_at'])),
      );
}

/// Les identifiants de profil que le serveur choisit (`retro_archetype.go`).
/// L'app les nomme (`l10n/retro_archetypes.dart`).
enum RetroArchetype {
  marathon('marathon'),
  nightOwl('night_owl'),
  cinephile('cinephile'),
  explorer('explorer'),
  weekend('weekend'),
  goodAudience('good_audience');

  const RetroArchetype(this.wire);
  final String wire;

  /// Un identifiant inconnu (un serveur plus récent) devient le profil par
  /// défaut plutôt qu'un écran vide.
  static RetroArchetype parse(String wire) => values.firstWhere(
        (a) => a.wire == wire,
        orElse: () => RetroArchetype.goodAudience,
      );
}

/// `GET /api/me/retro/:year`.
class RetroReport {
  final int year;

  /// Faux sous 5 h de lecture : le reste est alors vide.
  final bool eligible;
  final int watchedSeconds;
  final int plays;
  final int titles;
  final int movieSeconds;
  final List<RetroTitle> top;

  /// 12 totaux en secondes, janvier d'abord.
  final List<int> months;

  /// 24 totaux en secondes, à l'heure de l'appareil.
  final List<int> hours;

  /// 7 totaux en secondes, lundi d'abord.
  final List<int> weekdays;
  final MarathonStat? marathon;
  final RetroMoment? firstPlay;
  final RetroMoment? latestNight;
  final List<StatBucket> devices;

  /// Part du temps lue telle quelle, sans conversion par le serveur.
  final int directPercent;
  final RetroArchetype archetype;
  final RetroServerShare server;

  const RetroReport({
    required this.year,
    required this.eligible,
    required this.watchedSeconds,
    required this.plays,
    required this.titles,
    required this.movieSeconds,
    required this.top,
    required this.months,
    required this.hours,
    required this.weekdays,
    required this.marathon,
    required this.firstPlay,
    required this.latestNight,
    required this.devices,
    required this.directPercent,
    required this.archetype,
    required this.server,
  });

  factory RetroReport.fromJson(Map<String, dynamic> json) => RetroReport(
        year: _int(json['year']),
        eligible: json['eligible'] == true,
        watchedSeconds: _int(json['watched_seconds']),
        plays: _int(json['plays']),
        titles: _int(json['titles']),
        movieSeconds: _int(json['movie_seconds']),
        top: _list(json['top']).map((e) => RetroTitle.fromJson(_map(e))).toList(),
        months: _ints(json['months'], 12),
        hours: _ints(json['hours'], 24),
        weekdays: _ints(json['weekdays'], 7),
        marathon: json['marathon'] is Map
            ? MarathonStat.fromJson(_map(json['marathon']))
            : null,
        firstPlay: RetroMoment.tryParse(json['first_play']),
        latestNight: RetroMoment.tryParse(json['latest_night']),
        devices: _list(json['devices'])
            .map((e) => StatBucket.fromJson(_map(e)))
            .toList(),
        directPercent: _int(json['direct_percent']),
        archetype: RetroArchetype.parse(_str(json['archetype'])),
        server: RetroServerShare.fromJson(_map(json['server'])),
      );

  double get hoursWatched => watchedSeconds / 3600;

  /// L'heure où commence le plus de temps regardé.
  int get peakHour => _argMax(hours);

  /// Le mois le plus regardé, de 1 à 12.
  int get bestMonth => _argMax(months) + 1;

  /// Part du temps entre 22 h et 4 h, comme la règle « Oiseau de nuit ».
  double get nightShare => _share([
        for (var h = 0; h < hours.length; h++)
          if (h >= 22 || h < 4) hours[h],
      ]);

  /// Part du temps le samedi et le dimanche.
  double get weekendShare =>
      weekdays.length == 7 ? _share([weekdays[5], weekdays[6]]) : 0;

  double get movieShare =>
      watchedSeconds > 0 ? movieSeconds / watchedSeconds : 0;

  double _share(List<int> part) => watchedSeconds > 0
      ? part.fold<int>(0, (a, b) => a + b) / watchedSeconds
      : 0;
}

/// Un titre du top 5 : une série (ses épisodes réunis) ou un film.
class RetroTitle {
  final int mediaId;
  final String title;
  final bool isShow;
  final String posterUrl;
  final int watchedSeconds;

  /// Épisodes différents, pour une série.
  final int episodes;

  /// Fois vu à moitié au moins, pour un film.
  final int times;

  const RetroTitle({
    required this.mediaId,
    required this.title,
    required this.isShow,
    required this.posterUrl,
    required this.watchedSeconds,
    required this.episodes,
    required this.times,
  });

  factory RetroTitle.fromJson(Map<String, dynamic> json) => RetroTitle(
        mediaId: _int(json['media_id']),
        title: _str(json['title']),
        isShow: json['media_type'] == 'show',
        posterUrl: _str(json['poster_url']),
        watchedSeconds: _int(json['watched_seconds']),
        episodes: _int(json['episodes']),
        times: _int(json['times']),
      );
}

/// Une séance datée, à l'heure de l'appareil qui a demandé le Rétro.
class RetroMoment {
  final String title;
  final DateTime at;

  const RetroMoment(this.title, this.at);

  static RetroMoment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(_str(raw['at']));
    if (at == null) return null;
    return RetroMoment(_str(raw['title']), at);
  }
}

/// La place du compte sur son serveur. Des agrégats : personne n'y est nommé.
class RetroServerShare {
  final int members;
  final int watchedSeconds;

  /// 1 pour le compte qui a le plus regardé ; 0 s'il n'est pas classé.
  final int rank;
  final String topTitle;
  final int topTitleViewers;

  const RetroServerShare({
    required this.members,
    required this.watchedSeconds,
    required this.rank,
    required this.topTitle,
    required this.topTitleViewers,
  });

  factory RetroServerShare.fromJson(Map<String, dynamic> json) =>
      RetroServerShare(
        members: _int(json['members']),
        watchedSeconds: _int(json['watched_seconds']),
        rank: _int(json['rank']),
        topTitle: _str(json['top_title']),
        topTitleViewers: _int(json['top_title_viewers']),
      );

  /// Part des autres membres qui ont regardé moins : 100 pour le premier,
  /// 0 pour le dernier. Nul quand on est seul.
  int get aheadOfPercent {
    if (members < 2 || rank < 1) return 0;
    return ((members - rank) * 100 / (members - 1)).round();
  }
}

int _argMax(List<int> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) best = i;
  }
  return best;
}

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';
List<Object?> _list(Object? v) => v is List ? v : const [];
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Une série de longueur fixe : un serveur qui en enverrait moins ne fait pas
/// sortir un graphique de ses bornes.
List<int> _ints(Object? v, int length) {
  final values = _list(v).map(_int).toList();
  return List<int>.generate(length, (i) => i < values.length ? values[i] : 0);
}
