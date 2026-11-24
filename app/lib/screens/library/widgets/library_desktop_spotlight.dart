import 'package:material_ui/material_ui.dart';

import '../../../models/models.dart';
import '../../../utils/responsive.dart';
import 'library_spotlight.dart';
import 'library_spotlight_prefetch.dart';
import 'library_tv_view.dart';
import 'spotlight_scale.dart';

/// Une bibliothèque sur un grand écran du bureau : la fiche du titre que le
/// pointeur (ou le clavier) désigne dans un volet à gauche, la grille
/// d'affiches à droite, comme dans la recherche du bureau (ADR-0139) et le
/// volet d'une bibliothèque sur téléviseur (ADR-0125). Voir ADR-0140.
///
/// Sous [minWidth], la grille garde toute la largeur : le volet y mangerait
/// la moitié des colonnes.
///
/// Le volet a les proportions de celui de l'Apple TV ([SpotlightScale],
/// ADR-0156).
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

  /// Vrai quand une fenêtre de [width] ouvre le volet.
  static bool fits(double width) => width >= minWidth;

  /// La place que le volet prend à gauche de la grille dans une page de
  /// [width], sa gouttière droite comprise : la grille y pose la sienne.
  static double paneWidth(BuildContext context, double width) =>
      (AppLayout.pagePadding(context) + LibraryTvView.textWidth) *
      SpotlightScale.factorFor(width);

  LibraryEntry _spotlight(int? id) {
    for (final entry in entries) {
      if (entry.media.id == id) return entry;
    }
    return entries.first;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final scale = SpotlightScale.factorFor(box.maxWidth);
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
              child: SpotlightScale(
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
