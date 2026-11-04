import 'package:onyx_player_apple/onyx_player_apple.dart';

/// L'`AVPlayerViewController` d'Apple TV, présenté par-dessus Flutter sur le
/// lecteur d'une session déjà ouverte.
///
/// Une interface et non le lecteur Pigeon lui-même : [NativeTvPresenter] se
/// teste sans canal de plateforme, et le lecteur ne voit du moteur que ces
/// quatre gestes.
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

  /// Les événements de *ce* lecteur seulement : le flux natif est commun à
  /// tous, et deux lecteurs vivent ensemble au passage d'un épisode.
  Stream<OnyxAppleNativeEvent> get events;
}
