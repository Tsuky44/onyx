import 'package:onyx_player_apple/onyx_player_apple.dart';

/// L'`AVPlayerViewController` d'Apple TV, présenté par-dessus Flutter sur le
/// lecteur d'une session déjà ouverte.
///
/// Une interface et non le lecteur Pigeon lui-même : [NativeTvPresenter] se
/// teste sans canal de plateforme, et le lecteur ne voit du moteur que ces
/// gestes.
abstract interface class NativeTvScreen {
  /// Présente l'écran natif. Un refus arrive par [events] (`unavailable`),
  /// jamais par une erreur.
  Future<void> present(OnyxAppleNativeSpec spec);

  /// Remplace ce qu'il affiche : menus cochés, actions, titre.
  Future<void> update(OnyxAppleNativeSpec spec);

  /// Le ferme. Il répond `dismissed` avec la raison `requested`.
  Future<void> dismiss();

  /// Le cadrage de l'image, que le natif applique à sa propre couche.
  Future<void> setFit(OnyxAppleVideoFit fit);

  /// Les sous-titres à déclarer au chargement, pour les ouvertures qui
  /// suivent : AVKit ne montre que ceux-là. Appelé avant la première.
  Future<void> prepareSubtitles(OnyxAppleLoadSubtitles subtitles);

  /// Le moteur sert la lecture par la route logicielle : il n'y a pas
  /// d'`AVPlayer` à présenter.
  bool get softwareRoute;

  /// La piste de sous-titres active du moteur est une image (PGS, VobSub,
  /// DVB), qu'AVKit ne montre pas : le natif la peint dans sa propre couche.
  bool get showsBitmapSubtitle;

  /// Les événements de *ce* lecteur seulement : le flux natif est commun à
  /// tous, et deux lecteurs vivent ensemble au passage d'un épisode. Le
  /// `trackId` d'un `subtitleSelected` y est déjà un `PlaybackTrack.id`.
  Stream<OnyxAppleNativeEvent> get events;
}
