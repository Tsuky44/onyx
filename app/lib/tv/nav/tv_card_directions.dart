import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ce que `TvFocusable.onDirection` fait d'une flèche quand le focus est sur
/// l'une des cibles internes de la carte (`TvFocusable.childFocus`) : les
/// icônes d'une ligne d'épisode, que le parcours ne voit pas.
///
/// Gauche et droite vont à `onDirection` : c'est la carte qui sait passer
/// d'une icône à l'autre. Haut et bas partent de la carte, pas de l'icône.
///
/// - **Sous dpad** ([TvCardDirections.dpad]), il n'y a rien à faire pour
///   haut et bas : la carte contient l'icône, elle n'est donc pas « en
///   dessous » d'elle, et les icônes des autres cartes sont hors du parcours ;
///   dpad, parti du rectangle de l'icône, arrive sur la carte voisine. Quand
///   c'est la carte elle-même qui a le focus, `DpadFocusable.onDirection` s'en
///   charge.
/// - **Avec l'ancien système** ([TvCardDirections.legacy]), le parcours
///   partait du rectangle de l'icône, en haut de la ligne, et Bas retombait
///   sur la ligne elle-même : le focus repasse à la carte, puis la flèche
///   repart d'elle (le code d'`EpisodeTile` d'avant la refonte, déplacé ici à
///   l'identique). Disparaît avec le drapeau `ONYX_TV_NAV`.
class TvCardDirections extends StatelessWidget {
  const TvCardDirections.dpad({
    super.key,
    required this.card,
    required this.onDirection,
    required this.child,
  }) : _legacy = false;

  const TvCardDirections.legacy({
    super.key,
    required this.card,
    required this.onDirection,
    required this.child,
  }) : _legacy = true;

  /// Le nœud de la carte.
  final FocusNode card;
  final bool Function(TraversalDirection direction) onDirection;
  final Widget child;
  final bool _legacy;

  static final Map<LogicalKeyboardKey, TraversalDirection> _arrows = {
    LogicalKeyboardKey.arrowUp: TraversalDirection.up,
    LogicalKeyboardKey.arrowDown: TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
    LogicalKeyboardKey.arrowRight: TraversalDirection.right,
  };

  static bool _vertical(TraversalDirection direction) =>
      direction == TraversalDirection.up ||
      direction == TraversalDirection.down;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) =>
            _legacy ? _onLegacyKey(event) : _onDpadKey(context, event),
        child: child,
      );

  /// Le focus est sur une cible interne de la carte, pas sur la carte.
  bool _insideCard(FocusNode? current) =>
      current != null &&
      !identical(current, card) &&
      current.ancestors.contains(card);

  KeyEventResult _onDpadKey(BuildContext context, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // La carte elle-même : `DpadFocusable.onDirection` a déjà répondu.
    if (!_insideCard(FocusManager.instance.primaryFocus)) {
      return KeyEventResult.ignored;
    }
    final direction = Dpad.keySetOf(context).directionOf(event.logicalKey);
    if (direction == null || _vertical(direction)) {
      return KeyEventResult.ignored;
    }
    return onDirection(direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  KeyEventResult _onLegacyKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = _arrows[event.logicalKey];
    if (direction == null) return KeyEventResult.ignored;
    if (_vertical(direction) &&
        _insideCard(FocusManager.instance.primaryFocus)) {
      card.requestFocus();
      // Après la microtâche qui applique ce focus, pas avant.
      unawaited(
        Future.microtask(() {
          if (card.hasPrimaryFocus) card.focusInDirection(direction);
        }),
      );
      return KeyEventResult.handled;
    }
    return onDirection(direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}
