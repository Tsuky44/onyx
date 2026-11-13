import 'package:flutter/widgets.dart';

import '../../../tv/tv_ui_scale.dart';

/// Ce que le lecteur d'un téléviseur dessine au-dessus de l'image, aux
/// proportions de l'Apple TV.
///
/// Le lecteur échappe à [TvUiScale] : la vidéo d'ExoPlayer est une
/// SurfaceView que Flutter ne sait pas réduire. Ses tailles télé sont donc des
/// pixels logiques fixes ([OnyxChromeMetrics.tv], la largeur des menus, la
/// hauteur du panneau des épisodes), réglées sur l'Apple TV qui annonce
/// 1920 points (ADR-0124). Un téléviseur Android en annonce 960 : le titre,
/// les boutons de verre, la barre, les onglets et les menus y prenaient deux
/// fois plus de place. Chaque couche posée sur l'image est donc mise en page
/// sur [designWidth] puis ramenée à l'écran ; la vidéo reste hors de
/// l'échelle. Sur Apple TV et sur le web des téléviseurs LG (1920 de large),
/// rien ne change.
abstract final class PlayerTvScale {
  /// La largeur que l'Apple TV annonce, sur laquelle le lecteur a été réglé.
  static const double designWidth = 1920;

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
