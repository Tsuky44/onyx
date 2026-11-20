import 'package:flutter/material.dart';

/// L'image d'un bandeau sous la barre du haut du téléphone (ADR-0144) : elle
/// garde le cadrage qu'elle avait sous la barre, un peu plus bas, et sort du
/// noir de la page par le haut, juste au-dessus des visages.
///
/// Posée en entier derrière la barre, elle se grossissait pour couvrir la
/// hauteur en plus, et les visages remontaient sous la marque et le compte.
/// Prolongée au-dessus en miroir flou, elle laissait une tache trouble sous
/// eux. Au-dessus d'elle, rien que la page : la marque et le compte s'y posent
/// sans verre.
class HeroTopFade extends StatelessWidget {
  const HeroTopFade({super.key, required this.top, required this.image});

  /// La hauteur laissée à la page au-dessus de l'image : la barre d'état et
  /// la barre du haut.
  final double top;

  final Widget image;

  /// L'image descend un peu sous la barre, à la même taille : les têtes, en
  /// haut des affiches, passent sous le fondu au lieu d'y rester. À 24 points,
  /// le noir descendait trop bas sous la barre.
  static const double shift = 12;

  /// La hauteur sur laquelle l'image sort du noir : courte, pour qu'il ne
  /// prenne que le haut des têtes et finisse vers le front. Pas de flou : posé
  /// sur l'arête, il brouillait les visages.
  static const double fade = 40;

  @override
  Widget build(BuildContext context) {
    if (top <= 0) return image;
    return LayoutBuilder(
      builder: (context, constraints) {
        // La taille qu'elle avait sous la barre : le même cadrage, et le bas,
        // déjà fondu dans la page, sort du bandeau.
        final height = constraints.maxHeight - top;
        final imageTop = top + shift;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: imageTop,
              left: 0,
              right: 0,
              height: height,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  final end = (fade / rect.height).clamp(0.0, 1.0);
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Color(0x00000000),
                      Color(0x99000000),
                      Color(0xFF000000),
                    ],
                    stops: [0, end * 0.5, end],
                  ).createShader(rect);
                },
                // Le masque ne couvre que le cadre de l'image. Le zoom lent du
                // fond vivant (ADR-0154) la grossit au-delà : la bande qui
                // dépassait au-dessus restait en clair sur le noir, avant le
                // fondu.
                child: ClipRect(child: image),
              ),
            ),
          ],
        );
      },
    );
  }
}
