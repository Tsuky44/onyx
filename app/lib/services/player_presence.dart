import 'package:flutter/foundation.dart';

/// Dit si un lecteur est ouvert, où qu'il ait été lancé.
///
/// [PlayerScreen] s'ouvre depuis six endroits (accueil, fiches, téléchargements,
/// watch party, reprise à distance…) : c'est lui qui s'annonce, plutôt que
/// chacun de ses appelants. Un compteur et pas un booléen, parce qu'un
/// lecteur peut en remplacer un autre (épisode suivant) et que le nouveau
/// arrive avant que l'ancien ne soit démonté.
abstract final class PlayerPresence {
  static int _open = 0;
  static final ValueNotifier<bool> _isOpen = ValueNotifier<bool>(false);

  static bool isOpen() => _open > 0;

  /// Pour ce qui doit réagir à l'ouverture ou à la fermeture d'un lecteur
  /// (voir `BackgroundMotionGate`). Elle se notifie depuis `initState` et
  /// `dispose` : l'écouteur ne doit pas reconstruire sur-le-champ.
  static ValueListenable<bool> get open => _isOpen;

  static void enter() {
    _open++;
    _isOpen.value = true;
  }

  static void leave() {
    if (_open > 0) _open--;
    _isOpen.value = _open > 0;
  }
}
