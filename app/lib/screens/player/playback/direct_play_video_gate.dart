import '../../../models/media_tracks.dart';
import '../../../services/playback_capabilities.dart';
import '../web_quality.dart';

/// La qualité à demander au serveur quand la puce ne décode pas l'image de ce
/// fichier en matériel, ou null quand le fichier s'ouvre tel quel.
///
/// Le cas visé est l'Apple TV HD : AetherEngine y lit le HEVC, mais en
/// logiciel, et l'image saccade. Le serveur, lui, le rend en H.264 que la
/// puce décode. Décidé ici avant toute ouverture, pour ne pas ouvrir le
/// fichier, le voir saccader puis le quitter.
///
/// Jamais au-dessus de ce que la puce affiche : un 4K demandé en 2160p
/// reviendrait à lui faire décoder ce qu'elle ne tient pas non plus.
String? serverQualityForUndecodableVideo(
  PlaybackCapabilities capabilities,
  MediaVideoTrack? video,
) {
  final limits = capabilities.directPlayVideo;
  if (limits == null || video == null) return null;
  if (capabilities.playsVideoDirectly(
    codec: video.codec,
    height: video.height,
    bitDepth: video.bitDepth,
  )) {
    return null;
  }
  final height =
      video.height > limits.maxHeight ? limits.maxHeight : video.height;
  return qualityForSourceHeight(height);
}
