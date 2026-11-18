import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Lisse la molette de la souris sur le web.
///
/// Flutter web avance d'un cran de molette d'un seul coup (une centaine de
/// pixels), sans inertie : sur une grille d'affiches, c'est ce qui donne la
/// saccade. Ici chaque cran déplace une *cible*, et la position glisse vers
/// elle en une fraction de seconde ; les crans qui s'enchaînent s'additionnent
/// dans la même cible au lieu de redémarrer une animation. Voir ADR-0151.
///
/// Ce qui n'est pas touché, parce que Flutter le fait déjà bien ou qu'un autre
/// widget s'en charge :
/// * le trackpad, dont les deltas sont fins et déjà fluides ([isWheelNotch]) ;
/// * Ctrl / Cmd / Maj (zoom de la grille, zoom du navigateur, défilement
///   horizontal) ;
/// * le défilement natif : le widget est inerte hors du web.
///
/// Enveloppe une zone défilante comme [MiddleClickAutoScroll].
class SmoothWheelScroll extends StatefulWidget {
  const SmoothWheelScroll({
    super.key,
    required this.details,
    required this.child,
    bool? enabled,
  }) : enabled = enabled ?? kIsWeb;

  final ScrollableDetails details;
  final Widget child;
  final bool enabled;

  /// Durée caractéristique du glissement : la position rattrape environ 63 %
  /// de l'écart restant à chaque [tau].
  static const Duration tau = Duration(milliseconds: 85);

  /// Un cran de molette arrive en gros deltas entiers (100 sous Chrome, 120
  /// sous Windows) ; un trackpad envoie une rafale de petites valeurs, souvent
  /// fractionnaires. En dessous de ce seuil, on laisse Flutter faire.
  static const double notchThreshold = 40;

  /// `true` si [delta] ressemble à un cran de molette plutôt qu'à un trackpad.
  @visibleForTesting
  static bool isWheelNotch(double delta) =>
      delta.abs() >= notchThreshold && delta == delta.roundToDouble();

  @override
  State<SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

class _SmoothWheelScrollState extends State<SmoothWheelScroll>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  ScrollPosition? _position;
  double _target = 0;
  // Dernière valeur posée par nous : si la position en diffère, quelqu'un
  // d'autre (glisser, barre de défilement, clavier) a pris la main.
  double _lastSet = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  ScrollPosition? _positionFor() {
    final controller = widget.details.controller;
    if (controller == null || controller is PageController) return null;
    if (!controller.hasClients) return null;
    final axis = axisDirectionToAxis(widget.details.direction);
    for (final position in controller.positions) {
      if (position.axis == axis) return position;
    }
    return null;
  }

  // Flutter enregistre son propre gestionnaire de molette plus profondément que
  // [ScrollBehavior.buildScrollbar] : il passe toujours le premier et déplace la
  // position d'un bloc (le résolveur l'exécute en fin de passe). On ne peut donc pas le devancer. On le laisse faire,
  // puis on rembobine juste après, avant tout rendu, et on
  // fait glisser la position vers l'endroit où il l'avait envoyée. Flutter garde
  // ainsi la décision (quelle zone défile, jusqu'où, dans quel axe).
  double? _jumpBefore;

  bool _onNotification(ScrollNotification n) {
    // `depth == 0` : seule la notification de la zone qu'on enveloppe, pas
    // celle d'une zone imbriquée qui remonterait jusqu'ici.
    if (n is ScrollUpdateNotification &&
        n.depth == 0 &&
        n.dragDetails == null &&
        n.scrollDelta != null &&
        n.metrics.axis == axisDirectionToAxis(widget.details.direction)) {
      _jumpBefore = n.metrics.pixels - n.scrollDelta!;
      scheduleMicrotask(() => _jumpBefore = null);
    }
    return false;
  }

  void _onSignal(PointerSignalEvent event) {
    if (!widget.enabled || event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isShiftPressed) {
      return;
    }
    final position = _positionFor();
    if (position == null) return;
    final delta = position.axis == Axis.vertical
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (!SmoothWheelScroll.isWheelNotch(delta)) return;

    // Les gestionnaires de la passe tournent tous avant que le résolveur
    // exécute celui de Flutter : la notification de saut n'existe pas encore.
    // Une micro-tâche passe après elle et avant le prochain rendu.
    scheduleMicrotask(() => _smooth(position, delta));
  }

  void _smooth(ScrollPosition position, double delta) {
    final before = _jumpBefore;
    _jumpBefore = null;
    if (before == null || !mounted || !position.hasPixels) return;
    final moved = position.pixels;
    final from = _ticker.isActive && _position == position ? _target : before;
    // Flutter a déjà borné son saut ; on borne le cumul de la même façon.
    _target = (from + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _position = position;
    if (moved != before) position.jumpTo(before);
    _lastSet = position.pixels;
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final position = _position;
    if (position == null ||
        !position.hasPixels ||
        (position.pixels - _lastSet).abs() > 1) {
      _ticker.stop();
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final remaining = _target - position.pixels;
    if (remaining.abs() < 0.5) {
      position.jumpTo(_target);
      _ticker.stop();
      return;
    }
    final k = 1 - math.exp(-dt / (SmoothWheelScroll.tau.inMicroseconds / 1e6));
    final next = position.pixels + remaining * k.clamp(0.0, 1.0);
    position.jumpTo(next);
    _lastSet = position.pixels;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _onSignal,
        child: widget.child,
      ),
    );
  }
}
