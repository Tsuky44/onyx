import 'package:flutter/material.dart';

import '../../../../widgets/global/glass_chrome.dart';
import 'onyx_chrome_theme.dart';

/// Le verre des panneaux posés sur le film : les menus, les fenêtres de
/// question, le volet des onglets (ADR-0130).
///
/// Un fond sombre qui laisse deviner l'image, un filet clair, une ombre. Le
/// flou n'est qu'un plus ([GlassBlur]) : il disparaît en mode léger et sur les
/// téléviseurs LG, et le fond se densifie alors pour porter le texte seul.
/// Ce n'est pas le verre groupé que l'ADR-0048 a retiré du lecteur : chaque
/// panneau est ponctuel, ouvert à la demande, jamais posé sur le chrome au
/// repos.
class OnyxGlassPanel extends StatelessWidget {
  const OnyxGlassPanel({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(26)),
    this.outlined = true,
    this.elevated = true,
  });

  final Widget child;
  final BorderRadius radius;

  /// Faux pour un volet qui touche les bords de l'écran : un seul filet, en
  /// haut.
  final bool outlined;

  /// Faux pour un volet qui ne flotte pas : pas d'ombre portée.
  final bool elevated;

  static const double _sigma = 30;

  @override
  Widget build(BuildContext context) {
    final blurs = glassBlurs(context);
    final fill = blurs
        ? OnyxChromeTheme.glassSurface
        : OnyxChromeTheme.glassSurfaceDense;
    final panel = ClipRRect(
      borderRadius: radius,
      child: GlassBlur(
        sigma: _sigma,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            // Un filet d'un seul côté ne s'arrondit pas : le découpage
            // au-dessus donne déjà sa forme au volet.
            borderRadius: outlined ? radius : null,
            border: outlined
                ? Border.all(color: OnyxChromeTheme.glassBorder)
                : const Border(
                    top: BorderSide(color: OnyxChromeTheme.glassHairline),
                  ),
          ),
          child: child,
        ),
      ),
    );
    if (!elevated) return panel;
    // L'ombre est hors du découpage : dedans, elle serait rognée avec lui.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: OnyxChromeTheme.glassShadow,
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: panel,
    );
  }
}
