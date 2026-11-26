import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_motion.dart';

/// Le fond animé d'un écran du Rétro : il respire derrière le texte, lentement,
/// pour que l'écran vive même quand rien n'y arrive plus.
///
/// Peint, sans image ni flou (un flou se recalcule à chaque image, et c'est ce
/// qu'un téléviseur ne tient pas). Une seule animation en boucle par écran,
/// dans sa propre couche de peinture. Sous « réduire les animations » ou en
/// mode léger, le fond reste fixe.
sealed class RetroAmbient {
  const RetroAmbient();
}

/// Trois halos colorés qui dérivent.
final class RetroOrbs extends RetroAmbient {
  const RetroOrbs(this.colors);
  final List<Color> colors;
}

/// Trois bandeaux de texte qui défilent en biais, comme une affiche.
final class RetroBands extends RetroAmbient {
  const RetroBands(this.text);
  final String text;
}

/// Des rayons qui tournent derrière l'affiche du n°1.
final class RetroRays extends RetroAmbient {
  const RetroRays();
}

/// Des ondes qui partent d'un point.
final class RetroRings extends RetroAmbient {
  const RetroRings(this.center);
  final Alignment center;
}

/// Une trame de points qui glisse dans un coin.
final class RetroDots extends RetroAmbient {
  const RetroDots();
}

class RetroAmbientLayer extends StatefulWidget {
  const RetroAmbientLayer(
      {super.key, required this.ambient, required this.ink});

  final RetroAmbient ambient;

  /// L'encre de l'écran : bandeaux, rayons, ondes et points s'y dessinent.
  final Color ink;

  @override
  State<RetroAmbientLayer> createState() => _RetroAmbientLayerState();
}

class _RetroAmbientLayerState extends State<RetroAmbientLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: RetroMotion.ambient);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Même question que RetroMotion.still, posée ici en clair pour la garde
    // des animations sans fin (ADR-0101).
    if (AppMotion.reduced(context)) {
      // Une pose plutôt que le point de départ : les halos ne s'empilent pas.
      _loop.value = 0.3;
    } else {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(
            ambient: widget.ambient,
            ink: widget.ink,
            loop: _loop,
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.ambient,
    required this.ink,
    required this.loop,
  }) : super(repaint: loop);

  final RetroAmbient ambient;
  final Color ink;
  final Animation<double> loop;

  TextPainter? _band;

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value;
    switch (ambient) {
      case RetroOrbs(:final colors):
        _orbs(canvas, size, t, colors);
      case RetroBands(:final text):
        _bands(canvas, size, t, text);
      case RetroRays():
        _rays(canvas, size, t);
      case RetroRings(:final center):
        _rings(canvas, size, t, center);
      case RetroDots():
        _dots(canvas, size, t);
    }
  }

  void _orbs(Canvas canvas, Size size, double t, List<Color> colors) {
    const anchors = [Offset(0.05, 0.1), Offset(0.8, 0.85), Offset(0.85, 0.05)];
    const radii = [0.75, 0.65, 0.5];
    final turn = 2 * math.pi * t;
    for (var i = 0; i < colors.length && i < anchors.length; i++) {
      final drift = Offset(
        math.sin(turn + i * 2.1) * 0.08,
        math.cos(turn * (i.isEven ? 1 : -1) + i) * 0.08,
      );
      final center = Offset(
        (anchors[i].dx + drift.dx) * size.width,
        (anchors[i].dy + drift.dy) * size.height,
      );
      final radius =
          size.longestSide * radii[i] * (1 + 0.12 * math.sin(turn * 2 + i));
      final paint = Paint()
        ..shader =
            RadialGradient(colors: [colors[i], colors[i].withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _bands(Canvas canvas, Size size, double t, String text) {
    final fontSize = size.shortestSide * 0.15;
    final band = _band ??= TextPainter(
      text: TextSpan(
        text: List.filled(8, '$text · ').join(),
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          color: ink.withValues(alpha: 0.13),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -fontSize * 0.03,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final period = band.width / 2;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-10 * math.pi / 180);
    for (var i = 0; i < 3; i++) {
      final y = (i - 1) * size.height * 0.36 - band.height / 2;
      final direction = i.isEven ? -1 : 1;
      // Deux tours de boucle pour la bande du milieu : elles ne glissent pas
      // ensemble.
      final shift = (t * (i == 1 ? 2 : 1) * period) % period;
      final x = -size.longestSide - (direction < 0 ? shift : period - shift);
      band.paint(canvas, Offset(x, y));
      band.paint(canvas, Offset(x + band.width, y));
    }
    canvas.restore();
  }

  void _rays(Canvas canvas, Size size, double t) {
    final center = Offset(size.width / 2, size.height * 0.62);
    final radius = size.longestSide;
    const count = 24;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [ink.withValues(alpha: 0.16), ink.withValues(alpha: 0)],
        stops: const [0, 0.55],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    final path = Path();
    final start = 2 * math.pi * t;
    for (var i = 0; i < count; i++) {
      final a = start + i * 2 * math.pi / count;
      final b = a + 2 * math.pi / count / 3;
      path
        ..moveTo(center.dx, center.dy)
        ..lineTo(
            center.dx + radius * math.cos(a), center.dy + radius * math.sin(a))
        ..lineTo(
            center.dx + radius * math.cos(b), center.dy + radius * math.sin(b))
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  void _rings(Canvas canvas, Size size, double t, Alignment at) {
    final center = at.alongSize(size);
    final maxRadius = size.longestSide * 0.7;
    for (var i = 0; i < 4; i++) {
      // Une onde toutes les six secondes environ, quatre à la fois.
      final phase = (t * 3 + i / 4) % 1;
      final eased = RetroMotion.out.transform(phase);
      canvas.drawCircle(
        center,
        maxRadius * (0.1 + 1.2 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ink.withValues(alpha: 0.35 * (1 - phase)),
      );
    }
  }

  void _dots(Canvas canvas, Size size, double t) {
    final cell = size.shortestSide * 0.06;
    final shift = (t * 6 * cell) % cell;
    final corner = Offset(size.width * 0.85, 0);
    final reach = size.longestSide * 0.7;
    final paint = Paint();
    for (var y = -cell + shift; y < size.height; y += cell) {
      for (var x = -cell + shift; x < size.width; x += cell) {
        final fade = 1 - ((Offset(x, y) - corner).distance / reach);
        if (fade <= 0) continue;
        paint.color = ink.withValues(alpha: 0.2 * fade);
        canvas.drawCircle(Offset(x, y), 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.ambient != ambient || old.ink != ink;
}
