import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'input/step_target.dart';
import 'input/tv_arrow_gate.dart';
import 'tv_focus_entry.dart';
import 'tv_focus_panes.dart';
import 'tv_focus_scroll.dart';
import 'tv_mode.dart';

/// Ce que la télécommande fait quand on laisse une flèche enfoncée.
///
/// Android répète une touche maintenue toutes les 50 ms environ. Chaque
/// répétition déplaçait le focus d'une carte et relançait le défilement animé
/// qui la ramène à l'écran ; au bout de quelques cartes, le focus courait devant
/// une rangée qui n'avait pas fini de défiler, arrivait sur des cartes pas encore
/// construites, et s'arrêtait net — la rangée « bloquait » au milieu. Les
/// interfaces TV natives d'Android régulent ce débit ; Flutter ne le fait pas.
///
/// On observe donc les touches avant le système de focus pour savoir si la flèche
/// en cours est une répétition, et [TvDirectionalFocusAction] laisse passer au
/// plus un déplacement par [repeatInterval] tant qu'elle l'est. Un appui simple
/// n'est jamais retenu.
abstract final class TvKeyRepeat {
  /// La cadence de `TvArrowGate`, qui reprend ce rôle avec dpad (ADR-0110).
  static const Duration repeatInterval = TvArrowGate.defaultRepeatInterval;

  static bool _installed = false;
  static bool _repeating = false;

  /// Vrai tant que la dernière flèche reçue est une répétition automatique.
  static bool get isRepeating => _repeating;

  static final Set<LogicalKeyboardKey> _arrows = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  /// Branché une fois au démarrage. Le gestionnaire ne consomme jamais rien :
  /// il regarde passer les touches, il ne les retient pas.
  static void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_observe);
  }

  static bool _observe(KeyEvent event) {
    if (_arrows.contains(event.logicalKey)) {
      _repeating = event is KeyRepeatEvent;
    }
    return false;
  }

  /// Une flèche qui ne vient pas du clavier arrive (un pas du trackpad de la
  /// Siri Remote, voir [TvTouchpad]) : ce n'est pas la répétition d'une touche
  /// tenue, même si la dernière vraie flèche en était une.
  static void noteFreshPress() => _repeating = false;

  @visibleForTesting
  static void debugReset() {
    _repeating = false;
    TvDirectionalFocusAction._lastMove = null;
  }
}

/// Le déplacement du focus aux flèches, sur un téléviseur.
///
/// Remplace [DirectionalFocusAction] à la racine de l'app. Trois différences, et
/// hors téléviseur aucune :
///
/// - la flèche maintenue est régulée, voir [TvKeyRepeat] ;
/// - gauche et droite ne quittent jamais la ligne. Au bout d'une rangée ou
///   d'une ligne de grille, Flutter cherche « quelque chose à droite » n'importe
///   où sur l'écran : l'avatar du compte dans l'en-tête, une affiche d'une autre
///   rangée qui dépasse plus loin. Le focus sautait alors à l'autre bout de
///   l'écran, et l'on ne savait plus où l'on était. Ici, sans rien sur la même
///   ligne, le focus reste où il est — sauf entre les volets d'un
///   [TvFocusPanes], où le passage est voulu ;
/// - haut et bas, quand plus rien ne peut prendre le focus, font défiler la
///   page : voir [TvFocusScroll.scrollPast].
class TvDirectionalFocusAction extends DirectionalFocusAction {
  TvDirectionalFocusAction();

  static DateTime? _lastMove;

  @override
  void invoke(DirectionalFocusIntent intent) {
    if (!TvMode.isTv) {
      _lastMove = DateTime.now();
      super.invoke(intent);
      return;
    }
    if (TvKeyRepeat.isRepeating) {
      final now = DateTime.now();
      final last = _lastMove;
      if (last != null && now.difference(last) < TvKeyRepeat.repeatInterval) {
        return;
      }
      _lastMove = now;
    } else {
      _lastMove = DateTime.now();
    }

    final direction = intent.direction;
    final current = primaryFocus;
    if (current == null ||
        current.context == null ||
        current is FocusScopeNode ||
        (direction != TraversalDirection.left &&
            direction != TraversalDirection.right)) {
      super.invoke(intent);
      // Le focus demandé ne se pose qu'à la microtâche suivante.
      FocusManager.instance.applyFocusChangesIfNeeded();
      if (identical(primaryFocus, current) && current != null) {
        TvFocusScroll.scrollPast(current, direction);
      }
      return;
    }

    final onLine = StepTarget.nextOnLine(current, direction);
    final panes = TvFocusPanes.maybeOf(current);
    final target = panes == null
        ? onLine
        : panes.next(current, direction, onLine: onLine);
    if (target == null) return;
    TvFocusEntries.requestFocus(
      target,
      alignmentPolicy: direction == TraversalDirection.left
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }
}
