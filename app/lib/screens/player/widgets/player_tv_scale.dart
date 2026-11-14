import 'package:flutter/widgets.dart';

import '../../../tv/tv_ui_scale.dart';

/// Ce que le lecteur d'un téléviseur dessine au-dessus de l'image, à l'échelle
/// du reste de l'app.
///
/// Le lecteur échappe à [TvUiScale] : la vidéo d'ExoPlayer est une
/// SurfaceView que Flutter ne sait pas réduire. Chaque couche posée sur
/// l'image est donc mise en page sur [designWidth] puis ramenée à l'écran ; la
/// vidéo reste hors de l'échelle.
///
/// [designWidth] est celle des pages ([TvUiScale.designWidth], 1280) depuis
/// l'ADR-0130. Les tailles télé du chrome ([OnyxChromeMetrics.tv] : marge de
/// 53, soit les 80 points de la zone sûre d'Apple sur 1920) ont été dessinées
/// pour cette largeur ; mis en page sur les 1920 points que l'Apple TV
/// annonce, le chrome paraissait un tiers plus petit que la maquette validée
/// et que le reste de l'app, vu du canapé. Un téléviseur Android (960) et le
/// web des téléviseurs LG (1920) tombent sur les mêmes proportions.
abstract final class PlayerTvScale {
  /// La largeur de mise en page du lecteur : celle des pages d'un téléviseur.
  static const double designWidth = TvUiScale.designWidth;

  /// Le facteur entre ce qui est mis en page et ce qui est dessiné, sur un
  /// écran de [width] pixels logiques. 1 hors téléviseur.
  static double factorFor(double width, {required bool isTv}) =>
      isTv && width > 0 && width.isFinite ? width / designWidth : 1;

  /// Une couche de la pile du lecteur (ou d'un menu posé par-dessus), mise à
  /// l'échelle sur téléviseur. [child] peut être un `Positioned` : il est
  /// posé dans sa propre pile pleine page.
  static Widget layer({required bool isTv, required Widget child}) {
    if (!isTv) return child;
    return SizedBox.expand(
      child: TvUiScale(
        layoutWidth: designWidth,
        child: Stack(fit: StackFit.expand, children: [child]),
      ),
    );
  }
}
