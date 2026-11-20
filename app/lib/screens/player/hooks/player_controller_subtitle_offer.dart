part of 'use_player_controller.dart';

/// Ce que le chrome sait des sous-titres avant d'ouvrir leur menu (ADR-0140).
///
/// Sorti de `player_controller_tracks.dart`, qui touchait le plafond de taille
/// (ADR-0052).
extension PlayerControllerSubtitleOffer on PlayerController {
  /// Il y a au moins un sous-titre à choisir, dans la liste que le menu des
  /// sous-titres montrerait : celle du fichier ou celle du serveur (voir
  /// [PlayerControllerTracks.listsEmbeddedSubtitles]). « Désactivés » n'en
  /// est pas un. Sans aucun, le chrome ne pose pas le bouton des sous-titres :
  /// il n'ouvrait qu'un menu « Aucune piste disponible ».
  bool get hasSubtitleTracks => listsEmbeddedSubtitles
      ? session.subtitleTracks.any((t) => t.id != 'auto' && t.id != 'no')
      : (mediaTracks?.subtitles ?? const []).isNotEmpty;
}
