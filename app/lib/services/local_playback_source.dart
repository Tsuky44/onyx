import '../models/device_video.dart';
import 'device_library/device_library.dart';
import 'download_manager.dart';

// Ce que le lecteur lit sur disque plutôt que par le serveur. Deux sources, un
// seul endroit qui tranche : une vidéo de l'appareil (identifiant négatif,
// ADR-0104) ou un téléchargement hors ligne. Le lecteur n'a pas à savoir
// laquelle des deux il lit.

/// Le fichier à ouvrir pour ce média, ou null s'il passe par le serveur.
String? localPlaybackPath(int mediaId) => isDeviceVideoId(mediaId)
    ? DeviceLibrary.instance.pathFor(mediaId)
    : DownloadManager.instance.localVideoPath(mediaId);

/// La liste de pistes rapatriée avec un téléchargement. Une vidéo de
/// l'appareil n'en a pas : le moteur garde les pistes par défaut du fichier.
Map<String, dynamic>? localPlaybackTracks(int mediaId) =>
    isDeviceVideoId(mediaId) ? null : DownloadManager.instance.offlineTracks(mediaId);

/// Le WebVTT rapatrié avec un téléchargement, pour [lang].
Future<String?> localPlaybackSubtitle(int mediaId, String lang) async =>
    isDeviceVideoId(mediaId)
        ? null
        : DownloadManager.instance.offlineSubtitle(mediaId, lang);
