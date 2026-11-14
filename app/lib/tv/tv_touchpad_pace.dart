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

/// Une étape du pavé de la Siri Remote : un glissé vertical n'en franchit
/// qu'une (ADR-0128).
///
/// Sur une fiche, chaque section (l'en-tête, les saisons, la distribution)
/// est une étape. D'un seul glissé, « Lecture » menait à la distribution puis
/// plus bas encore, et la page traversait deux écrans. Le pas qui change
/// d'étape est le dernier de son geste ; dans une même étape, seules des
/// cartes se suivent en continu (une liste d'épisodes), les commandes vont
/// cran par cran. Voir `TvTouchpad`.
///
/// Sans effet hors Apple TV, et sur les flèches du pavé directionnel : une
/// flèche vaut toujours un pas.
class TvTouchpadStop extends InheritedWidget {
  const TvTouchpadStop({
    super.key,
    required this.zone,
    required super.child,
  });

  /// Ce qui distingue cette étape des autres : deux cibles sont dans la même
  /// étape quand leurs zones sont le même objet.
  final Object zone;

  /// L'étape au-dessus de [context], ou nul hors de toute étape. Lue au
  /// moment d'un geste : aucune dépendance n'est inscrite.
  static Object? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvTouchpadStop>()?.zone;

  @override
  bool updateShouldNotify(TvTouchpadStop oldWidget) =>
      !identical(oldWidget.zone, zone);
}
