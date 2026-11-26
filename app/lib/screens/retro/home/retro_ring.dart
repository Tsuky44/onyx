import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/app_motion.dart';

/// L'anneau autour de l'avatar tant que le Rétro n'a pas été ouvert : un
/// cercle aux couleurs du Rétro qui tourne lentement. Il se dessine autour
/// de l'enfant, sans changer sa place : l'en-tête ne bouge pas quand il
/// apparaît ou disparaît.
///
/// Sous « réduire les animations » ou en mode léger, il reste immobile.
class RetroRing extends StatefulWidget {
  const RetroRing({
    super.key,
    required this.active,
    required this.diameter,
    required this.child,
  });

  final bool active;

  /// Le diamètre de l'anneau, centré sur l'enfant.
  final double diameter;
  final Widget child;

  /// Les couleurs du Rétro : le bleu d'Onyx et les encres des écrans.
  static const colors = [
    Color(0xFF0A84FF),
    Color(0xFFE7B8FF),
    Color(0xFFFFB86B),
    Color(0xFF7FF0DC),
    Color(0xFF0A84FF),
  ];

  @override
  State<RetroRing> createState() => _RetroRingState();
}

class _RetroRingState extends State<RetroRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  void _sync() {
    // Posée en clair pour la garde des animations sans fin (ADR-0101).
    if (widget.active && !AppMotion.reduced(context)) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RetroRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RingPainter(turn: _turn, diameter: widget.diameter),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.turn, required this.diameter})
      : super(repaint: turn);

  final Animation<double> turn;
  final double diameter;

  @override
  void paint(Canvas canvas, Size size) {
    final circle =
        Rect.fromCircle(center: size.center(Offset.zero), radius: diameter / 2);
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = SweepGradient(
          colors: RetroRing.colors,
          transform: GradientRotation(turn.value * 2 * math.pi),
        ).createShader(circle),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.diameter != diameter;
}
