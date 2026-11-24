import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../tv_focus_memory.dart';

/// `TvRegion.slide` avec l'ancien système.
///
/// Deux promesses :
///
/// - **gauche et droite au bord de la page affichée appellent [onEdge]** quand
///   aucun de ses éléments ne suit sur la ligne. C'est le `Focus(onKeyEvent:)`
///   du bandeau de l'accueil d'avant la refonte (`HeroCarousel`), déplacé ici
///   à l'identique : sans lui, la télécommande ne voyait que la diapositive
///   affichée, droite depuis « Plus d'infos » sautait n'importe où à droite de
///   l'écran (la recherche de l'en-tête), et les autres titres ne
///   s'atteignaient qu'en attendant que le carrousel tourne. Sous dpad, c'est
///   le bord `stop` d'une `DpadRegion` qui fait ce travail ;
/// - **la diapositive est l'entrée de sa page tant qu'elle est à l'écran**
///   (`TvFocusMemoryState.addLead`) : Bas depuis la barre arrive sur son
///   premier bouton, « Reprendre », et non sur la carte d'une rangée où l'on
///   était passé avant.
///
/// Disparaît avec le drapeau `ONYX_TV_NAV`.
class TvSlideEdges extends StatefulWidget {
  const TvSlideEdges({super.key, this.onEdge, required this.child});

  /// Nul pour un carrousel d'une seule page : gauche et droite sortent.
  final ValueChanged<TraversalDirection>? onEdge;
  final Widget child;

  @override
  State<TvSlideEdges> createState() => _TvSlideEdgesState();
}

class _TvSlideEdgesState extends State<TvSlideEdges> {
  final FocusNode _node = FocusNode(
    debugLabel: 'tv-slide',
    canRequestFocus: false,
    skipTraversal: true,
  );

  TvFocusMemoryState? _memory;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final memory = TvFocusMemory.maybeOf(context);
    if (identical(memory, _memory)) return;
    _memory?.removeLead(_node);
    _memory = memory;
    memory?.addLead(_node);
  }

  @override
  void dispose() {
    _memory?.removeLead(_node);
    _memory = null;
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final onEdge = widget.onEdge;
    if (onEdge == null) return KeyEventResult.ignored;
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
        focusNode: _node,
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKey,
        child: widget.child,
      );
}
