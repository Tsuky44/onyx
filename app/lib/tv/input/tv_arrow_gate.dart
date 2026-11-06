import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../tv_mode.dart';
import 'step_target.dart';

/// Combien de pas vaut une flèche partie de [from] vers [direction] : 1 pour
/// un appui, davantage pour un glissé vif sur le trackpad (`TvTouchpad`).
typedef TvArrowSteps = int Function(
    FocusNode from, TraversalDirection direction);

int _oneStep(FocusNode from, TraversalDirection direction) => 1;

/// Le seul intercepteur de flèches de l'app (ADR-0110).
///
/// Il se pose juste **sous** `Dpad` : les touches remontent du focus vers la
/// racine, un écran qui les veut (le lecteur, un curseur) les voit d'abord,
/// puis ce portail, puis les raccourcis de dpad (constat C4). Pour chaque
/// flèche, trois issues :
///
/// - **laisser passer**, le cas normal : dpad choisit la cible et la ramène
///   à l'écran ;
/// - **retenir** une répétition arrivée moins de [repeatInterval] après le
///   pas précédent. Android répète une touche maintenue toutes les 50 ms
///   environ ; à ce rythme le focus dépasse les cartes que la rangée n'a pas
///   encore construites, et dpad perd des pas pendant qu'il fait défiler
///   pour les trouver (constats C6 et C13 : 2 pas perdus sur 16 à 40 ms,
///   aucun à 80 ms). dpad ne régule rien lui-même ;
/// - **faire plusieurs pas** d'un coup quand [stepsFor] le demande : la carte
///   d'arrivée est calculée par [StepTarget] et reçoit le focus une seule
///   fois, donc un seul défilement.
///
/// Hors téléviseur, et quand un champ de texte a le focus, tout passe.
class TvArrowGate extends StatefulWidget {
  const TvArrowGate({
    super.key,
    required this.child,
    this.repeatInterval = defaultRepeatInterval,
    this.stepsFor = _oneStep,
  });

  final Widget child;

  /// L'écart minimal entre deux pas d'une flèche maintenue.
  final Duration repeatInterval;

  final TvArrowSteps stepsFor;

  /// Assez lent pour que la carte suivante soit construite et à l'écran,
  /// assez rapide pour qu'une longue rangée se parcoure d'un seul geste.
  static const Duration defaultRepeatInterval = Duration(milliseconds: 110);

  /// Remplace l'horloge dans les tests.
  @visibleForTesting
  static Duration Function()? debugClock;

  @override
  State<TvArrowGate> createState() => _TvArrowGateState();
}

class _TvArrowGateState extends State<TvArrowGate> {
  final FocusNode _node = FocusNode(
    debugLabel: 'tv-arrow-gate',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _lastMove;

  Duration _now() => TvArrowGate.debugClock?.call() ?? _stopwatch.elapsed;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !TvMode.isTv) return KeyEventResult.ignored;
    final direction = Dpad.keySetOf(context).directionOf(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    final focusContext = primary?.context;
    if (primary == null || focusContext == null) {
      return KeyEventResult.ignored;
    }
    // Le curseur d'un champ a sa propre cadence : dpad décide seul quand la
    // flèche quitte le champ.
    if (focusContext.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }

    final now = _now();
    final last = _lastMove;
    if (event is KeyRepeatEvent &&
        last != null &&
        now - last < widget.repeatInterval) {
      return KeyEventResult.handled;
    }
    _lastMove = now;

    final target = StepTarget.after(
        primary, direction, widget.stepsFor(primary, direction));
    if (target == null) return KeyEventResult.ignored;
    // Les pas intermédiaires ne prennent pas le focus : seule la carte
    // d'arrivée défile à l'écran et s'inscrit dans la mémoire de sa zone.
    return Dpad.maybeOf(context)?.requestFocus(target) ?? false
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _handleKey,
      child: widget.child,
    );
  }
}
