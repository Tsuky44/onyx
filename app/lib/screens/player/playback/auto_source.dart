/// La règle de l'Auto : ce que le lecteur ouvre quand personne n'a choisi.
///
/// Une seule décision, ici, là où cinq endroits du lecteur choisissaient
/// chacun leur barreau de leur côté (le garde de l'Apple TV HD, l'audio muet,
/// le Dolby Vision, le repli d'une panne, le rattrapage d'une lecture figée).
/// Chacun appelait `qualityForSourceHeight` et ignorait la ligne et le
/// serveur ; ils passent maintenant tous par [chooseAutoSource]. Voir
/// l'ADR « l'Auto choisit Direct Play, recopie, puis transcodage »
/// (2026-11-25), qui prolonge les ADR-0056 et 0065 et l'ADR Apple TV de
/// fytroz, et le §4 de `docs/transcodage-adaptatif.md`.
///
/// L'ordre, le premier possible gagnant :
///  1. **Direct Play** : l'appareil décode tout (image, son, Dolby Vision) et
///     la ligne porte le fichier. Une ligne pas encore mesurée ne l'interdit
///     pas (ADR-0065).
///  2. **Recopie** : l'image passe telle quelle dans une session du serveur,
///     avec `remux=1` pour lever le plafond de recopie : le spectateur aurait
///     tiré ce débit en Direct Play de toute façon.
///  3. **Transcodage au plus haut** : la ligne borne le débit (80 %, ADR-0056),
///     le serveur borne la résolution (`fit` = `ok`), parce que le coût d'un
///     encodage suit les pixels et presque pas le débit. Le HDR est gardé en
///     HEVC quand l'appareil l'affiche.
///  4. **Rien ne passe** : le barreau le plus bas, en disant ce qui limite.
///
/// Fonction pure : aucun moteur, aucun serveur. Un serveur plus ancien, sans
/// `fit` ni `transcode_capacity`, rend exactement les choix d'avant.
library;

import '../../../models/media_tracks.dart';
import '../../../services/playback_capabilities.dart';
import 'auto_quality.dart';

/// Ce que l'Auto ouvre.
enum AutoSourceKind {
  /// Le fichier lui-même, lu par le moteur de l'appareil.
  directPlay,

  /// Une session du serveur qui recopie l'image.
  copy,

  /// Une session du serveur qui encode l'image.
  transcode,
}

/// Pourquoi le fichier ne se lit pas tel quel.
enum DirectPlayBlock {
  none,

  /// Le moteur n'ouvre pas de fichier (navigateur), ou le Direct Play a déjà
  /// échoué sur ce fichier.
  engine,

  /// La puce ne décode pas cette image en matériel (Apple TV HD et HEVC).
  video,

  /// La piste audio choisie serait muette.
  audio,

  /// Un Dolby Vision profil 5 sortirait rose et vert (ADR-0060).
  dolbyVision,

  /// La ligne mesurée ne porte pas le fichier.
  line,
}

/// Ce qui a mis l'Auto au plus bas, quand rien ne passe.
enum AutoLimit { none, line, server }

/// Le fichier : ses pistes et l'échelle que le serveur en propose.
class AutoSourceFile {
  const AutoSourceFile({
    this.video,
    this.audio,
    this.sourceBps = 0,
    this.tiers = const [],
  });

  /// [audioIndex] : la piste audio qui sera lue.
  factory AutoSourceFile.of(MediaTracks? tracks, {int audioIndex = 0}) {
    final audio = tracks?.audio ?? const <MediaAudioTrack>[];
    return AutoSourceFile(
      video: tracks?.video,
      audio: audioIndex >= 0 && audioIndex < audio.length
          ? audio[audioIndex]
          : null,
      sourceBps: tracks?.sourceBitrateBps ?? 0,
      tiers: tracks?.qualities ?? const [],
    );
  }

  final MediaVideoTrack? video;
  final MediaAudioTrack? audio;

  /// Le débit du fichier, 0 quand le serveur ne le dit pas.
  final int sourceBps;

  /// L'échelle de `/tracks`, vide d'un serveur d'avant l'ADR-0022.
  final List<QualityTier> tiers;
}

/// L'appareil : ce que sa puce décode, et s'il ouvre des fichiers.
class AutoSourceDevice {
  const AutoSourceDevice({
    required this.capabilities,
    this.opensFiles = true,
    this.screenHeight = 0,
  });

