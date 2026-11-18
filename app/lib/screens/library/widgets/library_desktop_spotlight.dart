import 'package:flutter/material.dart';

import '../../../models/models.dart';
import '../../../tv/tv_ui_scale.dart';
import '../../../utils/responsive.dart';
import 'library_spotlight.dart';
import 'library_spotlight_prefetch.dart';
import 'library_tv_view.dart';

/// Une bibliothèque sur un grand écran du bureau : la fiche du titre que le
/// pointeur (ou le clavier) désigne dans un volet à gauche, la grille
/// d'affiches à droite, comme dans la recherche du bureau (ADR-0139) et le
/// volet d'une bibliothèque sur téléviseur (ADR-0125). Voir ADR-0140.
///
/// Sous [minWidth], la grille garde toute la largeur : le volet y mangerait
/// la moitié des colonnes.
///
/// Le volet a les proportions de celui de l'Apple TV (ADR-0156) : il se met en
/// page sur la largeur d'un téléviseur ([TvUiScale.designWidth]) puis grandit
/// avec la fenêtre ([scaleFor]). À taille réelle, sur un écran de 1920 px, il
/// ne prenait qu'un quart de la largeur, son titre petit à côté de six
/// colonnes d'affiches.
class LibraryDesktopSpotlight extends StatelessWidget {
  const LibraryDesktopSpotlight({
    super.key,
    required this.entries,
    required this.presented,
    required this.child,
  });

  /// Les affiches, déjà triées. Le volet présente la première tant que le
  /// pointeur n'en a désigné aucune.
  final List<LibraryEntry> entries;

  /// Le rang du titre désigné ; voir [LibrarySpotlightTarget].
  final ValueNotifier<int?> presented;

  /// La grille, avec son en-tête.
  final Widget child;

  /// La largeur à partir de laquelle le volet s'ouvre, celle de la recherche
  /// du bureau.
  static const double minWidth = 1100;

  /// L'image de fond déborde du volet et se fond sous les premières colonnes.
  static const double _backdropOverhang = 170;

  /// Le plus que le volet grandit : au-delà, sur un écran très large, la
  /// fiche deviendrait une affiche de cinéma.
  static const double maxScale = 2;

  /// L'affiche du mur d'un téléviseur, rapportée à celle d'une grille du
  /// bureau : la grille d'à côté vise quatre affiches par ligne, comme la TV.
  static const double posterScale = 1.2;

  /// Vrai quand une fenêtre de [width] ouvre le volet.
  static bool fits(double width) => width >= minWidth;

  /// L'agrandissement du volet dans une page de [width] pixels.
  static double scaleFor(double width) =>
      (width / TvUiScale.designWidth).clamp(1.0, maxScale);

  /// L'agrandissement que la grille d'à côté donne à ses affiches.
  static double tileScaleFor(double width) => scaleFor(width) * posterScale;

  /// La place que le volet prend à gauche de la grille dans une page de
  /// [width], sa gouttière droite comprise : la grille y pose la sienne.
  static double paneWidth(BuildContext context, double width) =>
      (AppLayout.pagePadding(context) + LibraryTvView.textWidth) *
      scaleFor(width);

  LibraryEntry _spotlight(int? id) {
    for (final entry in entries) {
      if (entry.media.id == id) return entry;
    }
    return entries.first;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final scale = scaleFor(box.maxWidth);
      final padding = AppLayout.pagePadding(context);
      final pane = paneWidth(context, box.maxWidth);
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: (padding +
                    LibraryTvView.textWidth +
                    padding +
                    _backdropOverhang) *
                scale,
            // La fiche se lit, elle ne se clique pas : le pointeur passe à la
            // grille qui déborde dessus.
            child: IgnorePointer(
              child: _ScaledPane(
                scale: scale,
                child: ValueListenableBuilder<int?>(
                  valueListenable: presented,
                  builder: (context, id, _) {
                    final media = _spotlight(id).media;
                    return LibrarySpotlight(
                      media: media,
                      eyebrow: librarySpotlightEyebrow(context, media),
                      textWidth: LibraryTvView.textWidth,
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(left: pane, top: 0, right: 0, bottom: 0, child: child),
        ],
      );
    });
  }
}

/// Met [child] en page [scale] fois plus petit, puis l'agrandit d'autant :
/// le principe de [TvUiScale], pour le volet seul.
///
/// La page vue par [child] garde les proportions de l'écran (sa largeur
/// divisée par [scale]) et non celles du volet : les marges et les points de
/// rupture y sont ceux d'un téléviseur, pas ceux d'une fenêtre de 600 px. La
/// densité suit, pour que l'image de fond se décode à la taille où elle
/// s'affiche.
class _ScaledPane extends StatelessWidget {
  const _ScaledPane({required this.scale, required this.child});

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
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: laidOut, child: child),
        ),
      );
    });
  }
}

/// Une affiche qui désigne son titre au volet quand le pointeur la survole
/// ou que le focus du clavier entre dans sa carte.
class LibrarySpotlightTarget extends StatelessWidget {
  const LibrarySpotlightTarget({
    super.key,
    required this.media,
    required this.presented,
    required this.child,
  });

  final Media media;
  final ValueNotifier<int?> presented;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => presented.value = media.id,
      // Ne prend pas le focus : il écoute celui de la carte dessous.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) presented.value = media.id;
        },
        // La fiche et le logo sont prêts avant le survol (ADR-0142).
        child: LibrarySpotlightWarmup(media: media, child: child),
      ),
    );
  }
}
