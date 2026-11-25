/// Holds the result of starting an HLS transcoding session.
///
/// [masterUrl] is opened directly by media_kit/mpv, which fetches the child
/// playlists and segments itself (no local temp file, no playlist rewriting).
class HlsSession {
  final String sessionId;
  final String masterUrl;
  final double totalDuration; // full media duration in seconds
  final int startOffset; // seconds into the original media

  /// Source audio tracks published as HLS renditions, in the order the player
  /// enumerates them: position k in the player's audio track list is source
  /// track `audioMap[k]`. This is what lets a language change be an mpv track
  /// switch instead of a whole new transcoding session.
  final List<int> audioMap;

  /// Bitmap subtitle stream the server actually rendered into the video, or -1.
  /// It can differ from what was requested when the track turned out not to be
  /// burnable, so the client should trust this rather than its own request.
  final int burnedSubtitle;

  /// `copy` when the server is repackaging the picture untouched, `encode` when
  /// it is re-encoding it. Empty from a server that predates the field.
  ///
  /// Worth surfacing rather than guessing: "Direct Stream" and "why is the
  /// server's CPU at 400%" are the same question, and only the server knows.
  final String videoMode;

  /// Why a copy was refused, in the server's own words. Empty on the copy path.
  final String videoReason;

  /// Les pistes texte que la session écrit elle-même, au fil du transcodage.
  /// Voir ADR-0031.
  ///
  /// Null quand le serveur est plus ancien que ces sous-titres : il faut alors
  /// passer par l'extraction d'avant. Une liste vide, elle, dit seulement que
  /// le fichier n'a pas de piste texte.
  final List<LiveSubtitleSource>? subtitles;

  /// Ce que la session garde derrière le dernier segment demandé, en
  /// secondes ; au-delà, le serveur les a effacés et reculer demande une
  /// nouvelle session. Null : tout est gardé.
  final int? retainSeconds;

  /// Vrai quand le serveur garde cette session en attente : elle ne remplace
  /// celle qui est lue qu'à son premier segment demandé. Faux d'un serveur qui
  /// ne connaît pas l'attente, où demander une session condamne déjà
  /// l'ancienne. Voir ADR-0056.
  final bool standby;

  /// Le barreau que le serveur sert. Null d'un serveur qui ne le renvoyait pas
  /// encore lu ici : c'est alors celui demandé.
  final String? quality;

  /// Le barreau demandé, seulement quand le serveur en a servi un autre :
  /// l'Auto (`auto=1`) demandait plus que ce que la machine tient.
  final String? requestedQuality;

  /// Ce que le serveur prévoit de sa machine pour cette session :
  /// [capacityDegraded] (l'Auto a été descendu, voir [requestedQuality]) ou
  /// [capacityTooHeavy] (servi tel quel, peut saccader). Null quand le
  /// serveur tient le barreau, ou d'un serveur sans budget
  /// (`ServerCapabilities.transcodeCapacity`).
  final String? capacityWarning;

  static const capacityDegraded = 'degraded';
  static const capacityTooHeavy = 'too_heavy';

  HlsSession({
    required this.sessionId,
    required this.masterUrl,
    required this.totalDuration,
    required this.startOffset,
    this.audioMap = const [],
    this.burnedSubtitle = -1,
    this.videoMode = '',
    this.videoReason = '',
    this.subtitles,
    this.retainSeconds,
    this.standby = false,
    this.quality,
    this.requestedQuality,
    this.capacityWarning,
  });

  /// True when the picture is reaching the viewer untouched.
  bool get isDirectStream => videoMode == 'copy';

  factory HlsSession.fromJson(Map<String, dynamic> json) {
    return HlsSession(
      sessionId: json['session_id'] as String? ?? '',
      masterUrl: json['master_url'] as String? ?? '',
      totalDuration: (json['duration'] as num? ?? 0).toDouble(),
      startOffset: json['start_offset'] as int? ?? 0,
      audioMap: (json['audio_map'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      burnedSubtitle: (json['burned_subtitle'] as num?)?.toInt() ?? -1,
      videoMode: json['video_mode'] as String? ?? '',
      videoReason: json['video_reason'] as String? ?? '',
      retainSeconds: (json['retain_seconds'] as num?)?.toInt(),
      standby: json['standby'] as bool? ?? false,
      quality: _nonEmpty(json['quality']),
      requestedQuality: _nonEmpty(json['requested_quality']),
      capacityWarning: _nonEmpty(json['capacity_warning']),
      subtitles: (json['subtitles'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(LiveSubtitleSource.fromJson)
          .where((s) => s.typedIndex >= 0 && s.url.isNotEmpty)
          .toList(),
    );
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// Ce que le serveur dit de l'encodeur d'une session HLS (`/health`,
/// ADR-0056) : ce qui distingue, vu du lecteur, une ligne trop lente d'un
/// serveur trop lent.
class HlsSessionHealth {
  const HlsSessionHealth({
    required this.aheadSeconds,
    this.speed = 0,
    this.suggestedQuality,
  });

  /// Ce que l'encodeur a produit au-delà du dernier segment demandé, en
  /// secondes.
  final int aheadSeconds;

  /// Sa vitesse rapportée à celle de la lecture ; 0 tant qu'elle n'est pas
  /// mesurable.
  final double speed;

  /// Le barreau que le serveur conseille d'ouvrir : plus bas quand la
  /// session ne suit plus la lecture, plus haut quand la marge est revenue, ou
  /// le barreau en cours quand une recette plus légère y tient. Une
  /// suggestion : l'Auto décide, un choix manuel n'en fait qu'un message.
  /// Null quand il n'y a rien à suggérer, ou d'un serveur qui ne sait pas le
  /// dire.
  final String? suggestedQuality;

  /// Null quand la réponse ne dit pas l'avance : un serveur d'avant
  /// l'ADR-0056, ou une réponse qui n'est pas la sienne.
  static HlsSessionHealth? tryParse(Object? json) {
    if (json is! Map) return null;
    final ahead = json['ahead_seconds'];
    if (ahead is! num) return null;
    final speed = json['speed'];
    final suggested = json['suggested_quality'];
    return HlsSessionHealth(
      aheadSeconds: ahead.toInt(),
      speed: speed is num ? speed.toDouble() : 0.0,
      suggestedQuality:
          suggested is String && suggested.isNotEmpty ? suggested : null,
    );
  }
}

/// Une piste texte qu'une session HLS écrit en WebVTT, et l'adresse où elle
/// grandit. L'adresse porte déjà le ticket de lecture.
class LiveSubtitleSource {
  const LiveSubtitleSource({required this.typedIndex, required this.url});

  /// La piste dans le conteneur : le N de 0:s:N, qui est aussi
  /// `MediaSubtitleTrack.typedIndex`.
  final int typedIndex;
  final String url;

  factory LiveSubtitleSource.fromJson(Map<String, dynamic> json) =>
      LiveSubtitleSource(
        typedIndex: (json['typed_index'] as num?)?.toInt() ?? -1,
        url: json['url'] as String? ?? '',
      );
}

/// L'adresse de la variante vidéo d'une playlist maîtresse, telle qu'elle y
/// est écrite (relative, ticket compris) : la première ligne qui suit un
/// `#EXT-X-STREAM-INF`. Null si la playlist n'en annonce aucune.
String? firstHlsVariantUri(String master) {
  var expectUri = false;
  for (final raw in master.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      expectUri = true;
    } else if (expectUri && !line.startsWith('#')) {
      return line;
    }
  }
  return null;
}
