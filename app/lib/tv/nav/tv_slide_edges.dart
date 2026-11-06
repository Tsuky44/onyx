import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// `TvRegion.slide` avec l'ancien système : gauche et droite au bord de la
/// page affichée appellent [onEdge] quand aucun de ses éléments ne suit sur
/// la ligne.
///
/// C'est le `Focus(onKeyEvent:)` du bandeau de l'accueil d'avant la refonte
/// (`HeroCarousel`), déplacé ici à l'identique : sans lui, la télécommande ne
/// voyait que la diapositive affichée, droite depuis « Plus d'infos » sautait
/// n'importe où à droite de l'écran (la recherche de l'en-tête), et les autres
/// titres ne s'atteignaient qu'en attendant que le carrousel tourne. Sous
/// dpad, c'est le bord `stop` d'une `DpadRegion` qui fait ce travail.
/// Disparaît avec le drapeau `ONYX_TV_NAV`.
class TvSlideEdges extends StatelessWidget {
  const TvSlideEdges({super.key, required this.onEdge, required this.child});

  final ValueChanged<TraversalDirection> onEdge;
  final Widget child;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final direction = key == LogicalKeyboardKey.arrowRight
        ? TraversalDirection.right
        : key == LogicalKeyboardKey.arrowLeft
            ? TraversalDirection.left
            : null;
    if (direction == null) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return KeyEventResult.ignored;
    final from = focused.rect;
    final forward = direction == TraversalDirection.right;
    // Un voisin dans la page, sur la même ligne : la flèche lui revient.
    final hasNeighbour = node.traversalDescendants.any((other) {
      if (identical(other, focused)) return false;
      final rect = other.rect;
      final ahead =
          forward ? rect.left >= from.right - 1 : rect.right <= from.left + 1;
      return ahead && rect.top < from.bottom && rect.bottom > from.top;
    });
    if (hasNeighbour) return KeyEventResult.ignored;
    onEdge(direction);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKey,
        child: child,
      );
}
