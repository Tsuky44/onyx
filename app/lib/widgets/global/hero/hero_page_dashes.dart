import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';

/// Les traits du carrousel d'accueil, un par diapositive (ADR-0147). Celui de
/// la diapositive affichée est plus long et se remplit à mesure qu'elle
/// passe : on voit quand la suivante viendra.
///
/// Des repères au toucher et à la souris, pas des boutons : à la télécommande
/// le bandeau change de diapositive aux flèches (Droite au bord), et ces
/// traits restent volontairement hors du parcours.
class HeroPageDashes extends StatelessWidget {
  const HeroPageDashes({
    super.key,
    required this.count,
    required this.current,
    required this.progress,
    required this.onTap,
  });

  static const double activeWidth = 24;
  static const double _width = 6;
  static const double _height = 3;

  final int count;
  final int current;

  /// La part écoulée de la diapositive affichée, de 0 à 1.
  final Animation<double> progress;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (index) {
        final active = index == current;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
            child: AnimatedContainer(
              duration: AppMotion.move(context),
              curve: AppMotion.curve,
              width: active ? activeWidth : _width,
              height: _height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
              child: active
                  ? AnimatedBuilder(
                      animation: progress,
                      builder: (context, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress.value.clamp(0.0, 1.0),
                        child: const ColoredBox(color: AppColors.textPrimary),
                      ),
                    )
                  : null,
            ),
          ),
        );
      }),
    );
  }
}
