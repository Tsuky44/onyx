import 'package:flutter/widgets.dart';

import 'touchpad_motion.dart';

export 'touchpad_motion.dart' show TouchpadPace;

/// Déclare le rythme du pavé de la Siri Remote pour tout ce que [child]
/// contient (ADR-0122).
///
/// Le pavé devine seul l'essentiel : une cible basse (onglet, bouton, ligne
/// de menu) est une commande, qu'il parcourt posément ; une cible haute est
/// une carte, qu'il traverse vite (`TvTouchpad.paceOf`). Une zone se déclare
/// quand sa taille ment : les lignes des réglages portent un titre, un texte
/// et parfois un choix, et montent jusqu'à 170 px, plus qu'une vignette
/// d'épisode. Ce sont pourtant des commandes.
///
/// Sans effet hors Apple TV : rien d'autre ne lit le pavé.
class TvTouchpadPace extends InheritedWidget {
  const TvTouchpadPace({
    super.key,
    required this.pace,
    required super.child,
  });

  /// Une zone de commandes : réglages, formulaire, liste de choix.
  const TvTouchpadPace.precise({super.key, required super.child})
      : pace = TouchpadPace.precise;

  final TouchpadPace pace;

  /// Le rythme déclaré au-dessus de [context], ou nul quand rien ne l'est.
  /// Lu hors de la construction, au moment d'un geste : aucune dépendance
  /// n'est inscrite.
  static TouchpadPace? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvTouchpadPace>()?.pace;

  @override
  bool updateShouldNotify(TvTouchpadPace oldWidget) => oldWidget.pace != pace;
}
