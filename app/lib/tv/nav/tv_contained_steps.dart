import 'package:flutter/widgets.dart';

/// Gauche et droite entre une ligne cliquable et les boutons qu'elle
/// contient : le menu d'une ligne de téléchargement, le menu d'heure au bout
/// de « Plage horaire » dans les réglages.
///
/// dpad ne cherche que ce qui est *à droite* (ou à gauche) du rectangle
/// quitté. Un bouton contenu dans sa ligne ne l'est jamais : la ligne
/// commence avant lui et finit avec lui. Sans ces pas, le bouton n'est
/// atteignable par aucune flèche (ADR-0110). Haut et bas ne passent pas ici.
abstract final class TvContainedSteps {
  static bool _placed(FocusNode node) =>
      node is! FocusScopeNode && node.context != null && !node.rect.isEmpty;

  /// Les boutons de [row] posés à l'écran, qu'ils soient ou non dans le
  /// parcours directionnel : ceux d'un `TvFocusable.childFocus` n'y sont pas
  /// sous dpad, justement pour n'être atteints que d'ici.
  static Iterable<FocusNode> _inside(FocusNode row) =>
      row.descendants.where((node) => node.canRequestFocus).where(_placed);

  /// Droite depuis la ligne [row] : son premier bouton à droite de son
  /// centre. Nul s'il n'y en a pas.
  static FocusNode? into(FocusNode row) {
    if (!_placed(row)) return null;
    final from = row.rect.center.dx;
    FocusNode? best;
    for (final inner in _inside(row)) {
      if (inner.rect.center.dx <= from) continue;
      if (best == null || inner.rect.left < best.rect.left) best = inner;
    }
    return best;
  }

  /// La ligne qui contient le bouton [node] : son ancêtre focalisable le
  /// plus proche, dans la même portée. Nul hors d'une ligne.
  static FocusNode? rowOf(FocusNode node) {
    for (final ancestor in node.ancestors) {
      if (ancestor is FocusScopeNode) return null;
      if (ancestor.canRequestFocus &&
          !ancestor.skipTraversal &&
          _placed(ancestor)) {
        return ancestor;
      }
    }
    return null;
  }

  /// Le voisin du bouton [node] dans sa ligne [row], vers [direction] (gauche
  /// ou droite). Nul au bord de la ligne.
  static FocusNode? beside(
    FocusNode node,
    FocusNode row,
    TraversalDirection direction,
  ) {
    if (!_placed(node)) return null;
    final forward = direction == TraversalDirection.right;
    final rect = node.rect;
    FocusNode? best;
    for (final inner in _inside(row)) {
      if (identical(inner, node)) continue;
      final ahead = forward
          ? inner.rect.left >= rect.right - 1
          : inner.rect.right <= rect.left + 1;
      if (!ahead) continue;
      if (best == null ||
          (forward
              ? inner.rect.left < best.rect.left
              : inner.rect.right > best.rect.right)) {
        best = inner;
      }
    }
    return best;
  }

  /// Gauche depuis le bouton [node] : son voisin de gauche dans la ligne,
  /// sinon la ligne elle-même. Nul hors d'une ligne.
  static FocusNode? outOf(FocusNode node) {
    if (!_placed(node)) return null;
    final row = rowOf(node);
    if (row == null) return null;
    return beside(node, row, TraversalDirection.left) ?? row;
  }
}
