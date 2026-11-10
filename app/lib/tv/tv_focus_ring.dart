import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/lite_mode.dart';

/// L'anneau de focus d'Onyx : un trait blanc fin qui épouse l'arrondi de ce
/// qu'il entoure (ADR-0008, ADR-0111).
///
/// Il remplace le liseré bleu de 3 px et son halo : posé *dans* l'affiche, il
/// mangeait l'image sur ses bords, et les rangées le coupaient en haut et en
/// bas dès que l'affiche grandissait. Blanc, plus fin et, sur une affiche,
/// détaché d'elle par un jour, il se lit du canapé sans écraser l'image.
///
/// La pile ne dépend pas de [visible] : basculer l'enfant entre « enveloppé »
/// et « nu » reconstruirait tout son sous-arbre, et chaque affiche relancerait
/// son fondu à chaque pas de focus.
class TvFocusRing extends StatelessWidget {
  const TvFocusRing({
    super.key,
    required this.visible,
    required this.borderRadius,
    this.outset = false,
    required this.child,
  });

  final bool visible;

  /// L'arrondi de l'enfant. En [outset], l'anneau l'agrandit de [reach] pour
  /// rester parallèle au bord.
  final BorderRadius borderRadius;

  /// Vrai pour tracer l'anneau autour de l'enfant, à [gap] de son bord : la
  /// place d'une affiche, dont l'image doit rester entière. Ce débord de
  /// [reach] doit être réservé par ce qui la contient ([PosterCard.railRoom]).
  ///
  /// Faux, il se pose sur le bord intérieur : aucun débord, donc rien à
  /// réserver autour d'un bouton ou d'une ligne de réglages.
  final bool outset;

  final Widget child;

  static const double width = 2.5;
  static const double gap = 2.5;

  /// De combien un anneau [outset] dépasse de l'enfant, de chaque côté.
  static const double reach = gap + width;

  @override
  Widget build(BuildContext context) {
    final inset = outset ? -reach : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        // Par-dessus l'enfant plutôt qu'autour, dans la mise en page : une
        // bordure dans le layout décalerait chaque voisin à chaque pas.
        if (visible)
          Positioned(
            left: inset,
            top: inset,
            right: inset,
            bottom: inset,
            child: IgnorePointer(
              child: _Ring(
                // Le voile resterait sur l'image d'une affiche : l'anneau
                // extérieur s'en passe, il se lit déjà sur le fond.
                wash: !outset,
                borderRadius: outset
                    ? borderRadius + BorderRadius.circular(reach)
                    : borderRadius,
              ),
            ),
          ),
      ],
    );
  }
}

/// Le trait lui-même, qui s'allume en fondu à son arrivée.
///
/// Il s'éteint net : au pas suivant, le focus est déjà ailleurs, et deux
/// anneaux à moitié visibles diraient deux endroits à la fois.
class _Ring extends StatelessWidget {
  const _Ring({required this.borderRadius, required this.wash});

  final BorderRadius borderRadius;
  final bool wash;

  @override
  Widget build(BuildContext context) {
    final still = LiteScope.of(context) ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : AppMotion.focus,
      curve: Curves.easeOutCubic,
      // Deux traits : le blanc, et un filet sombre juste dedans. Le blanc seul
      // disparaissait sur une image claire ou un bouton blanc ; le filet le
      // détache de n'importe quel fond. Le voile clair à l'intérieur dit
      // « ici » même quand l'œil ne trouve pas le trait.
      builder: (context, t, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: AppColors.focus.withValues(alpha: t),
            width: TvFocusRing.width,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TvFocusRing.width),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _inner(borderRadius),
              color: wash ? Colors.white.withValues(alpha: 0.08 * t) : null,
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.55 * t),
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// L'arrondi juste à l'intérieur du trait blanc, pour que le filet sombre
  /// lui reste parallèle.
  static BorderRadius _inner(BorderRadius r) {
    Radius shrink(Radius x) => Radius.elliptical(
          (x.x - TvFocusRing.width).clamp(0, double.infinity),
          (x.y - TvFocusRing.width).clamp(0, double.infinity),
        );
    return BorderRadius.only(
      topLeft: shrink(r.topLeft),
      topRight: shrink(r.topRight),
      bottomLeft: shrink(r.bottomLeft),
      bottomRight: shrink(r.bottomRight),
    );
  }
}
