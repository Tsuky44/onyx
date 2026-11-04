import 'package:path/path.dart' as p;

import 'media.dart';

/// Les extensions que la bibliothèque de l'appareil reconnaît comme vidéo.
///
/// Celles que mpv, ExoPlayer et AetherEngine ouvrent tous les trois. Un
/// fichier hors de cette liste n'apparaît pas : mieux vaut un film absent
/// qu'une tuile qui échoue à l'ouverture.
const Set<String> kDeviceVideoExtensions = {
  '.mkv', '.mp4', '.m4v', '.mov', '.avi', '.webm', '.ts', '.m2ts', '.mts',
  '.wmv', '.flv', '.mpg', '.mpeg', '.3gp', '.ogv',
};

bool isDeviceVideoPath(String path) {
  final name = p.basename(path);
  // Les fichiers cachés et les ressources macOS (`._film.mkv`) ne sont pas
  // des films.
  if (name.startsWith('.')) return false;
  return kDeviceVideoExtensions.contains(p.extension(name).toLowerCase());
}

/// Les identifiants des vidéos de l'appareil sont négatifs.
///
/// Le lecteur, ses rangées et le reporter désignent un média par un entier :
/// une vidéo locale en a donc un, dérivé de son chemin pour rester le même
/// d'un scan à l'autre. Négatif, il ne croise jamais un identifiant de
/// serveur, que SQLite attribue à partir de 1. Voir ADR-0104.
bool isDeviceVideoId(int id) => id < 0;

/// FNV-1a sur 31 bits du chemin normalisé, puis négatif. Stable entre deux
/// lancements, contrairement à `String.hashCode`.
int deviceVideoIdFor(String path) {
  final key = p.normalize(path);
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return -(hash + 1);
}

/// Le titre lisible d'un nom de fichier : sans extension, sans points ni
/// tirets bas de séparation, sans les étiquettes de release entre crochets.
///
/// `Mon.Film.2019.1080p.mkv` → `Mon Film 2019 1080p`. On ne va pas plus loin :
/// deviner un titre « propre » est le travail de l'indexeur du serveur, et
/// une vidéo de vacances n'a pas de titre à retrouver.
String deviceVideoTitle(String path) {
  var name = p.basenameWithoutExtension(path);
  name = name.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  name = name.replaceAll(RegExp(r'[._]+'), ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isEmpty ? p.basename(path) : name;
}

/// Où en est la lecture d'une vidéo de l'appareil. Rien ne part au serveur :
/// ces vidéos lui sont inconnues.
class DeviceVideoProgress {
  final int positionSeconds;
  final int durationSeconds;
  final bool isFinished;
  final DateTime updatedAt;

  const DeviceVideoProgress({
    required this.positionSeconds,
    required this.durationSeconds,
    required this.isFinished,
    required this.updatedAt,
  });

  double get fraction => durationSeconds <= 0
      ? 0
      : (positionSeconds / durationSeconds).clamp(0.0, 1.0);

  factory DeviceVideoProgress.fromJson(Map<String, dynamic> json) =>
      DeviceVideoProgress(
        positionSeconds: (json['position'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
        isFinished: json['finished'] as bool? ?? false,
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'position': positionSeconds,
        'duration': durationSeconds,
        'finished': isFinished,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}

/// Un fichier vidéo trouvé dans un dossier suivi de l'appareil.
class DeviceVideo {
  final String path;

  /// Le dossier suivi qui l'a fait trouver, pour grouper l'écran.
  final String folder;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DeviceVideoProgress? progress;

  const DeviceVideo({
    required this.path,
    required this.folder,
    required this.sizeBytes,
    required this.modifiedAt,
    this.progress,
  });

  int get id => deviceVideoIdFor(path);
  String get title => deviceVideoTitle(path);

  /// Le sous-dossier où il se trouve, relatif au dossier suivi ; vide à la
  /// racine.
  String get subfolder {
    final dir = p.dirname(path);
    if (p.equals(dir, folder)) return '';
    return p.relative(dir, from: folder);
  }

  DeviceVideo withProgress(DeviceVideoProgress? next) => DeviceVideo(
        path: path,
        folder: folder,
        sizeBytes: sizeBytes,
        modifiedAt: modifiedAt,
        progress: next,
      );

  /// Ce que le lecteur reçoit. Un film, toujours : un épisode lancerait la
  /// navigation entre épisodes, qui interroge le serveur.
  HomeMediaItem toHomeMediaItem() {
    final position = progress?.positionSeconds ?? 0;
    final duration = progress?.durationSeconds ?? 0;
    return HomeMediaItem(
      media: Media(
        id: id,
        type: MediaType.movie,
        title: title,
        filePath: path,
        duration: duration,
        createdAt: modifiedAt,
      ),
      currentPositionSeconds: position,
      duration: duration,
      isFinished: progress?.isFinished ?? false,
      updatedAt: progress?.updatedAt,
    );
  }
}
