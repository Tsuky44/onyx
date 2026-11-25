import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../desktop_window.dart';
import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/library_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../utils/responsive.dart';
import '../../utils/search_match.dart';
import '../../widgets/global/empty_state.dart';
import '../../widgets/global/filter_panel/onyx_filter_dock.dart';
import '../../widgets/global/media_card.dart';
import '../../widgets/global/poster_grid_zoom_region.dart';
import '../../widgets/global/skeleton.dart';
import '../shell/shell_tabs.dart';
import '../../tv/tv_mode.dart';
import 'library_filters.dart';
import 'widgets/catalog_header.dart';
import 'widgets/catalog_sort_capsule.dart';
import 'widgets/library_desktop_spotlight.dart';
import 'widgets/library_filters_panel.dart';
import 'widgets/spotlight_scale.dart';
import 'widgets/library_tv_view.dart';
import '../../widgets/global/sliver_scroll_end.dart';

/// Les libellés de tri, lus par `tr()` à l'affichage.
@visibleForTesting
Iterable<String> get librarySortLabels => librarySortOptions.values;

/// L'icône d'une bibliothèque, d'après ce qu'elle contient. [selected] rend la
/// variante pleine, celle d'un onglet actif.
IconData libraryIcon(LibraryKind kind, {bool selected = false}) =>
    switch (kind) {
      LibraryKind.movies => selected ? AppIcons.movieSelected : AppIcons.movie,
      LibraryKind.shows => selected ? AppIcons.seriesSelected : AppIcons.series,
      // Pas de variante pleine dans le jeu d'icônes : l'onglet actif se lit à
      // sa couleur et à la graisse de son nom.
      LibraryKind.other => AppIcons.folder,
    };

/// Le catalogue d'une bibliothèque du serveur, sous le nom que son
/// administrateur lui a donné (ADR-0058).
///
/// Un seul écran pour toutes : ce qui change d'une bibliothèque à l'autre est
/// son nom et la fiche qu'ouvre une affiche, pas la grille.
class LibraryScreen extends StatefulWidget {
  final MediaLibrary library;
  final bool embedded;

  const LibraryScreen(
      {super.key, required this.library, this.embedded = false});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryFilters _filters = LibraryFilters.defaults;
  bool _loadScheduled = false;

  /// Le panneau des filtres, ouvert à droite de la grille sur grand écran.
  /// Ouvert, il prend la place du volet du titre survolé.
  bool _filtersOpen = false;

  /// Garde la grille (et sa position de défilement) quand le volet du
  /// titre survolé s'efface pour le panneau des filtres, puis revient.
  final _gridKey = GlobalKey();

