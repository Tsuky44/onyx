import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../utils/responsive.dart';
import 'media_card.dart';
import 'poster_card.dart';
import 'skeleton.dart';

/// Une affiche du mur : un film avec sa progression, ou une série.
typedef PosterWallEntry = ({Media media, HomeMediaItem? movie});

/// Un rayon du mur : ses affiches, sous un titre s'il y en a plusieurs.
class PosterWallSection {
  const PosterWallSection({this.title, required this.entries});

  /// Nul pour un mur d'un seul tenant (une bibliothèque).
  final String? title;
  final List<PosterWallEntry> entries;
}

/// Le mur d'affiches d'un téléviseur : la grille qui défile à droite d'un
/// volet, dans une bibliothèque comme dans la recherche (ADR-0125, ADR-0126).
///
/// Il défile rangée par rangée : la rangée focalisée se pose toujours à la
/// même hauteur ([focusTop]), par le `scrollAlignment` de `TvFocusable`. Les
/// rangées d'avant sortent par le haut, celle d'après est entière dessous.
class TvPosterWall extends StatelessWidget {
  const TvPosterWall({
    super.key,
    required this.sections,
    required this.padding,
    required this.focusTop,
    this.columns = 4,
    this.resetKey,
    this.loading = false,
    this.showDetails = false,
    this.onFocused,
  });

  /// Les rayons, dans l'ordre. Un rayon vide n'est pas dessiné.
  final List<PosterWallSection> sections;

  /// Les marges du contenu. Celle du haut est la place du premier titre de
  /// rayon, ou de la première rangée s'il n'y en a pas.
  final EdgeInsets padding;

  /// Où se pose le haut de la rangée focalisée, depuis le haut du mur.
  final double focusTop;

  final int columns;

  /// Quand il change (un tri, une autre recherche), le mur repart du haut.
  final Object? resetKey;

  /// Vrai tant que les affiches ne sont pas là : des cases grises à leur
  /// place, pour que la page ait déjà sa forme.
  final bool loading;

  /// Vrai pour poser sur l'affiche focalisée son cartouche (titre, type,
  /// résumé). Faux quand le volet d'à côté présente déjà le titre.
  final bool showDetails;

  /// L'affiche que la télécommande vient de désigner.
  final ValueChanged<Media>? onFocused;

  /// L'écart entre deux rangées.
  static const double rowGap = 28;

  /// L'écart entre la dernière rangée d'un rayon et le titre du suivant.
  static const double sectionGap = 36;

  /// La hauteur du titre d'un rayon, écart avec sa première rangée compris :
  /// la place de l'affiche soulevée (un dixième de sa hauteur), qui sinon
  /// passait sur le titre.
  static const double sectionHeader = 58;

  Widget _poster(PosterWallEntry entry, double alignment) {
    final movie = entry.movie;
    final card = MediaCard(
      media: entry.media,
      item: movie,
      watched: movie?.isFinished ?? false,
      progress: movie == null || movie.isFinished ? null : movie.percentWatched,
      showDetails: showDetails,
      scrollAlignment: alignment,
    );
    final onFocused = this.onFocused;
    if (onFocused == null) return card;
    // Ne prend pas le focus : il apprend seulement que son affiche l'a.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) onFocused(entry.media);
      },
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = AppLayout.mediaRowGap(context);
    final shown = [
      for (final section in sections)
        if (section.entries.isNotEmpty) section,
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final gridWidth = constraints.maxWidth - padding.horizontal;
      final cellWidth = (gridWidth - gap * (columns - 1)) / columns;
      final cellHeight = cellWidth * 3 / 2;
      final slack = constraints.maxHeight - cellHeight;
      final alignment = slack <= 0 ? 0.0 : (focusTop / slack).clamp(0.0, 1.0);
      final delegate = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: gap,
        mainAxisSpacing: rowGap,
        childAspectRatio: 2 / 3,
      );
      // Les marges de côté sont dans ce qui défile : l'affiche focalisée,
      // agrandie, n'est pas rognée par le bord du mur.
      final sides = EdgeInsets.only(left: padding.left, right: padding.right);

      return CustomScrollView(
        // Un autre tri, une autre recherche : le mur repart du haut.
        key: ValueKey<Object?>(resetKey),
        physics: loading ? const NeverScrollableScrollPhysics() : null,
        scrollCacheExtent: AppLayout.imageCacheExtent(context),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: padding.top)),
          if (loading)
            SliverPadding(
              padding: sides,
              sliver: SliverGrid(
                gridDelegate: delegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const SkeletonPulse(
                    child: SkeletonBox(radius: PosterCard.radius),
                  ),
                  childCount: columns * 3,
                ),
              ),
            )
          else
            for (final (position, section) in shown.indexed) ...[
              if (section.title case final title?)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: sides.copyWith(
                      top: position == 0 ? 0 : sectionGap,
                    ),
                    child: SizedBox(
                      height: sectionHeader,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppType.title1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: sides,
                sliver: SliverGrid(
                  gridDelegate: delegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _poster(section.entries[index], alignment),
                    childCount: section.entries.length,
                  ),
                ),
              ),
            ],
          SliverToBoxAdapter(
            child: SizedBox(
              height: padding.bottom + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      );
    });
  }
}
