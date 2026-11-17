import 'package:flutter/material.dart';

/// Locked visual constants for Chrome Onyx, the player chrome.
///
/// Nothing here is a user setting: the look is fixed, the same for every
/// account and every device.
abstract final class OnyxChromeTheme {
  const OnyxChromeTheme._();

  /// Sous cette largeur, le chrome d'une souris prend ses tailles serrées et
  /// range les onglets derrière un bouton, comme un écran tenu en main : la
  /// rangée d'onglets et leur volet demandent la largeur d'un moniteur.
  static const double compactBreakpoint = 800;

  /// Sous cette hauteur, le volet des onglets (238 de contenu, plus ses
  /// rangées) mangerait l'image d'une fenêtre : mêmes onglets, derrière le
  /// bouton.
  static const double tabsPaneMinHeight = 560;

  /// Le chrome d'une souris porte-t-il les onglets sous sa barre, avec le
  /// volet d'un téléviseur (ADR-0139) ? Sinon un bouton de la rangée ouvre la
  /// feuille du bas. Une seule réponse pour le chrome, qui dessine, et pour
  /// l'écran du lecteur, qui pose la feuille.
  static bool pointerCarriesTabs(Size size) =>
      size.width >= compactBreakpoint && size.height >= tabsPaneMinHeight;

  /// À partir de cette largeur, un écran tenu en main est une tablette : son
  /// chrome garde les tailles d'un doigt mais s'écarte davantage des bords,
  /// que rien n'y protège (un téléphone couché a ses zones sûres). Le plus
  /// large des téléphones couchés fait 956.
  static const double tabletBreakpoint = 1000;

  // --- Colour -------------------------------------------------------------

  /// Icons at rest. They go to [iconActive] on hover/focus.
  static const Color icon = Color(0xD9FFFFFF); // white 85%
  static const Color iconActive = Colors.white;
  static const Color iconDisabled = Color(0x59FFFFFF); // white 35%

  static const Color title = Colors.white;
  static const Color meta = Color(0x99FFFFFF); // white 60%
  static const Color time = Color(0xB3FFFFFF); // white 70%

  /// Played portion of the scrubber — white.
  static const Color progressPlayed = Colors.white;
  static const Color progressBuffered = Color(0x4DFFFFFF); // white 30%
  static const Color progressTrack = Color(0x33FFFFFF); // white 20%
  static const Color chapterMark = Color(0x8AFFFFFF); // white 54%

  static const Color tooltipSurface = Color(0xF21C1C1C);

  // --- Verre ----------------------------------------------------------------
  // Les panneaux posés sur le film à la demande (`OnyxGlassPanel`, ADR-0130).

  /// Le fond d'un panneau quand ce qui est dessous est flouté.
  static const Color glassSurface = Color(0xB828282C); // 72 %

  /// Le même sans flou (mode léger, téléviseurs LG) : assez dense pour porter
  /// le texte sur une image claire.
  static const Color glassSurfaceDense = Color(0xF21E1E22); // 95 %
  static const Color glassBorder = Color(0x29FFFFFF); // blanc 16 %
  static const Color glassHairline = Color(0x14FFFFFF); // blanc 8 %
  static const Color glassShadow = Color(0x8C000000); // noir 55 %

  /// Une commande de verre au repos : bouton rond, capsule, carte.
  static const Color glassControl = Color(0x2EFFFFFF); // blanc 18 %

  /// La même sous le pointeur, ou marquée comme le choix en cours.
  static const Color glassControlActive = Color(0x47FFFFFF); // blanc 28 %

  /// Une carte de volet au repos, plus discrète qu'une commande.
  static const Color glassCard = Color(0x14FFFFFF); // blanc 8 %

  /// Le voile posé sur l'image derrière une fenêtre de question.
  static const Color questionVeil = Color(0x99000000); // noir 60 %

