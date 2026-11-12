import 'package:flutter/material.dart';

import '../../../desktop_window.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/media_card.dart';
import '../../../widgets/global/poster_card.dart';
import '../../../widgets/global/skeleton.dart';
import 'library_spotlight.dart';

/// Une affiche de la grille d'une bibliothèque : un film avec sa progression,
/// ou une série.
typedef LibraryEntry = ({Media media, HomeMediaItem? movie});

/// Une bibliothèque sur téléviseur : la fiche du titre que la télécommande
/// désigne en tête d'écran, une rangée d'affiches dessous (ADR-0123).
///
/// La grille d'avant montrait trois rangées pleines de sept affiches sans
/// titre, à 14 px les unes des autres : « trop rempli, trop compact » vu du
/// canapé. Ici l'écran ne montre qu'une rangée de six, de la taille de celles
/// de l'accueil, et le haut de la suivante ; ce qu'on perd en affiches, la
/// fiche le rend en contexte (image, année, durée, genres, résumé).
///
/// La fiche ne défile pas. La grille défile sous elle, rangée par rangée :
/// l'affiche focalisée se pose toujours à la même hauteur ([_liftRoom]), et la
/// rangée du dessus est alors sortie tout entière.
class LibraryTvView extends StatefulWidget {
  const LibraryTvView({
    super.key,
    required this.title,
    required this.countLabel,
    required this.entries,
    required this.order,
    required this.sortControl,
    required this.embedded,
  });

  /// Le nom de la bibliothèque.
  final String title;

  /// « 128 titres ». Nul pendant le chargement.
  final String? countLabel;

  /// Les affiches, déjà triées. Vide pendant le chargement : la page garde
  /// alors sa forme, des cases grises à la place des affiches.
  final List<LibraryEntry> entries;

  /// Le tri en vigueur. Quand il change, la grille repart du haut et la fiche
  /// de la première affiche.
  final Object order;

  /// Le tri, posé à droite au-dessus de la grille. Absent pendant le
  /// chargement : il n'y a rien à trier, et il serait la seule cible sous
  /// l'en-tête.
  final Widget sortControl;

  /// Vrai sous la barre d'onglets de la coquille.
  final bool embedded;

  /// Six affiches par ligne, comme une rangée de l'accueil (ADR-0118).
  static const int columns = 6;

  /// L'écart entre deux rangées. Plus grand que [_liftRoom] : la rangée du
  /// dessus est sortie de la grille quand la suivante a le focus, sans qu'un
  /// filet de ses affiches reste au bord.
  static const double rowGap = 32;

  /// La place au-dessus de la rangée focalisée : une affiche se soulève de
  /// 10 % depuis son pied (`PosterCard.tvLift`), 27 px pour 266 de haut.
  static const double _liftRoom = 30;

  /// Ce que la rangée suivante montre en bas de l'écran : il y en a d'autres.
  static const double _peek = 52;

  /// L'image de fond descend sous la fiche et se fond derrière le haut de la
  /// grille.
  static const double _backdropTail = 72;

  @override
  State<LibraryTvView> createState() => _LibraryTvViewState();
}

class _LibraryTvViewState extends State<LibraryTvView> {
  /// Le titre que la fiche présente : le dernier que la télécommande a
  /// désigné. Nul tant qu'elle n'est pas entrée dans la grille : la fiche
  /// présente alors la première affiche.
  ///
  /// Un `ValueNotifier` et non un `setState` : le focus qui passe d'une
  /// affiche à l'autre ne redessine que la fiche, pas la grille.
  final ValueNotifier<int?> _presented = ValueNotifier<int?>(null);

