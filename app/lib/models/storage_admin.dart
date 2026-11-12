/// Le gestionnaire de stockage de l'administration (ADR-0115) : ce que
/// chaque film ou série occupe sur le disque, qui l'a demandé, qui le regarde
/// et depuis quand personne ne l'a lancé.
library;

DateTime? _date(Object? raw) {
  final text = raw?.toString() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
}

int _int(Object? raw) => (raw as num?)?.toInt() ?? 0;

List<int> _ints(Object? raw) => [
      for (final value in raw as List? ?? const []) (value as num).toInt(),
    ];

/// Une demande MediaHub du titre : une par compte, saisons comprises.
class StorageRequest {
  const StorageRequest({
    required this.requester,
    required this.status,
    this.requestedAt,
    this.seasons = const [],
  });

  final String requester;
  final String status;
  final DateTime? requestedAt;
  final List<int> seasons;

  factory StorageRequest.fromJson(Map<String, dynamic> json) => StorageRequest(
        requester: json['requester']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        requestedAt: _date(json['requested_at']),
        seasons: _ints(json['seasons']),
      );
}

/// Une ligne de la liste : un film, ou une série avec tous ses épisodes.
class StorageItem {
  const StorageItem({
    required this.id,
    required this.isShow,
    required this.title,
    required this.size,
    this.tmdbId = 0,
    this.path = '',
    this.posterUrl,
    this.episodeCount = 0,
    this.addedAt,
    this.lastPlayedAt,
    this.requests = const [],
  });

  final int id;
  final bool isShow;
  final String title;
  final int size;
  final int tmdbId;
  final String path;
  final String? posterUrl;
  final int episodeCount;
  final DateTime? addedAt;

  /// La dernière lecture, tous comptes confondus. Nulle : jamais lancé.
  final DateTime? lastPlayedAt;
  final List<StorageRequest> requests;

  /// Depuis quand personne ne l'a regardé : depuis sa dernière lecture, ou
  /// depuis son ajout s'il n'a jamais été lancé.
  DateTime? get idleSince => lastPlayedAt ?? addedAt;

