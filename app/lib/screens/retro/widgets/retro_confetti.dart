import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/retro_motion.dart';

/// Les confettis de la carte de fin : une gerbe qui part du bas, retombe et
/// s'éteint. Une seule fois par ouverture de l'écran ; rien sous « réduire
/// les animations » ou en mode léger.
class RetroConfetti extends StatefulWidget {
  const RetroConfetti({super.key, required this.colors});
  final List<Color> colors;

  /// Le temps que la carte arrive avant que la gerbe parte.
  static const Duration lead = Duration(milliseconds: 900);

  @override
  State<RetroConfetti> createState() => _RetroConfettiState();
}

class _RetroConfettiState extends State<RetroConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: RetroConfetti.lead + RetroMotion.confetti,
  );
  late final List<_Piece> _pieces = _launch(widget.colors);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = RetroMotion.still(context);
    if (!_still && !_clock.isAnimating && _clock.value == 0) _clock.forward();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  static List<_Piece> _launch(List<Color> colors) {
    // Une graine fixe : la même gerbe à chaque ouverture, et dans les tests.
    final random = math.Random(2026);
    return List.generate(110, (i) {
      return _Piece(
        x: 0.5 + (random.nextDouble() - 0.5) * 0.3,
        vx: (random.nextDouble() - 0.5) * 0.7,
        vy: -(0.85 + random.nextDouble() * 0.7),
        size: 4 + random.nextDouble() * 6,
        spin: (random.nextDouble() - 0.5) * 18,
        color: colors[i % colors.length],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(pieces: _pieces, clock: _clock),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.size,
    required this.spin,
    required this.color,
  });

  /// Départ, en part de la largeur ; vitesses en hauteurs d'écran par seconde.
  final double x;
  final double vx;
  final double vy;
  final double size;
  final double spin;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.clock})
      : super(repaint: clock);

  final List<_Piece> pieces;
  final AnimationController clock;

  /// La pesanteur, en hauteurs d'écran par seconde au carré.
  static const double _gravity = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final total = clock.duration!.inMicroseconds / 1e6;
    final lead = RetroConfetti.lead.inMicroseconds / 1e6;
    final age = clock.value * total - lead;
    if (age <= 0 || clock.isCompleted) return;
    final life = RetroMotion.confetti.inMicroseconds / 1e6;
    final fade = (1 - age / life).clamp(0.0, 1.0);
    final paint = Paint();
    for (final p in pieces) {
      final x = (p.x + p.vx * age) * size.width;
      final y = size.height * (1 + p.vy * age + _gravity * age * age / 2);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * age);
      paint.color = p.color.withValues(alpha: fade);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size / 2),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.pieces != pieces;
}