  @override
  void didUpdateWidget(LibraryTvView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order) _presented.value = null;
  }

  @override
  void dispose() {
    _presented.dispose();
    super.dispose();
  }

  LibraryEntry _spotlight(int? presented) {
    final entries = widget.entries;
    for (final entry in entries) {
      if (entry.media.id == presented) return entry;
    }
    return entries.first;
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppLayout.pagePadding(context);
    final gap = AppLayout.mediaRowGap(context);
    final topInset = shellTabTopInset(context, embedded: widget.embedded);
    final entries = widget.entries;
    final loading = entries.isEmpty;

    return LayoutBuilder(builder: (context, constraints) {
      const columns = LibraryTvView.columns;
      final cellWidth =
          (constraints.maxWidth - 2 * padding - gap * (columns - 1)) / columns;
      final cellHeight = cellWidth * 3 / 2;
      final gridHeight = (LibraryTvView._liftRoom +
              cellHeight +
              LibraryTvView.rowGap +
              LibraryTvView._peek)
          .clamp(0.0, constraints.maxHeight);
      final headerHeight = constraints.maxHeight - gridHeight;
      // Où une affiche focalisée se pose dans la grille : son haut à
      // [_liftRoom] du bord, quelle que soit la rangée.
      final slack = gridHeight - cellHeight;
      final alignment =
          slack <= 0 ? 0.0 : (LibraryTvView._liftRoom / slack).clamp(0.0, 1.0);

      return Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: headerHeight + LibraryTvView._backdropTail,
            child: loading
                ? _LoadingHeader(
                    title: widget.title,
                    topInset: topInset,
                    padding: padding,
                  )
                : ValueListenableBuilder<int?>(
                    valueListenable: _presented,
                    builder: (context, presented, _) => LibrarySpotlight(
                      media: _spotlight(presented).media,
                      eyebrow: '${widget.title} · ${widget.countLabel ?? ''}',
                      contentHeight: headerHeight,
                      topInset: topInset,
                    ),
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: headerHeight,
            bottom: 0,
            child: CustomScrollView(
              // Un nouveau tri repart du haut de la grille.
              key: ValueKey<Object>(widget.order),
              physics: loading ? const NeverScrollableScrollPhysics() : null,
              scrollCacheExtent: AppLayout.imageCacheExtent(context),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    LibraryTvView._liftRoom,
                    padding,
                    // La dernière rangée doit pouvoir monter à la place de
                    // la première.
                    LibraryTvView.rowGap +
                        LibraryTvView._peek +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: LibraryTvView.rowGap,
                      childAspectRatio: 2 / 3,
                    ),
                    delegate: loading
                        ? SliverChildBuilderDelegate(
                            (context, index) => const SkeletonPulse(
                              child: SkeletonBox(radius: PosterCard.radius),
                            ),
                            childCount: columns * 2,
                          )
                        : SliverChildBuilderDelegate(
                            (context, index) {
                              final entry = entries[index];
                              final movie = entry.movie;
                              // Ne prend pas le focus : il apprend seulement
                              // que son affiche l'a, pour que la fiche la
                              // présente.
                              return Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onFocusChange: (focused) {
                                  if (focused) {
                                    _presented.value = entry.media.id;
                                  }
                                },
                                child: MediaCard(
                                  media: entry.media,
                                  item: movie,
                                  watched: movie?.isFinished ?? false,
                                  progress: movie == null || movie.isFinished
                                      ? null
                                      : movie.percentWatched,
                                  // La fiche du dessus dit déjà tout cela.
                                  showDetails: false,
                                  scrollAlignment: alignment,
                                ),
                              );
                            },
                            childCount: entries.length,
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Après la grille : au-dessus de l'image de fond, qui descend
          // jusque-là.
          if (!loading)
            Positioned(
              right: padding,
              bottom: gridHeight + 6,
              child: widget.sortControl,
            ),
        ],
      );
    });
  }
}

/// L'en-tête pendant le chargement : le nom de la bibliothèque à la place du
/// titre d'une affiche, pour que la page ne change pas de forme quand ses
/// affiches arrivent.
class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({
    required this.title,
    required this.topInset,
    required this.padding,
  });

  final String title;
  final double topInset;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: padding, right: padding, top: topInset),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          // La place du surtitre et du titre d'une fiche.
          height: LibrarySpotlight.headingHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.hero,
                fontWeight: FontWeight.w800,
                height: 1.04,
                letterSpacing: -1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