  /// Top and bottom scrims. Flat gradients, no blur anywhere in this chrome.
  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x99000000), Color(0x00000000)],
  );

  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xE6000000), Color(0x8A000000), Color(0x00000000)],
    stops: [0.0, 0.45, 1.0],
  );

  // --- Metrics ------------------------------------------------------------

  /// Sizes are split in two fixed sets rather than scaled continuously: at
  /// phone widths a scaled-down icon lands well under the 44px touch target,
  /// which would make the chrome unusable on the very devices it has to serve.
  ///
  /// [scale] trims what is *drawn* without touching what is touched — see
  /// [OnyxChromeMetrics.scaledBy]. It is how an iPhone gets a slightly smaller
  /// chrome than the same widget on Android.
  ///
  /// A television ignores the width: it always gets the phone's arrangement,
  /// drawn at [OnyxChromeMetrics.tv] sizes. See [OnyxChromeMetrics.tv].
  ///
  /// Un écran tenu en main l'ignore aussi : son arrangement n'a qu'un jeu de
  /// tailles, celles d'un doigt. Voir [OnyxChromeMetrics.handheld].
  static OnyxChromeMetrics metricsFor(
    double width, {
    double scale = 1,
    bool tv = false,
    bool handheld = false,
  }) {
    if (tv) return const OnyxChromeMetrics.tv();
    final base = handheld
        ? (width < tabletBreakpoint
            ? const OnyxChromeMetrics.handheld()
            : const OnyxChromeMetrics.handheld(gutter: 28))
        : width < compactBreakpoint
            ? const OnyxChromeMetrics.compact()
            : const OnyxChromeMetrics.wide();
    return scale == 1 ? base : base.scaledBy(scale);
  }
}

/// The two size sets of Chrome Onyx, picked by width.
class OnyxChromeMetrics {
  /// Edge padding around the whole chrome.
  final double gutter;

  /// Tappable box around an icon — never below 44 on touch-sized widths.
  final double hitSize;

  /// Drawn icon size inside that box.
  final double iconSize;

  /// Play/pause is the one oversized control in the transport row.
  final double playIconSize;

  final double titleSize;
  final double metaSize;
  final double timeSize;

  /// Scrubber bar thickness at rest and while hovered/dragged.
  final double barThickness;
  final double barThicknessActive;
  final double handleSize;

  /// Gap between two icons in a cluster.
  final double clusterGap;

  /// Les tailles serrées : une fenêtre étroite, un écran tenu en main, un
  /// téléviseur. Le curseur du volume y est plus court.
  final bool isCompact;

  /// Height of the TMDB logo in the top bar, and the size of the title text
  /// standing in for it.
  final double logoHeight;
  final double brandTextSize;

  /// Space kept free under the last row of the chrome and above the top bar.
  final double bottomInset;
  final double topInset;

  final double skipIntroTextSize;

  /// Width of the timeline still shown above the scrubber.
  final double previewWidth;

  /// Les tailles d'un écran à souris, pour l'arrangement de l'ADR-0139 :
  /// celui d'un téléviseur, à la distance d'un moniteur. Les boutons sont les
  /// disques de verre de tous les arrangements (`OnyxIconButton.glassDisc`).
  const OnyxChromeMetrics.wide()
      : gutter = 32,
        hitSize = 44,
        iconSize = 21,
        playIconSize = 34,
        titleSize = 28,
        metaSize = 15,
        timeSize = 13,
        barThickness = 3,
        barThicknessActive = 5,
        handleSize = 13,
        clusterGap = 4,
        isCompact = false,
        logoHeight = 38,
        brandTextSize = 18,
        bottomInset = 12,
        topInset = 12,
        skipIntroTextSize = 14,
        previewWidth = 320;

  /// Les mêmes dans une fenêtre étroite.
  const OnyxChromeMetrics.compact()
      : gutter = 16,
        hitSize = 44,
        iconSize = 21,
        playIconSize = 32,
        titleSize = 18,
        metaSize = 14,
        timeSize = 13,
        barThickness = 3,
        barThicknessActive = 5,
        handleSize = 13,
        clusterGap = 4,
        isCompact = true,
        logoHeight = 28,
        brandTextSize = 15,
        bottomInset = 10,
        topInset = 12,
        skipIntroTextSize = 13,
        previewWidth = 208;

