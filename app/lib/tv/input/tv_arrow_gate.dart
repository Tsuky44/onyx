import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../tv_mode.dart';
import '../tv_touchpad.dart';
import 'step_target.dart';
import 'tv_dpad_log.dart';

/// Combien de pas vaut une flèche partie de [from] vers [direction] : 1 pour
/// un appui, davantage pour un glissé vif sur le trackpad (`TvTouchpad`).
typedef TvArrowSteps = int Function(
    FocusNode from, TraversalDirection direction);

int _oneStep(FocusNode from, TraversalDirection direction) => 1;

/// Le seul intercepteur de flèches de l'app (ADR-0110), la couche CADENCE du
/// plan de refonte (§3).
///
/// Il se pose juste **sous** `Dpad` : les touches remontent du focus vers la
/// racine, un écran qui les veut (le lecteur, un curseur) les voit d'abord,
/// puis ce portail, puis les raccourcis de dpad (constat C4). Pour chaque
/// flèche, trois issues :
///
/// - **laisser décider dpad**, le cas normal : une flèche, un pas, choisi par
///   la politique de dpad (zones, mémoire, entrée) et ramené à l'écran par
///   elle ;
/// - **retenir** une répétition arrivée moins de [repeatInterval] après le
///   pas précédent. Android répète une touche maintenue toutes les 50 ms
///   environ ; à ce rythme le focus dépasse les cartes que la rangée n'a pas
///   encore construites, et dpad perd des pas pendant qu'il fait défiler
///   pour les trouver (constats C6 et C13 : 2 pas perdus sur 16 à 40 ms,
///   aucun à 80 ms). dpad ne régule rien lui-même. Sur Apple TV, c'est le
///   moteur qui règle la cadence (`TvRepeatCadence`), et [repeatInterval] est
///   nul : la même cadence ne se règle pas deux fois ;
/// - **faire plusieurs pas** d'un coup, quand [stepsFor] le demande (glissé
///   vif) ou quand plusieurs flèches arrivent avant que le focus de la
///   première soit posé (une **rafale**, constat N2). La carte d'arrivée est
///   calculée par [StepTarget] et reçoit le focus par **un seul**
///   `requestFocus` : un seul défilement, et la mémoire de la zone note la
///   carte d'arrivée, pas une carte demandée puis abandonnée (constat N3).
///
/// Chaque flèche reçue est donc consommée ici et appliquée à la microtâche
/// suivante : le focus que Flutter demande ne se pose lui-même qu'en
/// microtâche, et toutes les flèches arrivées d'ici là partiraient de la même
/// carte. Elles s'additionnent au lieu de se perdre.
///
/// Il fait aussi les pas de l'élan du trackpad ([TvTouchpad.glideStepper]),
/// par [StepTarget] : un pas d'élan reste dans sa rangée.
///
/// Hors téléviseur, quand un champ de texte a le focus (dpad décide alors
/// quand la flèche le quitte), ou sans `Dpad` au-dessus, tout passe.
class TvArrowGate extends StatefulWidget {
  const TvArrowGate({
    super.key,
    required this.child,
    this.repeatInterval = defaultRepeatInterval,
    this.stepsFor = _oneStep,
  });

  final Widget child;

  /// L'écart minimal entre deux pas d'une flèche maintenue ; nul quand la
  /// plateforme règle elle-même la répétition (Apple TV, `TvRepeatCadence`).
  final Duration? repeatInterval;

  final TvArrowSteps stepsFor;

  /// Assez lent pour que la carte suivante soit construite et à l'écran,
  /// assez rapide pour qu'une longue rangée se parcoure d'un seul geste. La
  /// valeur de l'ancien système (`TvKeyRepeat`), reprise telle quelle.
  ///
  /// À valider sur vraie Apple TV et sur Android TV : rapport de phase 0,
  /// §5.2 (touche maintenue) et §5.9.
  static const Duration defaultRepeatInterval = Duration(milliseconds: 110);

  /// Remplace l'horloge dans les tests.
  @visibleForTesting
  static Duration Function()? debugClock;

  @override
  State<TvArrowGate> createState() => _TvArrowGateState();
}

/// Les flèches arrivées avant que la première soit appliquée.
class _Burst {
  _Burst(this.direction);

  final TraversalDirection direction;

  /// Les flèches reçues.
  int arrows = 0;

  /// Les pas qu'elles demandent : une par flèche, davantage pour celles d'un
  /// glissé vif.
  int steps = 0;
}

