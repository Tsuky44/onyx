import '../../../models/media_tracks.dart';
import '../../../services/playback_capabilities.dart';
import 'auto_source.dart';

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
///
/// La décision est celle de [chooseAutoSource], sur l'image seule et face à
/// un serveur dont on ne sait rien : ce garde répond avant que la liste des
/// pistes ait tout dit, et ne tranche que « ouvrir le fichier ou non ». Le
/// barreau réellement demandé se décide ensuite, avec le serveur.
String? serverQualityForUndecodableVideo(
  PlaybackCapabilities capabilities,
  MediaVideoTrack? video,
) {
  if (capabilities.directPlayVideo == null || video == null) return null;
  final source = chooseAutoSource(
    AutoSourceFile(video: video),
    AutoSourceDevice(capabilities: capabilities),
    const AutoLine.unmeasured(),
    AutoSourceServer.legacy,
  );
  return source.blocked == DirectPlayBlock.video ? source.quality : null;
}