  factory StorageItem.fromJson(Map<String, dynamic> json) => StorageItem(
        id: _int(json['id']),
        isShow: json['type'] == 'show',
        title: json['title']?.toString() ?? '',
        size: _int(json['size']),
        tmdbId: _int(json['tmdb_id']),
        path: json['path']?.toString() ?? '',
        posterUrl: json['poster_url']?.toString(),
        episodeCount: _int(json['episode_count']),
        addedAt: _date(json['added_at']),
        lastPlayedAt: _date(json['last_played_at']),
        requests: [
          for (final r in json['requests'] as List? ?? const [])
            StorageRequest.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

class StorageList {
  const StorageList({required this.items, required this.requestsAvailable});

  final List<StorageItem> items;

  /// Faux quand MediaHub n'a pas répondu : « aucune demande » ne veut alors
  /// rien dire, et l'écran ne le prétend pas.
  final bool requestsAvailable;

  factory StorageList.fromJson(Map<String, dynamic> json) => StorageList(
        items: [
          for (final item in json['items'] as List? ?? const [])
            StorageItem.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        requestsAvailable: json['requests_available'] == true,
      );
}

class StorageSeason {
  const StorageSeason({
    required this.id,
    required this.number,
    required this.title,
    required this.size,
    required this.episodeCount,
  });

  final int id;
  final int number;
  final String title;
  final int size;
  final int episodeCount;

  factory StorageSeason.fromJson(Map<String, dynamic> json) => StorageSeason(
        id: _int(json['id']),
        number: _int(json['number']),
        title: json['title']?.toString() ?? '',
        size: _int(json['size']),
        episodeCount: _int(json['episode_count']),
      );
}

/// L'épisode qu'un compte a lu en dernier : « où il en est ».
class StorageViewerEpisode {
  const StorageViewerEpisode({
    required this.season,
    required this.episode,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.finished,
  });

  final int season;
  final int episode;
  final int positionSeconds;
  final int durationSeconds;
  final bool finished;

  factory StorageViewerEpisode.fromJson(Map<String, dynamic> json) =>
      StorageViewerEpisode(
        season: _int(json['season']),
        episode: _int(json['episode']),
        positionSeconds: _int(json['position_seconds']),
        durationSeconds: _int(json['duration_seconds']),
        finished: json['finished'] == true,
      );
}

class StorageViewer {
  const StorageViewer({
    required this.userId,
    required this.username,
    required this.finished,
    this.lastPlayedAt,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.watchedEpisodes = 0,
    this.totalEpisodes = 0,
    this.currentEpisode,
  });

  final int userId;
  final String username;
  final bool finished;
  final DateTime? lastPlayedAt;
  final int positionSeconds;
  final int durationSeconds;
  final int watchedEpisodes;
  final int totalEpisodes;
  final StorageViewerEpisode? currentEpisode;

  factory StorageViewer.fromJson(Map<String, dynamic> json) => StorageViewer(
        userId: _int(json['user_id']),
        username: json['username']?.toString() ?? '',
        finished: json['finished'] == true,
        lastPlayedAt: _date(json['last_played_at']),
        positionSeconds: _int(json['position_seconds']),
        durationSeconds: _int(json['duration_seconds']),
        watchedEpisodes: _int(json['watched_episodes']),
        totalEpisodes: _int(json['total_episodes']),
        currentEpisode: json['current_episode'] is Map
            ? StorageViewerEpisode.fromJson(
                Map<String, dynamic>.from(json['current_episode'] as Map))
            : null,
      );
}

class StorageDetails {
  const StorageDetails({
    required this.id,
    required this.isShow,
    required this.title,
    this.path = '',
    this.seasons = const [],
    this.viewers = const [],
  });

  final int id;
  final bool isShow;
  final String title;
  final String path;
  final List<StorageSeason> seasons;
  final List<StorageViewer> viewers;

  factory StorageDetails.fromJson(Map<String, dynamic> json) => StorageDetails(
        id: _int(json['id']),
        isShow: json['type'] == 'show',
        title: json['title']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        seasons: [
          for (final s in json['seasons'] as List? ?? const [])
            StorageSeason.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        viewers: [
          for (final v in json['viewers'] as List? ?? const [])
            StorageViewer.fromJson(Map<String, dynamic>.from(v as Map)),
        ],
      );
}

/// Ce que MediaHub a oublié du titre supprimé.
class StorageMediaHubRemoval {
  const StorageMediaHubRemoval({
    required this.manager,
    required this.managerRemoved,
    required this.requestsRemoved,
  });

  /// « sorraa » ou « arr » (Radarr/Sonarr).
  final String manager;
  final bool managerRemoved;
  final int requestsRemoved;

  factory StorageMediaHubRemoval.fromJson(Map<String, dynamic> json) =>
      StorageMediaHubRemoval(
        manager: json['manager']?.toString() ?? '',
        managerRemoved: json['managerRemoved'] == true,
        requestsRemoved: _int(json['requestsRemoved']),
      );
}

/// Ce qu'une suppression a libéré, et ce que MediaHub en a oublié (nul sans
/// MediaHub).
class StorageDeleteReport {
  const StorageDeleteReport({
    required this.filesRemoved,
    required this.bytesFreed,
    this.mediaHub,
  });

  final int filesRemoved;
  final int bytesFreed;
  final StorageMediaHubRemoval? mediaHub;

  factory StorageDeleteReport.fromJson(Map<String, dynamic> json) =>
      StorageDeleteReport(
        filesRemoved: _int(json['files_removed']),
        bytesFreed: _int(json['bytes_freed']),
        mediaHub: json['mediahub'] is Map
            ? StorageMediaHubRemoval.fromJson(
                Map<String, dynamic>.from(json['mediahub'] as Map))
            : null,
      );
}
