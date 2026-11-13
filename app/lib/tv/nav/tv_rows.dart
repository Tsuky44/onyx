import 'package:flutter/widgets.dart';

/// Les lignes d'une section de fiche, lues dans la place de ses cibles.
///
/// Le parcours directionnel ordinaire cherche « la cible la mieux alignée »
/// dans tout l'écran : depuis le bouton retour, calé à gauche, Bas sautait les
/// actions de la fiche (plus à droite) pour une section entière plus bas, et
/// rien ne ramenait ensuite sur « Lecture ». Ici une section se lit comme un
/// texte : ses cibles forment des lignes, Bas mène à la ligne suivante et Haut
/// à la précédente, où qu'elles se trouvent à l'horizontale.
///
/// Sans état : chaque appel relit les rectangles du moment
/// ([FocusNode.rect]), tous dans le même repère.
abstract final class TvRows {
  /// Vrai quand [a] et [b] partagent une ligne : le milieu de l'un tombe dans
  /// la hauteur de l'autre.
  ///
  /// Un recouvrement suffisant plutôt qu'une hauteur commune : les cartes
  /// d'un éventail penchent et se soulèvent, une icône ronde dépasse d'un
  /// pixel la pastille qu'elle suit. Aucun seuil en pixels : la page d'un
  /// téléviseur est mise à l'échelle, et un seuil changerait de sens avec
  /// elle.
  static bool sameRow(Rect a, Rect b) =>
      (a.center.dy >= b.top && a.center.dy <= b.bottom) ||
      (b.center.dy >= a.top && b.center.dy <= a.bottom);

  /// La ligne qui suit celle de [current] parmi [candidates], vers le bas
  /// ([down]) ou vers le haut. Vide quand [current] est sur la dernière.
  static List<FocusNode> next(
    FocusNode current,
    Iterable<FocusNode> candidates, {
    required bool down,
  }) {
    final from = current.rect;
    final beyond = <FocusNode>[
      for (final node in candidates)
        if (!identical(node, current) &&
            !sameRow(node.rect, from) &&
            (down
                ? node.rect.center.dy > from.bottom
                : node.rect.center.dy < from.top))
          node,
    ];
    return _nearestRow(beyond, top: down);
  }

  /// La ligne par où l'on entre dans [candidates] : la plus haute en venant
  /// du dessus ([top]), la plus basse en venant du dessous.
  static List<FocusNode> edge(
    Iterable<FocusNode> candidates, {
    required bool top,
  }) =>
      _nearestRow(candidates.toList(), top: top);

  /// La ligne de [node] parmi [candidates], [node] compris.
  static List<FocusNode> of(FocusNode node, Iterable<FocusNode> candidates) {
    final rect = node.rect;
    return <FocusNode>[
      for (final other in candidates)
        if (identical(other, node) || sameRow(other.rect, rect)) other,
    ];
  }

  /// La cible de [row] où arriver depuis [from] quand la ligne n'a pas
  /// d'entrée : celle qui est à sa verticale, sinon le début de la ligne.
  ///
  /// Toujours la plus à gauche des candidates : quand [from] en surplombe
  /// plusieurs (une ligne d'épisode ou un bandeau pleine largeur au-dessus
  /// d'une rangée de boutons), et quand il n'en surplombe aucune (« Demander »,
  /// à droite de l'affiche, au-dessus de bulles de saisons calées à gauche).
  /// On entre dans une ligne par son début (ADR-0113), pas par la cible qui
  /// se trouve la plus près en biais.
  static FocusNode enter(List<FocusNode> row, Rect from) {
    final under = <FocusNode>[
      for (final node in row)
        if (node.rect.right > from.left && node.rect.left < from.right) node,
    ];
    return (under.isEmpty ? row : under).reduce(
      (first, node) => node.rect.left < first.rect.left ? node : first,
    );
  }

  static List<FocusNode> _nearestRow(
    List<FocusNode> nodes, {
    required bool top,
  }) {
    if (nodes.isEmpty) return const <FocusNode>[];
    final lead = nodes.reduce((best, node) => top
        ? (node.rect.top < best.rect.top ? node : best)
        : (node.rect.bottom > best.rect.bottom ? node : best));
    return of(lead, nodes);
  }
}
