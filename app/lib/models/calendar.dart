/// Modèles UI du calendrier des sorties (« À venir »).
///
/// Ces types portent uniquement les données affichées par les vues Agenda,
/// Semaine, Mois et Affiche. `CalendarProvider` les construit à partir de
/// `GET /api/calendar` (`calendar_feed.dart`).
enum CalendarEntryKind { show, movie }

/// Raison pour laquelle une sortie apparaît dans le calendrier personnel.
enum CalendarSource { watching, followed, request, server }

/// Mode d'affichage sur bureau et tablette.
enum CalendarViewMode { week, month }

/// Filtre principal de l'agenda mobile.
enum CalendarKindFilter { all, shows }

/// Filtre par origine de la sortie dans l'agenda mobile.
enum CalendarSourceFilter { all, mine, request, server, movie }

/// Une sortie (épisode ou film) affichée dans le calendrier.
class CalendarEntry {
  final String id;
  final String showId;
  final String title;
  final CalendarEntryKind kind;

  /// Date locale tronquée à minuit.
  final DateTime date;

  /// Ex. « S2 · É9 », « S3 · É1 · Retour », « Film · sortie numérique ».
  final String subtitle;

  /// Heure optionnelle (« 03:00 », « 21:00 ») pour distinguer « Ce soir ».
  final String? timeLabel;
  final CalendarSource source;

  /// Teinte HSL de repli pour la vignette fictive tant qu'il n'y a pas
  /// d'image serveur (`posterUrl == null`).
  final double hue;
  final String? posterUrl;

  /// Déjà disponible sur le serveur : affiche la pastille « Disponible » et
  /// le bouton lecture.
  final bool ready;

  /// Identifiant média éventuel quand la fiche correspond à un titre réel.
  final int? mediaId;

  /// Identifiant TMDB du titre : ouvre la fiche de demande quand le serveur
  /// n'a pas encore le titre.
  final int? tmdbId;

  /// L'épisode déjà sur le serveur, à lancer directement.
  final int? episodeMediaId;
  final int? seasonNumber;
  final int? episodeNumber;

  const CalendarEntry({
    required this.id,
    required this.showId,
    required this.title,
    required this.kind,
    required this.date,
    required this.subtitle,
    this.timeLabel,
    required this.source,
    required this.hue,
    this.posterUrl,
    this.ready = false,
    this.mediaId,
    this.tmdbId,
    this.episodeMediaId,
    this.seasonNumber,
    this.episodeNumber,
  });

  /// Libellé court d'épisode sans mention additionnelle (ex. « S2 · É9 »).
  String get shortEpisodeLabel {
    final parts = subtitle.split(' · ');
    if (parts.length <= 2) return subtitle;
    return '${parts[0]} · ${parts[1]}';
  }
}

/// Série suivie (automatiquement ou manuellement) dans le calendrier.
class CalendarFollowedShow {
  final String id;
  final String title;
  final CalendarSource source;
  final double hue;
  final String? nextSummary;
  final int? mediaId;
  final int? tmdbId;

  const CalendarFollowedShow({
    required this.id,
    required this.title,
    required this.source,
    required this.hue,
    this.nextSummary,
    this.mediaId,
    this.tmdbId,
  });

  /// Vrai lorsque le suivi vient d'une action manuelle sur la fiche.
  bool get isManual => source == CalendarSource.followed;
}