  /// Les tailles d'un écran tenu en main, pour l'arrangement de l'ADR-0136 :
  /// le titre et les boutons ronds sur une rangée, la barre fine, les onglets
  /// dessous, lecture et ±10 s au milieu de l'image.
  ///
  /// Un seul jeu, téléphone ou tablette : la largeur ne change pas la taille
  /// d'un doigt, seulement la marge ([OnyxChromeTheme.tabletBreakpoint]). Une
  /// cible fait 44, et ce qui s'y dessine est plus petit — le disque d'un
  /// bouton de verre fait `OnyxIconButton.glassDisc`. La barre est fine
  /// parce qu'un repère dit la position ; sa rangée garde la hauteur d'un
  /// doigt.
  const OnyxChromeMetrics.handheld({this.gutter = 16})
      : hitSize = 44,
        iconSize = 21,
        playIconSize = 60,
        titleSize = 22,
        metaSize = 14,
        timeSize = 13,
        barThickness = 3,
        barThicknessActive = 5,
        handleSize = 13,
        clusterGap = 4,
        isCompact = true,
        logoHeight = 28,
        brandTextSize = 15,
        bottomInset = 10,
        topInset = 12,
        skipIntroTextSize = 14,
        previewWidth = 208;

  /// Television sizes, for a screen three metres away.
  ///
  /// Most sets report around 960 logical pixels across, so the width-based
  /// pick would hand them the desktop sizes, drawn for a monitor at arm's
  /// length.
  ///
  /// Dessinées pour une mise en page de 1280 de large (`PlayerTvScale`,
  /// ADR-0130) : la marge de 53 y vaut les 80 points de la zone sûre d'une
  /// Apple TV, et la vignette un quart de l'écran.
  ///
  /// The insets keep every control inside the title-safe area: a good share of
  /// televisions still crop a few percent off each edge.
  const OnyxChromeMetrics.tv()
      : gutter = 53,
        hitSize = 52,
        iconSize = 28,
        playIconSize = 56,
        titleSize = 28,
        metaSize = 17,
        timeSize = 15,
        barThickness = 6,
        barThicknessActive = 8,
        handleSize = 16,
        clusterGap = 14,
        isCompact = true,
        logoHeight = 60,
        brandTextSize = 26,
        bottomInset = 30,
        topInset = 40,
        skipIntroTextSize = 16,
        previewWidth = 320;

  const OnyxChromeMetrics._({
    required this.gutter,
    required this.hitSize,
    required this.iconSize,
    required this.playIconSize,
    required this.titleSize,
    required this.metaSize,
    required this.timeSize,
    required this.barThickness,
    required this.barThicknessActive,
    required this.handleSize,
    required this.clusterGap,
    required this.isCompact,
    required this.logoHeight,
    required this.brandTextSize,
    required this.bottomInset,
    required this.topInset,
    required this.skipIntroTextSize,
    required this.previewWidth,
  });

  /// The same chrome, drawn smaller.
  ///
  /// Only what is *seen* shrinks: text, icons, margins. [hitSize] and the
  /// scrubber's own thickness are left alone, because they are not style —
  /// they are the size of a fingertip and of a target that has to be hit while
  /// a film is playing. A chrome that looks 10% smaller and is 10% harder to
  /// press is not the same trade.
  OnyxChromeMetrics scaledBy(double factor) => OnyxChromeMetrics._(
        gutter: gutter * factor,
        hitSize: hitSize,
        iconSize: iconSize * factor,
        playIconSize: playIconSize * factor,
        titleSize: titleSize * factor,
        metaSize: metaSize * factor,
        timeSize: timeSize * factor,
        barThickness: barThickness,
        barThicknessActive: barThicknessActive,
        handleSize: handleSize,
        clusterGap: clusterGap * factor,
        isCompact: isCompact,
        // Left as they were before the scale existed.
        logoHeight: logoHeight,
        brandTextSize: brandTextSize,
        bottomInset: bottomInset,
        topInset: topInset,
        skipIntroTextSize: skipIntroTextSize,
        previewWidth: previewWidth * factor,
      );
}