  final PlaybackCapabilities capabilities;

  /// Faux dans un navigateur, et quand le Direct Play de ce fichier a déjà
  /// échoué (panne au démarrage, lecture figée).
  final bool opensFiles;

  /// La hauteur, en pixels réels, de la surface où l'image est peinte. 0 :
  /// inconnue, aucun plafond. Seul le navigateur la donne aujourd'hui : sur un
  /// téléviseur Android, la vue Flutter fait souvent 1080 lignes devant une
  /// dalle 4K, et la prendre pour l'écran ramènerait tout en 1080p.
  final int screenHeight;
}

/// La ligne, telle que l'Auto l'a mesurée. Jamais supposée (ADR-0056).
class AutoLine {
  const AutoLine.unmeasured() : bps = null;
  const AutoLine.measured(int this.bps);

  final int? bps;

  /// Si la ligne porte [demandBps] avec la marge de l'ADR-0056. Une ligne
  /// pas encore mesurée, ou un débit inconnu, ne refuse rien.
  bool carries(int demandBps) {
    final line = bps;
    if (line == null || demandBps <= 0) return true;
    return line * AutoQuality.headroom >= demandBps;
  }
}

/// Le serveur : ce qu'il comprend, et ce qu'il dit tenir.
class AutoSourceServer {
  const AutoSourceServer({
    this.transcodeCapacity = false,
    this.heightBound = 0,
  });

  /// Un serveur d'avant le budget : ni `auto=1`, ni `remux=1`, ni
  /// `encode=hevc` envoyés, comme aujourd'hui.
  static const legacy = AutoSourceServer();

  /// `/api/ping` annonce `transcode_capacity` : le serveur comprend `auto=1`,
  /// et c'est lui qui a appris à juger une recopie et un HEVC.
  final bool transcodeCapacity;

  /// La plus grande image que le serveur dit tenir en ce moment
  /// (`suggested_quality` de `/health`), plus récente que le `fit` des
  /// pistes. 0 : s'en tenir à `fit`.
  final int heightBound;
}

/// La décision.
class AutoSource {
  const AutoSource._({
    required this.kind,
    required this.blocked,
    this.quality,
    this.ceiling,
    this.keepHdr = false,
    this.remux = false,
    this.limitedBy = AutoLimit.none,
  });

  final AutoSourceKind kind;

  /// Pourquoi pas le Direct Play ; [DirectPlayBlock.none] quand c'est lui.
  final DirectPlayBlock blocked;

  /// Le barreau à demander, null en Direct Play.
  final String? quality;

  /// Le plus haut barreau que l'appareil et le fichier permettent, sans la
  /// ligne ni le serveur : le sommet de l'Auto quand le Direct Play est
  /// exclu. Null en Direct Play.
  final String? ceiling;

  /// `encode=hevc` : le HDR est gardé (ADR-0106).
  final bool keepHdr;

  /// `remux=1` : la recopie n'a pas de plafond de débit.
  final bool remux;

  /// Ce qui a mis l'Auto au plus bas ; [AutoLimit.none] sinon.
  final AutoLimit limitedBy;

  bool get isDirectPlay => kind == AutoSourceKind.directPlay;

  @override
  String toString() => switch (kind) {
        AutoSourceKind.directPlay => 'direct',
        AutoSourceKind.copy => 'recopie $quality${remux ? ' (remux)' : ''}',
        AutoSourceKind.transcode => 'transcodage $quality'
            '${keepHdr ? ' HEVC HDR' : ''}'
            '${limitedBy == AutoLimit.none ? '' : ' (au plus bas : ${limitedBy.name})'}',
      };
}

/// La décision de l'Auto. Voir la tête de ce fichier.
AutoSource chooseAutoSource(
  AutoSourceFile file,
  AutoSourceDevice device,
  AutoLine line,
  AutoSourceServer server,
) {
  final blocked = _directPlayBlock(file, device, line);
  if (blocked == DirectPlayBlock.none) {
    return const AutoSource._(
        kind: AutoSourceKind.directPlay, blocked: DirectPlayBlock.none);
  }

  final video = file.video;
  if (video != null && _copyable(video, device.capabilities) &&
      line.carries(file.sourceBps)) {
    final native = nativeTierKey(video.height);
    return AutoSource._(
      kind: AutoSourceKind.copy,
      blocked: blocked,
      quality: native,
      ceiling: native,
      remux: server.transcodeCapacity,
    );
  }

  return _transcode(file, device, line, server, blocked);
}