  /// Le titre que le volet du bureau présente : le dernier que le pointeur
  /// ou le clavier a désigné. Un `ValueNotifier` : survoler une affiche ne
  /// redessine que la fiche, pas la grille.
  final ValueNotifier<int?> _presented = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _presented.dispose();
    super.dispose();
  }

  bool get _isShows => widget.library.kind == LibraryKind.shows;

  /// Charge le catalogue s'il manque : à l'ouverture, et de nouveau quand un
  /// changement de serveur l'a vidé sous un onglet resté monté.
  void _loadIfMissing(LibraryProvider lp) {
    final library = widget.library;
    if (_loadScheduled ||
        lp.hasLoadedLibrary(library) ||
        lp.isLoadingLibrary(library) ||
        lp.libraryError(library) != null) {
      return;
    }
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (mounted) lp.loadLibrary(widget.library);
    });
  }

  List<LibraryEntry> _entries(LibraryProvider lp) {
    final List<LibraryEntry> entries = _isShows
        ? [
            for (final show in lp.showsOf(widget.library))
              (media: show, movie: null)
          ]
        : [
            for (final item in lp.moviesOf(widget.library))
              (media: item.media, movie: item),
          ];
    return _filters.apply(entries, titleKey: titleSortKey);
  }

  /// Le bouton « Filtres » de l'en-tête : le panneau à droite sur grand
  /// écran, une feuille du bas sur téléphone.
  void _openFilters() {
    if (!AppLayout.isCompact(context)) {
      setState(() => _filtersOpen = true);
      return;
    }
    LibraryFiltersPanel.show(
      context,
      filters: _filters,
      isShows: _isShows,
      onChanged: (f) => setState(() => _filters = f),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LibraryProvider>(context);
    final library = widget.library;
    _loadIfMissing(lp);

    final compact = AppLayout.isCompact(context);
    final error = lp.libraryError(library);
    // Rien de reçu encore se lit comme un chargement, pas comme « vide ».
    final loading =
        lp.isLoadingLibrary(library) || !lp.hasLoadedLibrary(library);
    final entries = _entries(lp);
    final count = entries.length;
    final sortOptions = {
      for (final option in librarySortOptions.entries)
        // Une série n'a pas de position de lecture à elle.
        if (!_isShows || option.key != LibrarySort.progress)
          option.key: option.value,
    };

    // Sur téléviseur, la fiche du titre focalisé à gauche et la grille à
    // droite (ADR-0125), dès le chargement. L'erreur et la bibliothèque
    // vide gardent la page commune.
    if (TvScope.of(context) &&
        error == null &&
        (loading || entries.isNotEmpty)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: LibraryTvView(
          title: ShellTabs.label(library),
          countLabel: loading
              ? null
              : tr('{0} titre{1}', [count, count > 1 ? 's' : '']),
          entries: loading ? const [] : entries,
          order: _filters.sort,
          embedded: widget.embedded,
          sortControl: CatalogSortCapsule<LibrarySort>(
            sortOptions: sortOptions,
            sort: _filters.sort,
            onSortChanged: (v) =>
                setState(() => _filters = _filters.copyWith(sort: v)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: error != null
          ? ErrorStateView(
              message: error,
              onRetry: () => lp.loadLibrary(library),
            )
          // Sur un grand écran du bureau, la fiche du titre survolé à gauche,
          // comme dans la recherche (ADR-0140).
          : LayoutBuilder(builder: (context, box) {
              // Le panneau des filtres ouvert prend la place du volet : la
              // grille passe à gauche, le panneau à droite.
              final panelOpen = _filtersOpen && !compact && !TvMode.isTv;
              final spotlight = !compact &&
                  !panelOpen &&
                  !loading &&
                  entries.isNotEmpty &&
                  LibraryDesktopSpotlight.fits(box.maxWidth);
              final grid = KeyedSubtree(
                key: _gridKey,
                child: _grid(context, lp, entries, loading, count, sortOptions,
                    spotlight: spotlight,
                    // À côté du volet, les affiches du mur d'un téléviseur
                    // (ADR-0156).
                    tileScale: spotlight
                        ? SpotlightScale.tileScaleFor(box.maxWidth)
                        : 1),
              );
              final page = spotlight
                  ? LibraryDesktopSpotlight(
                      entries: entries,
                      presented: _presented,
                      child: grid,
                    )
                  : grid;
              if (compact || TvMode.isTv) return page;
              void close() => setState(() => _filtersOpen = false);
              return OnyxFilterDock(
                top: shellTabTopInset(context, embedded: widget.embedded),
                onDismiss: close,
                page: page,
                panel: panelOpen
                    ? LibraryFiltersPanel(
                        filters: _filters,
                        isShows: _isShows,
                        onChanged: (f) => setState(() => _filters = f),
                        onClose: close,
                      )
                    : null,
              );
            }),
    );
  }

  Widget _grid(
    BuildContext context,
    LibraryProvider lp,
    List<LibraryEntry> entries,
    bool loading,
    int count,
    Map<LibrarySort, String> sortOptions, {
    required bool spotlight,
    double tileScale = 1,
  }) {
    final library = widget.library;
    final horizontalPadding = AppLayout.pagePadding(context);
    final compact = AppLayout.isCompact(context);
    return PosterGridZoomRegion(
      split: spotlight,
      child: CustomScrollView(
        scrollCacheExtent: AppLayout.imageCacheExtent(context),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                shellTabTopInset(context, embedded: widget.embedded),
                horizontalPadding,
                0,
              ),
              // Pendant le chargement, le tri n'a rien à trier, et il
              // était la seule cible sous l'en-tête : Bas depuis
              // l'onglet sautait au bout de la ligne, sur ce petit
              // menu, et l'on croyait l'appui perdu (vu au simulateur
              // Apple TV, phase 2 de la refonte dpad). La grille
              // arrivée, Bas tombait alors sur l'affiche la plus à
              // droite, sous le menu.
              child: ExcludeFocus(
                excluding: loading,
                child: CatalogHeader<LibrarySort>(
                  title: ShellTabs.label(library),
                  countLabel: loading
                      ? null
                      : tr('{0} titre{1}', [count, count > 1 ? 's' : '']),
                  sortOptions: sortOptions,
                  sort: _filters.sort,
                  onSortChanged: (v) =>
                      setState(() => _filters = _filters.copyWith(sort: v)),
                  compact: compact,
                  // Le téléviseur garde le menu de tri : le panneau ne s'y
                  // ouvre pas.
                  onFilters: TvMode.isTv ? null : _openFilters,
                  activeFilters: _filters.activeCount,
                ),
              ),
            ),
          ),
          if (loading)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  horizontalPadding, 24, horizontalPadding, 48),
              sliver: const PosterGridSkeleton(),
            )
          else if (entries.isEmpty && _filters.activeCount > 0)
            SliverFillRemaining(
              child: EmptyStateView(
                icon: AppIcons.filters,
                title: tr('Aucun titre ne correspond'),
                message: tr('Aucun titre de cette bibliothèque ne passe '
                    'ces filtres.'),
                actionLabel: tr('Effacer les filtres'),
                actionIcon: AppIcons.close,
                onAction: () => setState(() => _filters = _filters.cleared()),
              ),
            )
          else if (entries.isEmpty)
            SliverFillRemaining(
              child: EmptyStateView(
                icon: libraryIcon(library.kind),
                title: tr('Bibliothèque vide'),
                message: tr('Les fichiers ajoutés au dossier de cette '
                    'bibliothèque apparaissent ici d’eux-mêmes.'),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                SliverScrollEnd.extentOf(context),
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) => SliverGrid(
                  gridDelegate: AppLayout.posterGridDelegate(
                    context,
                    constraints.crossAxisExtent,
                    compact: compact,
                    withMeta: false,
                    tileScale: tileScale,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = entries[index];
                      final movie = entry.movie;
                      final card = MediaCard(
                        media: entry.media,
                        item: movie,
                        watched: movie?.isFinished ?? false,
                        progress: movie == null || movie.isFinished
                            ? null
                            : movie.percentWatched,
                        // Le volet dit déjà le titre survolé.
                        showDetails: !spotlight,
                      );
                      if (!spotlight) return card;
                      return LibrarySpotlightTarget(
                        media: entry.media,
                        presented: _presented,
                        child: card,
                      );
                    },
                    childCount: entries.length,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
