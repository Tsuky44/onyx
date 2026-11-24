import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../../l10n/tr.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/lite_mode.dart';
import 'onyx_chrome_theme.dart';

/// L'attente du lecteur (ADR-0140) : un anneau blanc et fin dont la tête
/// tourne et dont la traîne s'efface, posé sur une ombre douce pour se lire
/// sur un plan clair comme sur le noir du démarrage.
///
/// Il remplace le cercle bleu de Material, d'une autre couleur que tout le
/// chrome (blanc sur l'image, verre, ADR-0130), et centré sur l'écran quand le
/// bouton lecture d'un écran tenu en main est à 42 % de sa hauteur.
///
/// Sous « réduire les animations » et en mode léger, l'anneau ne tourne pas :
/// une animation sans fin redessine sa zone à chaque image (ADR-0101). La
/// traîne dit toujours qu'on attend.
class OnyxLoadingRing extends StatefulWidget {
  const OnyxLoadingRing({super.key, this.size = defaultSize});

  /// Le diamètre : celui du disque de lecture/pause qu'il remplace sur un
  /// écran tenu en main, un peu moins que sa cible de 78.
  static const double defaultSize = 52;

  final double size;

  @override
  State<OnyxLoadingRing> createState() => _OnyxLoadingRingState();
}

class _OnyxLoadingRingState extends State<OnyxLoadingRing>
    with SingleTickerProviderStateMixin {
  /// Un tour : celui du balayage des cartes (`AppMotion.sweep`).
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: AppMotion.sweep,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = AppMotion.reduced(context) || LiteScope.of(context);
    if (still) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Chargement'),
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _turn,
            builder: (context, _) => CustomPaint(
              painter: OnyxLoadingRingPainter(turn: _turn.value),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le dessin de [OnyxLoadingRing], à la fraction [turn] de son tour.
class OnyxLoadingRingPainter extends CustomPainter {
  const OnyxLoadingRingPainter({required this.turn});

  final double turn;

  /// L'épaisseur du trait, rapportée au diamètre.
  static const double strokeRatio = 0.075;

  /// La longueur de la traîne, en fraction du tour.
  static const double sweep = 0.78;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * strokeRatio;
    final rect = (Offset.zero & size).deflate(stroke);
    final centre = rect.center;
    final radius = rect.width / 2;

    // L'ombre d'abord : sans elle, le blanc disparaît sur un ciel.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.4
        ..color = OnyxChromeTheme.glassShadow.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.6),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = OnyxChromeTheme.progressTrack,
    );

    final start = -math.pi / 2 + turn * 2 * math.pi;
    const length = sweep * 2 * math.pi;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(start);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawArc(
      rect,
      0,
      length,
      false,
      // Bout plat : un bout rond déborderait sous zéro, où le dégradé reprend
      // sa dernière couleur, et la traîne finirait sur un point blanc.
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = const SweepGradient(
          endAngle: length,
          colors: [Color(0x00FFFFFF), Colors.white],
        ).createShader(rect),
    );
    // La tête, ronde.
    canvas.drawCircle(
      centre + Offset(math.cos(length), math.sin(length)) * radius,
      stroke / 2,
      Paint()..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OnyxLoadingRingPainter old) => old.turn != turn;
}