class _TvArrowGateState extends State<TvArrowGate> {
  final FocusNode _node = FocusNode(
    debugLabel: 'tv-arrow-gate',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Le dernier pas laissé passer, pour la régulation de la répétition.
  Duration? _lastMove;

  /// La dernière flèche reçue, retenue ou non : la cadence que la plateforme
  /// envoie, pour les traces.
  Duration? _lastArrow;

  _Burst? _burst;

  Duration _now() => TvArrowGate.debugClock?.call() ?? _stopwatch.elapsed;

  @override
  void initState() {
    super.initState();
    TvTouchpad.glideStepper = _glideStep;
  }

  @override
  void dispose() {
    if (TvTouchpad.glideStepper == _glideStep) TvTouchpad.glideStepper = null;
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !TvMode.isTv) return KeyEventResult.ignored;
    if (Dpad.maybeOf(context) == null) return KeyEventResult.ignored;
    final direction = Dpad.keySetOf(context).directionOf(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    final focusContext = primary?.context;
    // Rien de focalisé, ou une portée seule : dpad repose le focus lui-même.
    if (primary == null || focusContext == null || primary is FocusScopeNode) {
      return KeyEventResult.ignored;
    }
    // Le curseur d'un champ a sa propre cadence : dpad décide seul quand la
    // flèche quitte le champ.
    if (focusContext.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }

    final now = _now();
    final repeat = event is KeyRepeatEvent;
    final sinceArrow = _lastArrow == null ? null : now - _lastArrow!;
    _lastArrow = now;
    final interval = widget.repeatInterval;
    final last = _lastMove;
    if (repeat && interval != null && last != null && now - last < interval) {
      TvDpadLog.log(() => '${_arrowLabel(direction, repeat, sinceArrow)} '
          'retenue (< ${interval.inMilliseconds} ms)');
      return KeyEventResult.handled;
    }
    _lastMove = now;

    // Une flèche dans un autre sens n'allonge pas la rafale : celle en cours
    // s'applique d'abord, et la nouvelle part de sa carte d'arrivée.
    if (_burst != null && _burst!.direction != direction) {
      _apply();
      FocusManager.instance.applyFocusChangesIfNeeded();
    }
    final from = FocusManager.instance.primaryFocus ?? primary;
    final burst = _burst ??= _Burst(direction);
    if (burst.arrows == 0) scheduleMicrotask(_apply);
    final steps = widget.stepsFor(from, direction).clamp(1, 1 << 16);
    burst
      ..arrows += 1
      ..steps += steps;
    TvDpadLog.log(() => '${_arrowLabel(direction, repeat, sinceArrow)}'
        '${steps > 1 ? ' glissé ×$steps' : ''}'
        '${burst.arrows > 1 ? ' rafale #${burst.arrows}' : ''}');
    return KeyEventResult.handled;
  }

  /// Applique la rafale en cours : un pas par dpad, ou plusieurs par
  /// [StepTarget], toujours par un seul `requestFocus`.
  void _apply() {
    final burst = _burst;
    _burst = null;
    if (burst == null || burst.arrows == 0 || !mounted) return;
    final dpad = Dpad.maybeOf(context);
    final from = FocusManager.instance.primaryFocus;
    if (dpad == null || from == null || from.context == null) return;
    final direction = burst.direction;
    final grouped = burst.arrows > 1 ? ' (rafale de ${burst.arrows})' : '';

    if (burst.steps > 1) {
      final hop = StepTarget.after(from, direction, burst.steps);
      if (hop != null) {
        final moved = dpad.requestFocus(hop.node);
        TvDpadLog.log(() => 'pas ${hop.steps}/${burst.steps}$grouped'
            '${hop.steps < burst.steps ? ' borné : bout de la rangée ou de ses cartes construites' : ''}'
            ' → ${_describe(hop.node)}${moved ? '' : ' refusé'}');
        return;
      }
    }
    // Un pas, ou plusieurs là où ils ne se comptent pas : à la verticale
    // (ADR-0039), hors d'une rangée, au bout de ce qu'elle a construit. dpad
    // fait ce pas-là avec sa politique, et fait défiler puis réessaie au
    // besoin (constat C6) ; les autres pas de la rafale tombent.
    final moved = dpad.move(direction);
    TvDpadLog.log(() => burst.steps > 1
        ? 'pas 1/${burst.steps}$grouped par dpad (${_why(from, direction)})'
        : 'pas 1 par dpad${moved ? '' : ' : bloqué'}');
  }

  /// Un pas d'élan, dans la rangée seulement. Faux quand il n'y a plus de
  /// carte construite devant : la lancée s'arrête là.
  bool _glideStep(TraversalDirection direction) {
    if (!mounted) return false;
    final dpad = Dpad.maybeOf(context);
    final from = FocusManager.instance.primaryFocus;
    if (dpad == null || from == null || from.context == null) return false;
    final hop = StepTarget.after(from, direction, 1);
    if (hop == null) return false;
    final moved = dpad.requestFocus(hop.node);
    TvDpadLog.log(() => 'élan : pas → ${_describe(hop.node)}'
        '${moved ? '' : ' refusé'}');
    return moved;
  }

  static String _arrowLabel(
    TraversalDirection direction,
    bool repeat,
    Duration? since,
  ) =>
      '${direction.name} ${repeat ? 'rep' : 'appui'}'
      '${since == null ? '' : ' +${since.inMilliseconds} ms'}';

  static String _why(FocusNode from, TraversalDirection direction) =>
      direction == TraversalDirection.up || direction == TraversalDirection.down
          ? 'verticale'
          : from.context != null &&
                  Scrollable.maybeOf(from.context!, axis: Axis.horizontal) ==
                      null
              ? 'hors rangée'
              : 'bout de la rangée ou de ses cartes construites';

  static String _describe(FocusNode node) =>
      '${node.debugLabel ?? node.runtimeType} '
      'x=${node.context == null ? '?' : node.rect.left.round()}';

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
