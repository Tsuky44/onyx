import 'package:flutter/widgets.dart';

/// La carte d'arrivée d'un déplacement de plusieurs pas dans une rangée.
///
/// Un glissé vif sur le trackpad de l'Apple TV vaut plusieurs pas (ADR-0039),
/// et une rafale de flèches arrivées avant que le focus de la première soit
/// posé aussi (constat N2). Les faire un par un, c'est autant de
/// `requestFocus` et de défilements relancés : la rangée saccade, ou les pas
/// se perdent parce qu'ils partent tous de la même carte. On calcule donc la
/// carte d'arrivée d'abord, puis `TvArrowGate` y pose le focus une seule fois.
///
/// Deux bornes, voulues :
///
/// - **jamais à la verticale** : un pas vers le haut ou le bas change de
///   rangée, et sauter des rangées entières d'un glissé perd l'utilisateur
///   (ADR-0039) ;
/// - **seulement parmi les cartes construites de la rangée** : au-delà, dpad
///   ferait défiler puis réessaierait (constat C6), et la flèche suivante
///   arriverait pendant ce réessai. Le compte de pas s'arrête donc à la
///   dernière carte que la rangée a déjà construite ; la flèche d'après, partie
///   de là, laisse dpad faire défiler et réessayer.
abstract final class StepTarget {
  /// La carte atteinte depuis [from] après au plus [steps] pas vers
  /// [direction], et le nombre de pas réellement faits.
  ///
  /// Nul quand [from] n'est pas dans une rangée qui défile à l'horizontale,
  /// quand la direction est verticale, ou quand le premier pas ne mène nulle
  /// part (bout de la rangée, ou de ce qu'elle a construit) : la décision
  /// revient alors à dpad. Chaque pas reste dans la rangée de [from] : rien à
  /// côté d'elle (un bouton, l'en-tête, une autre zone) ne compte comme un pas.
  static ({FocusNode node, int steps})? after(
    FocusNode from,
    TraversalDirection direction,
    int steps,
  ) {
    if (steps < 1) return null;
    if (direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      return null;
    }
    final context = from.context;
    if (context == null) return null;
    final row = Scrollable.maybeOf(context, axis: Axis.horizontal);
    if (row == null) return null;
    FocusNode? target;
    var made = 0;
    while (made < steps) {
      final candidates = _lineCandidates(target ?? from, direction)
          .where((node) =>
              Scrollable.maybeOf(node.context!, axis: Axis.horizontal) == row)
          .toList();
      if (candidates.isEmpty) break;
      target = _nearest(target ?? from, direction, candidates);
      made++;
    }
    return target == null ? null : (node: target, steps: made);
  }

  /// Le voisin le plus proche de [current] dans [direction], parmi ce qui
  /// partage sa ligne — ce qui chevauche verticalement sa hauteur. Nul quand il
  /// n'y en a pas.
  ///
  /// Au bout d'une rangée ou d'une ligne de grille, le parcours de Flutter
  /// cherche « quelque chose à droite » n'importe où sur l'écran : l'avatar du
  /// compte dans l'en-tête, une affiche d'une autre rangée qui dépasse plus
  /// loin. Le focus sautait alors à l'autre bout de l'écran. Ici, rien sur la
  /// même ligne veut dire rien.
  ///
  /// Sans voisin, la flèche entre dans [current] : une ligne de réglages
  /// cliquable qui porte un bouton à son bord droit l'*englobe*, et ce bouton,
  /// qui n'est « à droite » de rien, n'était atteignable d'aucun côté.
  ///
  /// C'est le pas de l'ancien système (`TvDirectionalFocusAction`) ; sous
  /// dpad, seul [after] sert.
  static FocusNode? nextOnLine(
    FocusNode current,
    TraversalDirection direction,
  ) {
    if (current.nearestScope == null) return null;
    final candidates = _lineCandidates(current, direction);
    if (candidates.isEmpty) return _enclosedBy(current, direction);

    // Ce qui défile avec l'élément d'abord : dans une rangée, la carte
    // suivante, et pas un bouton posé à côté de la rangée.
    final scrollable =
        Scrollable.maybeOf(current.context!, axis: Axis.horizontal);
    if (scrollable != null) {
      final sameScrollable = candidates
          .where((node) =>
              Scrollable.maybeOf(node.context!, axis: Axis.horizontal) ==
              scrollable)
          .toList();
      if (sameScrollable.isNotEmpty) {
        candidates
          ..clear()
          ..addAll(sameScrollable);
      }
    }
    return _nearest(current, direction, candidates);
  }

  /// Ce qui est au-delà de [current] dans [direction] et partage sa ligne.
  static List<FocusNode> _lineCandidates(
    FocusNode current,
    TraversalDirection direction,
  ) {
    final scope = current.nearestScope;
    if (scope == null || current.context == null) return <FocusNode>[];
    final from = current.rect;
    final right = direction == TraversalDirection.right;
    return scope.traversalDescendants.where((node) {
      if (identical(node, current) || node.context == null) return false;
      final rect = node.rect;
      if (rect.isEmpty) return false;
      // Même règle que Flutter pour « à droite de » / « à gauche de ».
      final beyond =
          right ? rect.center.dx >= from.right : rect.center.dx <= from.left;
      return beyond && rect.top < from.bottom && rect.bottom > from.top;
    }).toList();
  }

  /// Le plus proche de [current] parmi [candidates] : l'écart horizontal
  /// d'abord ; à égalité, le mieux aligné.
  static FocusNode _nearest(
    FocusNode current,
    TraversalDirection direction,
    List<FocusNode> candidates,
  ) {
    final from = current.rect;
    final right = direction == TraversalDirection.right;
    double distance(FocusNode node) {
      final rect = node.rect;
      final dx = right ? rect.left - from.right : from.left - rect.right;
      final dy = (rect.center.dy - from.center.dy).abs();
      return dx.abs() * 1000 + dy;
    }

    candidates.sort((a, b) => distance(a).compareTo(distance(b)));
    return candidates.first;
  }

  /// Le premier élément focalisable contenu dans [current], du côté de
  /// [direction] par rapport à son centre.
  static FocusNode? _enclosedBy(
    FocusNode current,
    TraversalDirection direction,
  ) {
    final from = current.rect;
    final right = direction == TraversalDirection.right;
    FocusNode? best;
    for (final node in current.traversalDescendants) {
      if (node.context == null || node.rect.isEmpty) continue;
      final rect = node.rect;
      final beyond = right
          ? rect.center.dx > from.center.dx
          : rect.center.dx < from.center.dx;
      if (!beyond) continue;
      if (best == null ||
          (right ? rect.left < best.rect.left : rect.right > best.rect.right)) {
        best = node;
      }
    }
    return best;
  }
}