DirectPlayBlock _directPlayBlock(
    AutoSourceFile file, AutoSourceDevice device, AutoLine line) {
  if (!device.opensFiles) return DirectPlayBlock.engine;
  final caps = device.capabilities;
  final video = file.video;
  if (video != null &&
      !caps.playsVideoDirectly(
          codec: video.codec, height: video.height, bitDepth: video.bitDepth)) {
    return DirectPlayBlock.video;
  }
  final audio = file.audio;
  if (audio != null && !caps.decodesInDirectPlay(audio.codec)) {
    return DirectPlayBlock.audio;
  }
  if ((video?.needsDolbyVision ?? false) && !caps.dolbyVisionInDirectPlay) {
    return DirectPlayBlock.dolbyVision;
  }
  if (!line.carries(file.sourceBps)) return DirectPlayBlock.line;
  return DirectPlayBlock.none;
}

/// Si le serveur peut recopier cette image pour cet appareil : le reflet,
/// côté client, de `PlanVideo` (`server/streaming/plan.go`) pour ce que les
/// pistes disent. Le plafond de débit n'y est pas : `remux=1` le lève, et un
/// serveur plus ancien encode alors au même barreau, ce qu'on lui demandait
/// déjà.
bool _copyable(MediaVideoTrack video, PlaybackCapabilities caps) {
  final codec = _canonicalVideo(video.codec);
  if (codec == null || !caps.videoCodecs.contains(codec)) return false;
  if (caps.container == 'ts' && codec != 'h264' && codec != 'hevc') {
    return false;
  }
  if (video.bitDepth > caps.maxVideoBitDepth) return false;
  final pix = video.pixFmt.toLowerCase();
  if (pix.contains('422') || pix.contains('444')) return false;
  if (video.isHDR && !caps.hdr) return false;
  if (video.needsDolbyVision && !caps.dolbyVision) return false;
  // Ce que la puce décode en matériel vaut aussi pour une session : la puce
  // A8 de l'Apple TV HD ne décode pas un H.264 4K, recopié ou non.
  final limit = caps.directPlayVideo?.maxHeight ?? 0;
  if (limit > 0 && video.height > limit) return false;
  return true;
}

String? _canonicalVideo(String codec) => switch (codec.trim().toLowerCase()) {
      'h264' || 'avc' || 'avc1' => 'h264',
      'hevc' || 'h265' || 'hvc1' || 'hev1' => 'hevc',
      'av1' => 'av1',
      'vp9' => 'vp9',
      _ => null,
    };

