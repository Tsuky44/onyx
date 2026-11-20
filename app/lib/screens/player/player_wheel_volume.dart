import 'package:flutter/gestures.dart';

/// Le pas d'un cran de molette, le même que celui des flèches ↑ ↓ (voir
/// `_volumeStep` dans `player_key_routing.dart`) : les deux gestes donnent le
/// même volume pour le même effort.
const double playerWheelVolumeStep = 5.0;

/// Ce que [event] demande au volume, ou null s'il ne le concerne pas.
///
/// Seule la molette d'une souris compte. Le pavé tactile envoie lui aussi des
/// défilements, mais c'est un geste de défilement, pas de volume : le détourner
/// ferait bouger le son à chaque effleurement. Le sens suit la molette : vers
/// le bas (`dy > 0`) baisse, vers le haut monte. Le pas est fixe, quelle que
/// soit la valeur du défilement, que Flutter ne normalise pas d'un système à
/// l'autre.
double? playerWheelVolumeDelta(PointerSignalEvent event) {
  if (event is! PointerScrollEvent) return null;
  if (event.kind != PointerDeviceKind.mouse) return null;
  final dy = event.scrollDelta.dy;
  if (dy == 0) return null;
  return dy > 0 ? -playerWheelVolumeStep : playerWheelVolumeStep;
}
