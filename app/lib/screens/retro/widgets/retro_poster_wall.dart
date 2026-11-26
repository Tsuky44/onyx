import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../models/retro.dart';
import '../../../theme/app_motion.dart';
import '../widgets/retro_entrance.dart';
import 'retro_ambient.dart';
import 'retro_poster.dart';
import 'retro_type.dart';

/// Le mur d'affiches de l'ouverture : les titres de l'année en colonnes
/// inclinées qui défilent lentement, l'une vers le haut, la suivante vers le
/// bas. Il remplit le côté droit d'un écran large et le haut d'un téléphone,
/// et se fond dans le fond de l'écran du côté du texte.
///
/// Une seule animation en boucle pour tout le mur ; chaque colonne est sa
/// propre couche de peinture et ne fait que glisser. Sous « réduire les
/// animations » ou en mode léger, le mur reste fixe.
class RetroPosterWall extends StatefulWidget {
  const RetroPosterWall({
    super.key,
    required this.titles,
    required this.serverBaseUrl,
    required this.background,
    required this.glows,
  });

  final List<RetroTitle> titles;
  final String? serverBaseUrl;

  /// La couleur de l'écran, dans laquelle le mur se fond.
  final Color background;

  /// Les halos qui dérivent sous le texte.
  final List<Color> glows;

  @override
  State<RetroPosterWall> createState() => _RetroPosterWallState();
}

class _RetroPosterWallState extends State<RetroPosterWall>
    with SingleTickerProviderStateMixin {
  /// Une colonne parcourt une fois ses affiches en ce temps-là, à vitesse 1.
  static const _period = Duration(seconds: 48);

  /// Chaque colonne a son allure, pour que le mur ne glisse pas d'un bloc.
  static const _speeds = [1.0, 0.85, 1.15, 0.92];

  late final AnimationController _loop =
      AnimationController(vsync: this, duration: _period);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // La même question que RetroMotion.still, posée en clair pour la garde
    // des animations sans fin (ADR-0101).
    if (!AppMotion.reduced(context)) _loop.repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = RetroUnits.of(context);
    final size = units.size;
    final titles = widget.titles;
    final background = widget.background;
    final glows = RetroAmbientLayer(
      ambient: RetroOrbs(widget.glows),
      ink: background,
    );
    if (titles.isEmpty || size.isEmpty) return glows;

    final landscape = units.landscape;
    // Le mur est un grand rectangle incliné, plus haut que l'écran pour que
    // ses bords n'apparaissent jamais : à droite en paysage, en haut sinon.
    final Rect box = landscape
        ? Rect.fromLTWH(size.width * 0.46, -size.height * 0.45,
            size.width * 0.64, size.height * 1.9)
        : Rect.fromLTWH(-size.width * 0.25, -size.height * 0.24,
            size.width * 1.5, size.height * 0.95);
    const columns = 4;
    final gap = size.width * (landscape ? 0.02 : 0.035);
    final posterWidth = (box.width - gap * (columns - 1)) / columns;
    final step = posterWidth * 1.5 + gap;
    // Une colonne enchaîne ses affiches assez de fois pour couvrir le mur
    // pendant tout un tour.
    final cycle = step * titles.length;
    final repeats = ((box.height + cycle) / cycle).ceil() + 1;

    final enter = RetroEntrance.slice(
      context,
      delay: const Duration(milliseconds: 200),
      duration: const Duration(milliseconds: 1600),
    );

    Widget column(int index) {
      final order = [
        for (var r = 0; r < repeats; r++)
          for (var i = 0; i < titles.length; i++)
            titles[(i + index * 2) % titles.length],
      ];
      final speed = _speeds[index % _speeds.length];
      final upward = index.isEven;
      return SizedBox(
        width: posterWidth,
        height: box.height,
        child: AnimatedBuilder(
          animation: _loop,
          child: RepaintBoundary(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final title in order)
                    Padding(
                      padding: EdgeInsets.only(bottom: gap),
                      child: RetroPoster(
                        posterUrl: title.posterUrl,
                        title: title.title,
                        serverBaseUrl: widget.serverBaseUrl,
                        width: posterWidth,
                        showTitle: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
          builder: (context, child) {
            final phase = (_loop.value * speed + index * 0.37) % 1;
            final travelled = (upward ? phase : 1 - phase) * cycle;
            return Transform.translate(
              offset: Offset(0, -travelled),
              child: child,
            );
          },
        ),
      );
    }

    final Gradient fade = landscape
        // Opaque au bord gauche du mur, transparent de part et d'autre : les
        // halos restent visibles sous le texte.
        ? LinearGradient(
            colors: [
              background.withValues(alpha: 0),
              background,
              background.withValues(alpha: 0),
            ],
            stops: const [0.33, 0.45, 0.7],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [background.withValues(alpha: 0), background],
            stops: const [0.25, 0.62],
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        glows,
        Positioned.fromRect(
          rect: box,
          child: AnimatedBuilder(
            animation: enter,
            builder: (context, child) {
              final hidden = 1 - enter.value;
              return Opacity(
                opacity: enter.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: landscape
                      ? Offset(size.width * 0.14 * hidden, 0)
                      : Offset(0, -size.height * 0.1 * hidden),
                  child: child,
                ),
              );
            },
            child: Transform.rotate(
              angle: -11 * math.pi / 180,
              child: Row(
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    column(i),
                  ],
                ],
              ),
            ),
          ),
        ),
        DecoratedBox(decoration: BoxDecoration(gradient: fade)),
      ],
    );
  }
}
