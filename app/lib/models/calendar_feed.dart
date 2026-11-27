/// La réponse de `GET /api/calendar` (ADR
/// 2026-11-27-tsuky-calendrier-sorties-serveur), telle que le serveur
/// l'envoie. `CalendarProvider` la traduit en [CalendarEntry] pour les vues.
library;

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';

/// Une sortie : un épisode ou un film.
class CalendarFeedEntry {
  final String id;

  /// `show` ou `movie`.
  final String kind;

  /// `watching`, `followed`, `request` ou `server`.
  final String source;
  final int tmdbId;

  /// La fiche de la bibliothèque, 0 quand le serveur n'a pas le titre.
  final int mediaId;

  /// L'épisode déjà présent sur le serveur, 0 sinon.
  final int episodeMediaId;
  final String title;

  /// AAAA-MM-JJ.
  final String airDate;
  final int seasonNumber;
  final int episodeNumber;
  final String episodeName;

  /// `premiere`, `finale` ou vide.
  final String episodeType;

  /// `digital`, `physical`, `theatrical` (films), vide pour un épisode.
  final String releaseType;
  final String posterUrl;
  final String stillUrl;
  final bool ready;

  const CalendarFeedEntry({
    required this.id,
    required this.kind,
    required this.source,
    required this.tmdbId,
    required this.mediaId,
    required this.episodeMediaId,
    required this.title,
    required this.airDate,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeName,
    required this.episodeType,
    required this.releaseType,
    required this.posterUrl,
    required this.stillUrl,
    required this.ready,
  });

  factory CalendarFeedEntry.fromJson(Map<String, dynamic> json) =>
      CalendarFeedEntry(
        id: _str(json['id']),
        kind: _str(json['kind']),
        source: _str(json['source']),
        tmdbId: _int(json['tmdb_id']),
        mediaId: _int(json['media_id']),
        episodeMediaId: _int(json['episode_media_id']),
        title: _str(json['title']),
        airDate: _str(json['air_date']),
        seasonNumber: _int(json['season_number']),
        episodeNumber: _int(json['episode_number']),
        episodeName: _str(json['episode_name']),
        episodeType: _str(json['episode_type']),
        releaseType: _str(json['release_type']),
        posterUrl: _str(json['poster_url']),
        stillUrl: _str(json['still_url']),
        ready: json['ready'] == true,
      );
}

/// Une série du calendrier, pour « Séries suivies » et le bouton Suivre.
class CalendarFeedShow {
  final int tmdbId;
  final int mediaId;
  final String title;
  final String source;
  final String posterUrl;

  /// AAAA-MM-JJ, vide quand TMDB n'annonce rien.
  final String nextAirDate;
  final int nextSeason;
  final int nextEpisode;

  const CalendarFeedShow({
    required this.tmdbId,
    required this.mediaId,
    required this.title,
    required this.source,
    required this.posterUrl,
    required this.nextAirDate,
    required this.nextSeason,
    required this.nextEpisode,
  });

  factory CalendarFeedShow.fromJson(Map<String, dynamic> json) =>
      CalendarFeedShow(
        tmdbId: _int(json['tmdb_id']),
        mediaId: _int(json['media_id']),
        title: _str(json['title']),
        source: _str(json['source']),
        posterUrl: _str(json['poster_url']),
        nextAirDate: _str(json['next_air_date']),
        nextSeason: _int(json['next_season']),
        nextEpisode: _int(json['next_episode']),
      );
}

class CalendarFeed {
  final String from;
  final String to;
  final String today;
  final List<CalendarFeedEntry> entries;
  final List<CalendarFeedShow> followed;

  const CalendarFeed({
    required this.from,
    required this.to,
    required this.today,
    required this.entries,
    required this.followed,
  });

  factory CalendarFeed.fromJson(Map<String, dynamic> json) => CalendarFeed(
        from: _str(json['from']),
        to: _str(json['to']),
        today: _str(json['today']),
        entries: [
          for (final e in (json['entries'] as List? ?? const []))
            CalendarFeedEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
        followed: [
          for (final f in (json['followed'] as List? ?? const []))
            CalendarFeedShow.fromJson(Map<String, dynamic>.from(f as Map)),
        ],
      );
}
