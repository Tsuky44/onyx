import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Le tour du rond d'une bulle de saison : un filet pâle, et par-dessus, en
/// blanc, la part de la saison déjà vue. Rien de vu laisse le filet seul, tout
/// vu le ferme en cercle blanc.
///
/// [progress] va de 0 à 1. L'arc part du haut et tourne dans le sens des
/// aiguilles d'une montre ; quand la part change (un épisode vient d'être fini),
/// il glisse d'une valeur à l'autre, en fondu seulement sous « réduire les
/// animations ».
class SeasonProgressRing extends StatelessWidget {
  final double progress;
  final Widget child;

  const SeasonProgressRing({
    super.key,
    required this.progress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: AppMotion.fade(context, AppMotion.emphasis),
      curve: AppMotion.curve,
      builder: (_, value, child) => CustomPaint(
        painter: _RingPainter(value),
        child: child,
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  static const _stroke = 1.5;

  final double progress;

  const _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // Le trait est centré sur le cercle : on rentre d'une demi-épaisseur pour
    // qu'il reste dans la boîte, comme la bordure qu'il remplace.
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    canvas.drawOval(rect, paint..color = Colors.white.withValues(alpha: 0.08));
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint
        ..color = Colors.white
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
