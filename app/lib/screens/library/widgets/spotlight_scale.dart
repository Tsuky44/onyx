import 'package:material_ui/material_ui.dart';

import '../../../tv/tv_ui_scale.dart';

/// Le volet d'une page du bureau (bibliothèque, recherche) aux proportions de
/// celui de l'Apple TV (ADR-0156) : il se met en page sur la largeur d'un
/// téléviseur ([TvUiScale.designWidth]), puis grandit avec la fenêtre.
///
/// À taille réelle, sur un écran de 1920 px, il ne prenait qu'un quart de la
/// largeur, son titre petit à côté de six colonnes d'affiches.
///
/// [child] voit une page aux proportions de l'écran (sa largeur divisée par
/// [scale]) et non du volet : les marges et les points de rupture y sont
/// ceux d'un téléviseur, pas ceux d'une fenêtre de 600 px. La densité suit,
/// pour que l'image de fond se décode à la taille où elle s'affiche.
class SpotlightScale extends StatelessWidget {
  const SpotlightScale({super.key, required this.scale, required this.child});

  /// Le plus que le volet grandit : au-delà, sur un écran très large, la
  /// fiche deviendrait une affiche de cinéma.
  static const double maxScale = 2;

  /// L'affiche du mur d'un téléviseur, rapportée à celle d'une grille du
  /// bureau : la grille d'à côté vise quatre affiches par ligne, comme la TV.
  static const double posterScale = 1.2;

  /// L'agrandissement du volet dans une page de [width] pixels.
  static double factorFor(double width) =>
      (width / TvUiScale.designWidth).clamp(1.0, maxScale);

  /// L'agrandissement que la grille d'à côté donne à ses affiches.
  static double tileScaleFor(double width) => factorFor(width) * posterScale;

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    return LayoutBuilder(builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final laidOut = constraints.biggest / scale;
      return MediaQuery(
        data: media.copyWith(
          size: media.size / scale,
          devicePixelRatio: media.devicePixelRatio * scale,
          padding: media.padding / scale,
          viewPadding: media.viewPadding / scale,
        ),
        // FittedBox, comme TvUiScale : il met à l'échelle le dessin et les
        // coordonnées, et le volet garde exactement sa place.
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: laidOut, child: child),
        ),
      );
    });
  }
}
