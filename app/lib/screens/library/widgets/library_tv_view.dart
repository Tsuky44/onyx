import 'dart:async';

import 'package:flutter/material.dart';

import '../../../desktop_window.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../tv/nav/tv_region.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/media_card.dart';
import '../../../widgets/global/poster_card.dart';
import '../../../widgets/global/skeleton.dart';
import 'library_spotlight.dart';

/// Une affiche de la grille d'une bibliothèque : un film avec sa progression,
/// ou une série.
typedef LibraryEntry = ({Media media, HomeMediaItem? movie});

/// Une bibliothèque sur téléviseur : la fiche du titre que la télécommande
/// désigne dans un volet fixe à gauche, la grille d'affiches à droite
/// (ADR-0125, qui amende l'ADR-0123).
///
/// La grille du bureau montrait trois rangées pleines de sept affiches sans
/// titre : « trop rempli, trop compact » vu du canapé. Une première version
/// posait la fiche en tête d'écran et une seule rangée dessous : la grille n'y
/// défilait que sur la moitié basse, coupée net sous la fiche, et le
/// défilement se lisait mal. Ici la fiche est sur le côté : les affiches
/// défilent sur toute la hauteur de l'écran et passent sous la barre
/// d'onglets, comme les rangées de l'accueil.
///
/// Le tri est en haut du volet, à la hauteur de la rangée focalisée : gauche
/// depuis la première colonne y mène, droite ramène à l'affiche quittée
/// ([TvRegion.slide]). Le focus part dans le sens de la flèche, sans
/// traverser l'écran.
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

  /// Le tri, posé en haut du volet. Absent pendant le chargement : il n'y a
  /// rien à trier.
  final Widget sortControl;

  /// Vrai sous la barre d'onglets de la coquille.
  final bool embedded;

  /// Quatre affiches par ligne, de la taille de celles de l'accueil.
  static const int columns = 4;

  /// L'écart entre deux rangées.
  static const double rowGap = 28;

  /// L'écart entre la barre d'onglets et la rangée focalisée : la place de
  /// l'affiche soulevée (un dixième de sa hauteur).
  static const double rowTop = 16;

  /// La largeur du texte de la fiche, et celle du volet avec ses gouttières.
  static const double textWidth = 374;

  /// L'image de fond déborde du volet et se fond sous les premières colonnes.
  static const double _backdropOverhang = 170;

  /// Le temps qu'une affiche de la première colonne doit garder le focus
  /// avant que gauche mène au tri. Plus que l'écart entre deux pas d'un
  /// glissé sur sa lancée (220 ms) ou d'une flèche maintenue : un geste qui
  /// traverse la rangée s'arrête au bord, il ne finit pas sur le tri.
  static const Duration rest = Duration(milliseconds: 300);

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

  /// Ne prennent pas le focus : ils servent à trouver, dans la grille et
  /// dans le volet, ce qui peut le prendre.
  final FocusNode _grid = FocusNode(
    debugLabel: 'library-grid',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode _sort = FocusNode(
    debugLabel: 'library-sort',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// L'affiche d'où la télécommande est partie vers le tri, et son rang.
  FocusNode? _left;
  int? _focusedIndex;

  /// Court tant que le focus vient d'arriver sur son affiche le long de sa
  /// rangée ([LibraryTvView.rest]).
  Timer? _arriving;

  @override
  void didUpdateWidget(LibraryTvView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order) {
      _presented.value = null;
      _left = null;
      _focusedIndex = null;
    }
  }

  @override
  void dispose() {
    _arriving?.cancel();
    _grid.dispose();
    _sort.dispose();
    _presented.dispose();
    super.dispose();
  }

  void _onPosterFocused(int index, LibraryEntry entry) {
    final previous = _focusedIndex;
    _focusedIndex = index;
    _presented.value = entry.media.id;
    _arriving?.cancel();
    // Venu d'une autre rangée, ou du tri, le focus ne court pas le long de
    // celle-ci : gauche peut mener au tri tout de suite.
    const columns = LibraryTvView.columns;
    final alongRow = previous != null &&
        previous != index &&
        previous ~/ columns == index ~/ columns;
    _arriving = alongRow ? Timer(LibraryTvView.rest, () {}) : null;
  }

  /// Gauche au bord de la grille : le tri, en haut du volet.
  void _leaveGrid(TraversalDirection direction) {
    if (direction != TraversalDirection.left) return;
    if (_arriving?.isActive ?? false) return;
    final sort = _sort.descendants
        .where((node) => node.canRequestFocus && node.context != null)
        .firstOrNull;
    if (sort == null) return;
    _left = FocusManager.instance.primaryFocus;
    sort.requestFocus();
  }

  /// Droite depuis le tri : l'affiche quittée, sinon la première de la
  /// grille (après un tri, celle d'avant n'existe plus).
  void _leaveSort(TraversalDirection direction) {
    if (direction != TraversalDirection.right) return;
    final left = _left;
    if (left != null && left.context != null && left.canRequestFocus) {
      left.requestFocus();
      return;
    }
    final posters = _placed(_grid).toList();
    if (posters.isEmpty) return;
    posters.reduce((best, node) {
      final byTop = node.rect.top.compareTo(best.rect.top);
      if (byTop != 0) return byTop < 0 ? node : best;
      return node.rect.left < best.rect.left ? node : best;
    }).requestFocus();
  }

  Widget _poster(int index, double alignment) {
    final entry = widget.entries[index];
    final movie = entry.movie;
    // Ne prend pas le focus : il apprend seulement que son affiche l'a, pour
    // que la fiche la présente.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) _onPosterFocused(index, entry);
      },
      child: MediaCard(
        media: entry.media,
        item: movie,
        watched: movie?.isFinished ?? false,
        progress:
            movie == null || movie.isFinished ? null : movie.percentWatched,
        // La fiche du volet dit déjà tout cela.
        showDetails: false,
        scrollAlignment: alignment,
      ),
    );
  }

  static Iterable<FocusNode> _placed(FocusNode within) =>
      within.traversalDescendants
          .where((node) => node.context != null && !node.rect.isEmpty);

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
      // Le volet : sa gouttière, le texte, puis une gouttière avant la grille.
      final paneWidth = padding + LibraryTvView.textWidth + padding;
      final gridWidth = constraints.maxWidth - paneWidth - padding;
      final cellWidth = (gridWidth - gap * (columns - 1)) / columns;
      final cellHeight = cellWidth * 3 / 2;
      // Où une affiche focalisée se pose : sa rangée en haut de la grille,
      // juste sous la barre d'onglets. Les rangées d'avant passent dessous,
      // la suivante est entière et la troisième pointe.
      final slack = constraints.maxHeight - cellHeight;
      final alignment = slack <= 0
          ? 0.0
          : ((topInset + LibraryTvView.rowTop) / slack).clamp(0.0, 1.0);

      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: paneWidth + LibraryTvView._backdropOverhang,
            child: loading
                ? _LoadingPane(
                    title: widget.title,
                    padding: padding,
                    top: constraints.maxHeight * LibrarySpotlight.textTop,
                  )
                : ValueListenableBuilder<int?>(
                    valueListenable: _presented,
                    builder: (context, presented, _) => LibrarySpotlight(
                      media: _spotlight(presented).media,
                      eyebrow: '${widget.title} · ${widget.countLabel ?? ''}',
                      textWidth: LibraryTvView.textWidth,
                    ),
                  ),
          ),
          // La grille commence une gouttière avant sa première colonne :
          // l'affiche focalisée, agrandie, n'est pas rognée par le bord de ce
          // qui défile.
          Positioned(
            left: paneWidth - padding,
            right: 0,
            top: 0,
            bottom: 0,
            child: TvRegion.slide(
              onEdge: _leaveGrid,
              child: Focus(
                focusNode: _grid,
                canRequestFocus: false,
                skipTraversal: true,
                child: CustomScrollView(
                  // Un nouveau tri repart du haut de la grille.
                  key: ValueKey<Object>(widget.order),
                  physics:
                      loading ? const NeverScrollableScrollPhysics() : null,
                  scrollCacheExtent: AppLayout.imageCacheExtent(context),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        topInset + LibraryTvView.rowTop,
                        padding,
                        padding + MediaQuery.paddingOf(context).bottom,
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
                                childCount: columns * 3,
                              )
                            : SliverChildBuilderDelegate(
                                (context, index) => _poster(index, alignment),
                                childCount: entries.length,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!loading)
            Positioned(
              left: padding,
              top: topInset + LibraryTvView.rowTop,
              child: TvRegion.slide(
                onEdge: _leaveSort,
                // Hors du parcours : sous la barre d'onglets, Bas entre dans
                // la grille, pas sur le bouton posé à sa gauche. Le tri ne
                // s'atteint que depuis le bord de la grille.
                child: Focus(
                  focusNode: _sort,
                  canRequestFocus: false,
                  skipTraversal: true,
                  descendantsAreTraversable: false,
                  child: widget.sortControl,
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Le volet pendant le chargement : le nom de la bibliothèque à la place du
/// titre d'une affiche, pour que la page ne change pas de forme quand ses
/// affiches arrivent.
class _LoadingPane extends StatelessWidget {
  const _LoadingPane({
    required this.title,
    required this.padding,
    required this.top,
  });

  final String title;
  final double padding;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: padding,
          top: top,
          width: LibraryTvView.textWidth,
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
      ],
    );
  }
}
