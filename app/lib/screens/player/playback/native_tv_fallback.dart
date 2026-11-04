import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../../../models/models.dart';
import 'playback_session.dart';

/// Pourquoi une lecture garde l'interface Flutter sur un appareil éligible au
/// lecteur natif d'Apple TV.
enum NativeTvFallback {
  /// Le natif a refusé de se présenter (pas de contrôleur racine, lecteur
  /// inconnu, plateforme sans écran natif).
  presentationFailed,

  /// La route logicielle d'AetherEngine : pas d'`AVPlayer` à présenter, AVKit
  /// n'afficherait qu'une roue sur fond noir, son joué (spike, correction 1).
  softwareRoute,

  /// Des sous-titres image (PGS, VobSub, DVB) en Direct Play : le moteur les
  /// exclut du groupe `legible`, seule la couche Flutter sait les peindre.
  bitmapSubtitles,

  /// Des sous-titres texte pendant une session HLS : la session les écrit à
  /// part et c'est Flutter qui les peint (ADR-0031). Ils ne sont pas dans le
  /// flux qu'AVPlayer lit, donc pas dans son menu.
  overlaySubtitles,
}

/// Le sous-titre que l'utilisateur a choisi, ou que la mémoire des pistes a
/// repris, vu sous l'angle de qui sait le peindre.
enum NativeTvSubtitleKind { none, text, image }

/// La règle de repli, en entier. Relue à chaque construction de l'écran du
/// lecteur : un repli qui apparaît en cours de lecture (route logicielle, piste
/// image choisie) rend l'écran Flutter sans couper la lecture, et un repli qui
/// disparaît (piste texte reprise) rend l'écran natif.
///
/// [refusal] est la raison du dernier `unavailable` du natif : un refus est
/// définitif pour ce lecteur. [streaming] vaut pour une session HLS du
/// serveur, où une piste image est déjà incrustée dans l'image.
NativeTvFallback? nativeTvFallbackFor({
  OnyxAppleNativeReason? refusal,
  bool softwareRoute = false,
  NativeTvSubtitleKind subtitle = NativeTvSubtitleKind.none,
  bool streaming = false,
}) {
  switch (refusal) {
    case OnyxAppleNativeReason.softwareRoute:
      return NativeTvFallback.softwareRoute;
    case OnyxAppleNativeReason.presentationFailed ||
          OnyxAppleNativeReason.unsupported:
      return NativeTvFallback.presentationFailed;
    case OnyxAppleNativeReason.userDismissed ||
          OnyxAppleNativeReason.requested ||
          null:
      break;
  }
  if (softwareRoute) return NativeTvFallback.softwareRoute;
  return switch (subtitle) {
    NativeTvSubtitleKind.image when !streaming =>
      NativeTvFallback.bitmapSubtitles,
    NativeTvSubtitleKind.text when streaming =>
      NativeTvFallback.overlaySubtitles,
    _ => null,
  };
}

/// Le genre du sous-titre retenu. [engineShowsBitmap] : la piste active du
/// moteur est une image, ce qui couvre un choix fait dans sa propre liste (le
/// menu Onyx en Direct Play). Sinon, la clé du serveur ([selectedLang]) dit ce
/// qu'est la piste ; une clé qu'il ne liste pas est traitée en texte.
NativeTvSubtitleKind nativeTvSubtitleKind({
  required String? selectedLang,
  required List<MediaSubtitleTrack>? serverTracks,
  bool engineShowsBitmap = false,
}) {
  if (engineShowsBitmap) return NativeTvSubtitleKind.image;
  if (selectedLang == null || selectedLang.isEmpty) {
    return NativeTvSubtitleKind.none;
  }
  final track = serverTracks?.where((t) => t.lang == selectedLang).firstOrNull;
  return (track?.image ?? false)
      ? NativeTvSubtitleKind.image
      : NativeTvSubtitleKind.text;
}

/// Ce que le natif prépare au chargement quand l'écran natif peut servir : les
/// pistes texte du fichier rejoignent le menu Sous-titres d'AVKit. Rien de
/// plus en Direct Play, où le moteur lit ces pistes dans le fichier lui-même.
OnyxAppleLoadSubtitles nativeTvLoadSubtitles({
  List<OnyxAppleExternalSubtitle> external = const [],
}) =>
    OnyxAppleLoadSubtitles(prepareNative: true, external: external);

/// La piste à rendre au contrôleur pour un choix du menu AVKit : [trackId]
/// est déjà dans la numérotation du lecteur, nul pour « aucun ». Null quand la
/// piste n'est plus listée (un rechargement est passé entre-temps).
PlaybackTrack? nativeTvSubtitleChoice(
  String? trackId,
  List<PlaybackTrack> tracks,
) {
  if (trackId == null) return const PlaybackTrack(id: 'no');
  return tracks.where((track) => track.id == trackId).firstOrNull;
}
