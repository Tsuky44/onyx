import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../utils/format.dart';
import '../../utils/poster_url.dart';
import 'player_media_info.dart';

/// Ce que montre l'écran « Vous regardez » d'un film en pause (ADR-0137),
/// tiré une fois de ce que le lecteur sait déjà : le média, la fiche en cache
/// (celle du film, ou celle de la série pour un épisode) et la position.
///
/// Rien n'est demandé au serveur pour l'écrire : une fiche absente laisse
/// seulement des lignes vides, et l'écran se contente du titre et du résumé
/// que porte le média.
class PauseInfoContent {
  const PauseInfoContent({
    required this.isEpisode,
    required this.title,
    this.logoUrl,
    this.showTitle,
    this.episodeLine,
    this.meta = const [],
    this.rating,
    this.tagline,
    this.overview,
    this.director,
    this.cast,
    this.remaining,
    this.endClock,
    this.progress = 0,
    this.nextEpisodeTitle,
    this.nextEpisodeMeta,
    this.nextEpisodeStillUrl,
  });

  factory PauseInfoContent.from({
    required PlayerMediaInfo info,
    MediaDetails? details,
    HomeMediaItem? nextEpisode,
    required int positionSeconds,
    required int durationSeconds,
    String? logoUrl,
    String? serverBaseUrl,
    DateTime? now,
  }) {
    final media = info.media;
    final duration =
        durationSeconds > 0 ? durationSeconds : info.knownDurationSeconds;
    final left = duration > 0 ? duration - positionSeconds : 0;
    final genres = details?.genres.take(2).join(', ') ?? '';
    // Pour un épisode, la fiche en cache est celle de la série : sa note est
    // celle de la série, la seule que le serveur connaisse.
    final vote = details?.voteAverage ?? 0;
    final logo = _text(logoUrl);

    if (info.isEpisode) {
      final season = media.effectiveSeasonNumber;
      final episode = media.effectiveEpisodeNumber;
      return PauseInfoContent(
        isEpisode: true,
        title: info.item?.episodeTitle ?? media.title,
        logoUrl: logo,
        showTitle: info.showTitle,
        episodeLine:
            season != null && episode != null && season > 0 && episode > 0
                ? tr('Saison {0} · Épisode {1}', [season, episode])
                : null,
        meta: _parts([
          formatReleaseDay(media.releaseDate),
          formatDuration(duration),
          genres,
        ]),
        rating: vote > 0 ? vote : null,
        overview: _text(media.overview),
        remaining: left > 0 ? formatRemaining(left) : null,
        endClock: left > 0 ? formatEndClock(left, now: now) : null,
        progress: _progress(positionSeconds, duration),
        nextEpisodeTitle: nextEpisode == null
            ? null
            : nextEpisode.episodeTitle ?? nextEpisode.media.title,
        nextEpisodeMeta: nextEpisode == null
            ? null
            : _parts([
                nextEpisode.media.seasonEpisodeCode,
                formatDuration(nextEpisode.effectiveDuration),
              ]).join(' · '),
        // L'image d'un épisode est une image de l'épisode (16:9), pas
        // l'affiche de la série.
        nextEpisodeStillUrl: nextEpisode == null
            ? null
            : resolvePosterUrl(
                nextEpisode.media.posterUrl,
                serverBaseUrl: serverBaseUrl,
              ),
      );
    }

    final runtime = details != null && details.runtime > 0
        ? details.runtime * 60
        : duration;
    return PauseInfoContent(
      isEpisode: false,
      title: info.showTitle,
      logoUrl: logo,
      meta: _parts([
        extractYear(details?.releaseDate ?? media.releaseDate),
        genres,
        formatDuration(runtime),
      ]),
      rating: vote > 0 ? vote : null,
      tagline: _text(details?.tagline),
      overview: _text(details?.overview) ?? _text(media.overview),
      director: _text(details?.director),
      cast: _castLine(details?.cast ?? const []),
      remaining: left > 0 ? formatRemaining(left) : null,
      endClock: left > 0 ? formatEndClock(left, now: now) : null,
      progress: _progress(positionSeconds, duration),
    );
  }

  final bool isEpisode;

  /// Le titre du film, ou celui de l'épisode.
  final String title;

  /// Le logo-titre du film, ou de la série d'un épisode : celui que le chrome
  /// du lecteur affiche déjà, donc déjà en mémoire.
  final String? logoUrl;

  /// La série d'un épisode.
  final String? showTitle;

  /// « Saison 2 · Épisode 5 ».
  final String? episodeLine;

  /// Année ou date de diffusion, genres, durée : déjà sans parties vides.
  final List<String> meta;

  /// La note TMDB, sur 10 : celle du film, ou celle de la série.
  final double? rating;
  final String? tagline;
  final String? overview;
  final String? director;

  /// Les trois premiers rôles, à la suite.
  final String? cast;

  /// « 1h 12min restantes ».
  final String? remaining;

  /// L'heure à laquelle le titre se termine si la lecture reprend maintenant.
  final String? endClock;

  /// Entre 0 et 1.
  final double progress;
  final String? nextEpisodeTitle;
  final String? nextEpisodeMeta;

  /// L'image de l'épisode suivant.
  final String? nextEpisodeStillUrl;

  /// « 7.8 », écrite comme dans le reste de l'app (les téléchargements).
  String? get ratingLabel => rating?.toStringAsFixed(1);

  static List<String> _parts(List<String?> parts) => [
        for (final part in parts)
          if (part != null && part.trim().isNotEmpty) part.trim(),
      ];

  static String? _text(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _castLine(List<CastMember> cast) {
    final names = [
      for (final member in cast.take(3))
        if (member.name.trim().isNotEmpty) member.name.trim(),
    ];
    return names.isEmpty ? null : names.join(', ');
  }

  static double _progress(int position, int duration) {
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }
}
