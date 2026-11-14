import '../../../../theme/app_type.dart';
import '../../../../tv/tv_mode.dart';

/// Les mesures d'un menu du Chrome Onyx (ADR-0130).
///
/// Un seul dessin — un panneau de verre aux coins ronds, la coche à gauche,
/// la seconde ligne en gris — en deux tailles : celle d'un téléviseur, lue du
/// canapé, où la ligne sous la télécommande est une pastille blanche qui
/// dépasse un peu du rang ; celle d'une souris ou d'un doigt, plus serrée.
class OnyxMenuStyle {
  const OnyxMenuStyle.tv()
      : width = 360,
        maxHeight = 470,
        padding = 10,
        radius = 26,
        rowHeight = 46,
        tallRowHeight = 60,
        rowRadius = 16,
        rowInset = 14,
        overhang = 5,
        checkSlot = 30,
        checkSize = 20,
        labelSize = AppType.headline,
        detailSize = AppType.body,
        valueSize = AppType.callout,
        headerHeight = 34,
        headerSize = AppType.body;

  const OnyxMenuStyle.pointer()
      : width = 300,
        maxHeight = 420,
        padding = 8,
        radius = 18,
        rowHeight = 40,
        tallRowHeight = 52,
        rowRadius = 10,
        rowInset = 12,
        overhang = 0,
        checkSlot = 26,
        checkSize = 17,
        labelSize = AppType.body,
        detailSize = AppType.footnote,
        valueSize = AppType.footnote,
        headerHeight = 32,
        headerSize = AppType.footnote;

  /// Celui de l'appareil : la télécommande ou le pointeur.
  static OnyxMenuStyle get current =>
      TvMode.isTv ? const OnyxMenuStyle.tv() : const OnyxMenuStyle.pointer();

  final double width;
  final double maxHeight;

  /// Le retrait du panneau autour de ses lignes.
  final double padding;
  final double radius;

  /// Une ligne d'un seul texte, et une ligne qui porte une seconde ligne.
  final double rowHeight;
  final double tallRowHeight;
  final double rowRadius;

  /// Le retrait du texte dans sa ligne.
  final double rowInset;

  /// De combien la ligne focalisée dépasse de chaque côté, dans le retrait du
  /// panneau. Zéro hors téléviseur : la pastille blanche est le focus d'une
  /// télécommande (ADR-0112).
  final double overhang;

  /// La place de la coche, qu'elle soit posée ou non : les libellés restent
  /// sur une même verticale.
  final double checkSlot;
  final double checkSize;

  final double labelSize;
  final double detailSize;
  final double valueSize;

  /// L'en-tête : le nom du menu.
  final double headerHeight;
  final double headerSize;
}
