import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../widgets/global/glass_chrome.dart';

/// La recherche du bureau : un voile de verre qui descend sur la page qu'on
/// regarde, sous l'en-tête où l'on tape (ADR-0139).
///
/// La route n'est pas opaque : la page d'avant reste dessous, floutée, et on
/// la retrouve telle quelle en refermant. L'ancienne page de résultats la
/// remplaçait, avec sa barre « Recherche » et une flèche retour étrangères
/// à l'en-tête.
///
/// Elle ne prend pas le focus en s'ouvrant : il reste dans le champ de
/// l'en-tête, où l'on tape.
class DesktopSearchRoute<T> extends PageRoute<T> {
  DesktopSearchRoute({required this.builder, super.settings})
      : super(requestFocus: false);

  final WidgetBuilder builder;

  /// Le flou de la page dessous. Assez fort pour que ses affiches ne
  /// soient plus que des taches de couleur : la grille des résultats doit
  /// être la seule qu'on lise.
  static const double blurSigma = 28;

  /// La hauteur dont le contenu descend en s'ouvrant : de quoi sentir qu'il
  /// vient de l'en-tête, pas assez pour que l'œil quitte le champ.
  static const double drop = 10;

  @override
  Duration get transitionDuration => AppMotion.emphasis;

  @override
  Duration get reverseTransitionDuration => AppMotion.standard;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      _Veil(child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.curve.flipped,
    );
    final fading = FadeTransition(opacity: eased, child: child);
    if (AppMotion.reduced(context)) return fading;
    return AnimatedBuilder(
      animation: eased,
      child: fading,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -drop * (1 - eased.value)),
        child: child,
      ),
    );
  }
}

/// Le fond de la feuille : la page dessous floutée, puis assombrie. Là où le
/// verre ne floute pas ([glassBlurs] : mode léger, ADR-0086), le flou (une
/// passe de plus sur tout l'écran à chaque image) laisse place à un voile
/// presque opaque.
class _Veil extends StatelessWidget {
  const _Veil({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget backdrop = !glassBlurs(context)
        ? const ColoredBox(color: AppColors.searchVeilLite)
        : ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: DesktopSearchRoute.blurSigma,
                sigmaY: DesktopSearchRoute.blurSigma,
              ),
              child: const ColoredBox(color: AppColors.searchVeil),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [backdrop, child],
    );
  }
}
