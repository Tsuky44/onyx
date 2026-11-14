import 'package:flutter/widgets.dart';

import 'tv_mode.dart';

/// Une page de téléviseur qui tient elle-même son parcours vertical et son
/// défilement (les fiches, `TvSections`, ADR-0128).
///
/// Le parcours ordinaire cherche sa cible dans tout l'écran, et chaque sorte
/// de cible se ramène à l'écran à sa façon : une pastille se collait en bas,
/// une bulle de saison se centrait, et une fiche montait puis redescendait
/// d'un pas à l'autre. Une page qui se déclare ici reçoit Haut et Bas par
/// [step] et chaque cible focalisée par [reveal], et décide seule.
///
/// Ce contrat vit sous `lib/tv/` et non avec `TvSections` : l'ancien
/// `TvFocusable`, `TvFocusScroll` et `TvDpadFocusable` le consultent sans
/// connaître ce qui le tient.
abstract interface class TvPage {
  /// Où Haut ou Bas mène depuis [from], sans y aller. Nul au bout de la
  /// page.
  FocusNode? targetFor(FocusNode from, TraversalDirection direction);

  /// Fait le pas de Haut ou Bas depuis [from], et dit si le focus part.
  /// Faux au bout de la page.
  bool step(FocusNode from, TraversalDirection direction);

  /// Pose la page pour [node], qui vient de prendre le focus. [alignment] est
  /// la place que la cible demande dans une rangée horizontale, s'il y en a
  /// une ; la page garde la sienne à la verticale.
  void reveal(FocusNode node, {double? alignment});
}

/// Publie la [TvPage] d'une page à tout ce qu'elle contient.
class TvPageScope extends InheritedWidget {
  const TvPageScope({
    super.key,
    required this.page,
    required super.child,
  });

  final TvPage page;

  /// La page au-dessus de [context], sur un téléviseur seulement. Lue au
  /// moment d'un pas, hors de la construction : aucune dépendance inscrite.
  static TvPage? maybeOf(BuildContext context) {
    if (!TvMode.isTv) return null;
    return context.getInheritedWidgetOfExactType<TvPageScope>()?.page;
  }

  @override
  bool updateShouldNotify(TvPageScope oldWidget) =>
      !identical(oldWidget.page, page);
}
