part of 'onyx_controls_layer.dart';

/// Lays the chrome out as three bands: the top bar, the bottom cluster, and
/// whatever is left between them.
///
/// The middle band is the brightness bar's, and it is the whole point of doing
/// this by hand. The two bars are laid out first and *measured*; the bar is
/// then given the space that actually remains, so it can neither be drawn over
/// the buttons nor — worse, because it is invisible — catch fingers where they
/// belong to the buttons. A [Stack] could only have guessed at those heights.
class _OnyxChromeLayout extends MultiChildLayoutDelegate {
  _OnyxChromeLayout({
    required this.topLead,
    required this.bottomLead,
    this.centreLead = 0,
  });

  /// How far the band may reach back into each bar — their empty scrim
  /// margins, which draw nothing and catch nothing.
  final double topLead;
  final double bottomLead;

  /// Ce que les commandes du milieu peuvent reprendre à la barre du bas : sa
  /// marge de dégradé, jusqu'à la rangée du titre. Tenu à part de
  /// [bottomLead], que « Passer l'intro » ramène à zéro pour la barre de
  /// luminosité : la capsule est au bord droit, les commandes au milieu.
  final double centreLead;

  static const String top = 'top';
  static const String bottom = 'bottom';
  static const String brightness = 'brightness';

  /// Les commandes de lecture d'un écran tenu en main, au milieu de l'image.
  static const String centre = 'centre';

  /// Où tombe leur milieu, en fraction de la hauteur : voir
  /// [OnyxChromeTheme.handheldCentreAt].
  static const double _centreAt = OnyxChromeTheme.handheldCentreAt;

  /// Ce qui les sépare au moins de la rangée du titre, sur un écran trop bas
  /// pour que la fraction suffise.
  static const double _centreGap = 4;

  @override
  void performLayout(Size size) {
    // Full width, and **unbounded** height: the bars are asked how tall they
    // want to be, not told how tall they may be. A bounded height is not the
    // same question — several widgets in these bars, an [Align] around the
    // title among them, answer "as tall as you'll let me" and would take the
    // whole screen. It is the constraint a [Positioned] pinned to one edge
    // gives, which is what these bars were written against.
    final natural = BoxConstraints(minWidth: size.width, maxWidth: size.width);

    var topHeight = 0.0;
    if (hasChild(top)) {
      topHeight = layoutChild(top, natural).height;
      positionChild(top, Offset.zero);
    }

    var bottomHeight = 0.0;
    if (hasChild(bottom)) {
      bottomHeight = layoutChild(bottom, natural).height;
      positionChild(bottom, Offset(0, size.height - bottomHeight));
    }

    if (hasChild(centre)) {
      final box = layoutChild(centre, BoxConstraints.loose(size));
      // Entre les deux barres, quoi qu'il arrive : sur un petit téléphone la
      // fraction seule poserait les boutons sur la rangée du titre, et le
      // doigt qui visait +10 s ouvrirait un menu.
      final lowest =
          size.height - bottomHeight + centreLead - box.height - _centreGap;
      final highest = topHeight - topLead;
      var y = size.height * _centreAt - box.height / 2;
      if (y > lowest) y = lowest;
      if (y < highest) y = highest;
      positionChild(
        centre,
        Offset(
          (size.width - box.width) / 2,
          y.clamp(0.0, (size.height - box.height).clamp(0.0, size.height)),
        ),
      );
    }

    if (hasChild(brightness)) {
      // What is left between the two bars, plus the empty margin each of them
      // offers back. Never less than nothing: on a short window the bars can
      // take the whole height, and the control answers a band too small to use
      // by drawing nothing at all.
      final bandTop = (topHeight - topLead).clamp(0.0, size.height);
      final bandBottom = (size.height - bottomHeight + bottomLead).clamp(
        0.0,
        size.height,
      );
      final band = (bandBottom - bandTop).clamp(0.0, size.height);
      layoutChild(
        brightness,
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: band,
        ),
      );
      positionChild(brightness, Offset(0, bandTop));
    }
  }

  @override
  bool shouldRelayout(_OnyxChromeLayout oldDelegate) =>
      oldDelegate.topLead != topLead ||
      oldDelegate.bottomLead != bottomLead ||
      oldDelegate.centreLead != centreLead;
}