AutoSource _transcode(AutoSourceFile file, AutoSourceDevice device,
    AutoLine line, AutoSourceServer server, DirectPlayBlock blocked) {
  final video = file.video;
  final caps = device.capabilities;
  final hasFit = file.tiers.any((t) => t.fit != null);

  // Les plafonds de l'appareil et du fichier, sans la ligne ni le serveur.
  final height = video?.height ?? 0;
  // Sans hauteur, le palier 1080p que tous les serveurs offrent : se tromper
  // de palier laisse une lecture, deviner plus haut coûterait un 4K.
  var top = height > 0 ? _nativeHeight(height) : 1080;
  final decoder = caps.directPlayVideo?.maxHeight ?? 0;
  if (decoder > 0 && decoder < top) top = decoder;
  if (device.screenHeight > 0) {
    final surface = _tierHeightForSurface(device.screenHeight);
    if (surface < top) top = surface;
  }
  // Un serveur qui ne dit pas ce qu'il tient : le tone mapping de la couche
  // RPU au plus en 1080p, comme avant (un serveur sans GPU ne le tient pas en
  // 4K). Avec `fit`, c'est le serveur qui le dit, pour sa propre machine.
  if ((video?.needsDolbyVision ?? false) && !hasFit && top > 1080) top = 1080;

  final keepHdr = server.transcodeCapacity &&
      video != null &&
      video.isHDR &&
      !video.needsDolbyVision &&
      caps.hdr &&
      caps.videoCodecs.contains('hevc') &&
      caps.maxVideoBitDepth >= 10;

  final candidates =
      file.tiers.where((t) => t.bitrateBps > 0 && t.height <= top).toList();
  final ceiling = _baseKeyAtOrBelow(top);
  if (candidates.isEmpty) {
    // Un serveur d'avant l'échelle de débits : le palier de la hauteur.
    return AutoSource._(
      kind: AutoSourceKind.transcode,
      blocked: blocked,
      quality: ceiling,
      ceiling: ceiling,
      keepHdr: keepHdr,
    );
  }

  bool serverHolds(QualityTier t) {
    if (server.heightBound > 0) return t.height <= server.heightBound;
    return !hasFit || t.fit == QualityTier.fitOk;
  }

  bool lineCarries(QualityTier t) => line.carries(t.bitrateBps);

  final heights = candidates.map((t) => t.height).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  for (final h in heights) {
    final options = candidates
        .where((t) => t.height == h && serverHolds(t) && lineCarries(t))
        .toList()
      ..sort((a, b) => b.bitrateBps.compareTo(a.bitrateBps));
    if (options.isEmpty) continue;
    // Ligne pas mesurée : rien ne justifie le plus gros débit de la
    // résolution. Le palier de la hauteur, celui qu'on demandait avant.
    final base = nativeTierKey(h);
    final pick = line.bps == null && options.any((t) => t.key == base)
        ? base
        : options.first.key;
    return AutoSource._(
      kind: AutoSourceKind.transcode,
      blocked: blocked,
      quality: pick,
      ceiling: ceiling,
      keepHdr: keepHdr,
    );
  }

  // Rien ne passe : le barreau qui demande le moins, et ce qui l'impose.
  final lowest = candidates.reduce((a, b) {
    if (a.bitrateBps != b.bitrateBps) {
      return a.bitrateBps < b.bitrateBps ? a : b;
    }
    return a.height <= b.height ? a : b;
  });
  return AutoSource._(
    kind: AutoSourceKind.transcode,
    blocked: blocked,
    quality: lowest.key,
    ceiling: ceiling,
    keepHdr: keepHdr,
    limitedBy:
        candidates.any(lineCarries) ? AutoLimit.server : AutoLimit.line,
  );
}

/// Le barreau d'origine d'une source haute de [height] lignes : celui que le
/// serveur recopie quand il le peut (ADR-0056 §3), et le palier de chaque
/// hauteur.
///
/// Les seuils sont sous chaque hauteur nominale : un film en 2,39:1 rangé sans
/// bandes fait 1920×804, et un master recadré quelques dizaines de lignes de
/// moins. Ce sont les mêmes que `nativeTierHeight` côté serveur
/// (`server/streaming/quality.go`) : un palier que le serveur ne proposerait
/// pas laisserait le menu en désaccord avec ce qui joue.
///
/// Seul [chooseAutoSource] choisit une source avec ; `AutoLadder` s'en sert
/// pour reconnaître le barreau qui recopie. Gardé par
/// `test/auto_source_guard_test.dart`.
String nativeTierKey(int height) => '${_nativeHeight(height)}p';

int _nativeHeight(int height) {
  if (height <= 0) return 1080;
  if (height > 1400) return 2160;
  if (height > 800) return 1080;
  if (height > 560) return 720;
  if (height > 400) return 480;
  return 360;
}

const _tierHeights = <int>[2160, 1080, 720, 480, 360];

/// Le palier de la plus grande hauteur d'échelle qui ne dépasse pas [top].
String _baseKeyAtOrBelow(int top) {
  for (final h in _tierHeights) {
    if (h <= top) return '${h}p';
  }
  return '360p';
}

/// La plus petite hauteur d'échelle qui remplit une surface de [height]
/// pixels réels. Comparée à la surface et non à la source : une fenêtre fait
/// exactement sa hauteur, sans bandes à tolérer. Un film en scope dans une
/// fenêtre de 1080 lignes n'en peint que 800, et demander 1080p coûte peu et
/// survit à un redimensionnement.
int _tierHeightForSurface(int height) {
  if (height <= 360) return 360;
  if (height <= 480) return 480;
  if (height <= 720) return 720;
  if (height <= 1080) return 1080;
  return 2160;
}

/// La plus grande image que le serveur dit tenir d'après `fit` : la hauteur
/// du plus haut barreau `ok`. 0 quand l'échelle ne dit rien (serveur plus
/// ancien, profil pas prêt) ou que rien n'est `ok`.
int fitHeightBound(List<QualityTier> tiers) {
  var best = 0;
  for (final tier in tiers) {
    if (tier.fit == QualityTier.fitOk && tier.height > best) best = tier.height;
  }
  return best;
}
