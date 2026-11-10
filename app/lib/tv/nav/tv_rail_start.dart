import 'package:flutter/widgets.dart';

/// L'entrée d'une rangée horizontale : sa première carte, quelle que soit
/// la carte qu'on quitte (ADR-0113).
///
/// Descendre de la quatrième carte de « Reprendre » tombait sur la carte
/// juste en dessous dans la rangée suivante, au milieu de celle-ci : on ne
/// savait plus où commençait la rangée, ni ce qu'on avait sauté. Changer de
/// zone ramène donc au début de la rangée, comme sur les interfaces de salon.
///
/// Une rangée qu'on a fait défiler loin n'a plus sa première carte construite
/// (la liste ne garde qu'un écran de part et d'autre) : la plus à gauche des
/// cartes construites prend le focus, puis la rangée revient à son début et
/// la vraie première carte le reprend, une image plus tard.
abstract final class TvRailStart {
  /// La plus à gauche de [nodes] posées à l'écran, puis la plus haute.
  static FocusNode? firstOf(Iterable<FocusNode> nodes) {
    FocusNode? best;
    for (final node in nodes) {
      if (node.context == null || node.rect.isEmpty) continue;
      if (best == null) {
        best = node;
        continue;
      }
      final byLeft = node.rect.left.compareTo(best.rect.left);
      if (byLeft < 0 || (byLeft == 0 && node.rect.top < best.rect.top)) {
        best = node;
      }
    }
    return best;
  }

  /// La carte où entrer parmi [candidates], les cartes de la rangée
  /// atteignables maintenant. [current] les relit après le retour au début.
  static FocusNode? enter(
    Iterable<FocusNode> candidates, {
    required Iterable<FocusNode> Function() current,
  }) {
    final first = firstOf(candidates);
    if (first == null) return null;
    final context = first.context;
    final scrollable = context == null
        ? null
        : Scrollable.maybeOf(context, axis: Axis.horizontal);
    if (scrollable != null && !_startIsBuilt(scrollable, first)) {
      // Une image d'attente : la carte focalisée lance son propre défilement
      // jusqu'à elle à l'image qui suit le focus. Sauté avant lui, le retour
      // au début était aussitôt défait ; sauté après, il l'interrompt.
      _afterFrames(2, () {
        if (!scrollable.mounted) return;
        final position = scrollable.position;
        position.jumpTo(position.minScrollExtent);
        _afterFrames(1, () {
          if (!scrollable.mounted) return;
          firstOf(current())?.requestFocus();
        });
      });
    }
    return first;
  }

  static void _afterFrames(int frames, VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (frames <= 1) {
        action();
        return;
      }
      WidgetsBinding.instance.scheduleFrame();
      _afterFrames(frames - 1, action);
    });
  }

  /// Vrai si [first] est bien la première carte de la rangée.
  ///
  /// La première carte se tient dans la marge de tête de la liste, bien avant
  /// la moitié de la largeur visible : plus loin dans le contenu, c'est une
  /// carte du milieu, et le début de la rangée n'est pas construit.
  static bool _startIsBuilt(ScrollableState scrollable, FocusNode first) {
    final position = scrollable.position;
    if (!position.hasPixels || position.pixels <= position.minScrollExtent) {
      return true;
    }
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return true;
    final viewportLeft = box.localToGlobal(Offset.zero).dx;
    final inContent = position.pixels -
        position.minScrollExtent +
        first.rect.left -
        viewportLeft;
    return inContent < box.size.width / 2;
  }
}
