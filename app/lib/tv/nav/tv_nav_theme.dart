import 'package:dpad/dpad.dart';

import '../../theme/app_motion.dart';
import '../tv_ui_scale.dart';

/// Le thème de dpad aux couleurs et aux durées d'Onyx.
///
/// Il ne dessine rien : l'anneau de focus reste le nôtre (ADR-0008), posé par
/// `TvDpadFocusable` dans son `builder`, ce qui rend les `effects` du thème
/// sans objet. Restent la marge et la cadence du défilement jusqu'à la cible,
/// le seul défilement par pas depuis la refonte (ADR-0110, ex-`TvFocusScroll`).
abstract final class TvNavTheme {
  /// La largeur de référence des recommandations d'Apple pour la zone sûre.
  static const double _hig1080Width = 1920;

  /// La marge latérale de la zone sûre tvOS, en points d'un écran de
  /// [_hig1080Width] (HIG : 80 sur les côtés, 60 en haut et en bas).
  static const double _hig1080Side = 80;

  /// La marge que dpad garde entre la cible et le bord de ce qui défile.
  ///
  /// dpad n'en prend qu'**une** pour les quatre côtés (constat C12) : on y met
  /// la marge latérale, la plus grande, et le haut et le bas restent portés
  /// par le padding des écrans. Les pages se mettent en page sur
  /// [TvUiScale.designWidth] puis s'étirent à l'écran : 80 points sur 1920
  /// font donc toujours la même fraction de la largeur, ≈ 53 pixels logiques
  /// de page, quelle que soit la densité qu'annonce le téléviseur.
  static const double scrollPadding =
      _hig1080Side * TvUiScale.designWidth / _hig1080Width;

  /// Le thème à donner à `Dpad`.
  ///
  /// En mode léger, la cible saute au lieu de glisser : c'est une animation de
  /// défilement de moins par flèche, sur les machines qui comptent leurs
  /// images (ADR-0086). Quand le système demande moins de mouvement, dpad
  /// saute de lui-même (`MediaQuery.disableAnimations`).
  static DpadThemeData data({required bool lite}) => DpadThemeData(
        effects: const <DpadEffect>[],
        scrollPadding: scrollPadding,
        scrollDuration: lite ? Duration.zero : AppMotion.standard,
        scrollCurve: AppMotion.curve,
        scrollAlignment: DpadRevealAlignment.nearest,
        longSelectDuration: longSelectDuration,
      );

  /// Ce qu'il faut tenir OK pour ouvrir le menu d'une carte.
  ///
  /// La durée de l'appui long d'Android TV ; dpad la mesure entre l'appui et
  /// le relâchement (constat C10), pas aux répétitions comme l'ancien
  /// `TvFocusable`.
  static const Duration longSelectDuration = Duration(milliseconds: 500);

  /// L'alignement dpad le plus proche d'un alignement de `TvFocusable`.
  ///
  /// L'ancien `TvFocusable.scrollAlignment` est une fraction (0,5 centre la
  /// cible) ; dpad ne connaît que « au plus près » et « au centre ». Le centre
  /// reste le centre, tout le reste devient « au plus près » : c'est ce que
  /// demandaient les listes hautes qui passaient 0,2 ou 0,3 pour ne pas
  /// recentrer à chaque ligne.
  static DpadRevealAlignment alignmentFor(double scrollAlignment) =>
      scrollAlignment == 0.5
          ? DpadRevealAlignment.center
          : DpadRevealAlignment.nearest;
}
