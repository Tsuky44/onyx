import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'glass_chrome.dart';

/// L'image d'un bandeau prolongée sous la barre du haut du téléphone
/// (ADR-0144), comme iOS 26 prolonge un contenu sous ses barres.
///
/// L'image nette garde le cadrage qu'elle avait sous la barre : posée en
/// entier derrière elle, elle se grossissait pour couvrir la hauteur en plus,
/// et les visages remontaient sous la pilule de la marque et le rond du
/// compte. Au-dessus, sur [extendTop], le haut de l'image en miroir, très flou
/// et assombri : la barre se pose sur une matière calme, de la couleur de
/// l'affiche, et l'image nette s'y fond par le haut, sans arête.
///
/// Sans flou ([glassBlurs] : mode léger, webOS), pas de miroir, qui
/// montrerait l'image à l'envers et nette : un voile sombre, dans lequel
/// l'image se fond de la même façon.
class BackdropExtension extends StatelessWidget {
  const BackdropExtension({
    super.key,
    required this.extendTop,
    required this.image,
  });

  /// La hauteur du prolongement, au-dessus de l'image nette.
  final double extendTop;

  /// L'image du bandeau, construite à chaque usage : nette dessous, en miroir
  /// et floue au-dessus. La même adresse, donc le même cache.
  final Widget Function() image;

  /// La hauteur sur laquelle l'image nette se fond dans le prolongement.
  static const double blend = 48;

  /// Assez flou pour qu'aucun trait de l'image ne se lise sous la barre.
  static const double sigma = 28;

  @override
  Widget build(BuildContext context) {
    if (extendTop <= 0) return image();
    final blurs = glassBlurs(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sharpHeight = constraints.maxHeight - extendTop;
        final zone = extendTop + blend;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (blurs)
              Positioned(
                key: const ValueKey('backdrop-extension'),
                top: 0,
                left: 0,
                right: 0,
                height: zone,
                child: RepaintBoundary(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: sigma,
                        sigmaY: sigma,
                        tileMode: TileMode.mirror,
                      ),
                      // Le miroir au-dessus de la ligne, l'image elle-même
                      // dessous : le flou passe de l'un à l'autre sans couture.
                      child: Stack(
                        children: [
                          Positioned(
                            top: extendTop - sharpHeight,
                            height: sharpHeight,
                            left: 0,
                            right: 0,
                            child: Transform.flip(flipY: true, child: image()),
                          ),
                          Positioned(
                            top: extendTop,
                            height: sharpHeight,
                            left: 0,
                            right: 0,
                            child: image(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: extendTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Color(0x00000000), Color(0xFF000000)],
                  stops: [0, (blend / rect.height).clamp(0.0, 1.0)],
                ).createShader(rect),
                child: image(),
              ),
            ),
            // Un voile sombre sur le prolongement : l'heure et le verre de la
            // barre s'y lisent, quelle que soit la couleur de l'affiche.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: zone,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background
                            .withValues(alpha: blurs ? 0.6 : 0.9),
                        AppColors.background
                            .withValues(alpha: blurs ? 0.3 : 0.7),
                        AppColors.background.withValues(alpha: 0),
                      ],
                      stops: [0, extendTop / zone, 1],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
