import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../navigation/detail_flight.dart';
import '../../../navigation/search_route_observer.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../services/api_client.dart';
import '../../../services/unavailable_titles_search.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/empty_state.dart';
import '../../../widgets/global/media_card.dart';
import '../../../widgets/global/poster_card.dart';
import '../../../widgets/global/poster_grid_display_menu.dart';
import '../../../widgets/global/poster_grid_zoom_region.dart';
import '../../../widgets/global/staggered_entrance.dart';
import '../../library/widgets/library_spotlight_prefetch.dart';
import '../../player/player_screen.dart';
import '../../requests/request_availability.dart';
import '../../requests/request_detail_launch.dart';
import '../../requests/widgets/request_media_card.dart';
import '../search_shelves.dart';
import '../search_chips.dart';
import 'desktop_search_chips.dart';
import 'desktop_search_controller.dart';
import '../search_layout.dart';
import 'desktop_search_spotlight.dart';
import '../recent_searches.dart';

/// Les résultats de la recherche du bureau, sous le voile de
/// `DesktopSearchRoute` (ADR-0139).
///
/// La recherche se tape dans l'en-tête, qui reste au-dessus : la feuille lit
/// [SearchProvider.query] et n'a pas de champ à elle. Rien de tapé, elle
/// propose les recherches récentes et les derniers ajouts. Sinon, les
/// pastilles, la grille de la bibliothèque, puis celle des titres absents
/// (ADR-0129) ; à droite, l'aperçu du titre sélectionné.
class DesktopSearchSheet extends StatefulWidget {
  const DesktopSearchSheet({
    super.key,
    required this.controller,
    required this.recents,
    required this.onPickRecent,
    required this.onReturn,
  });

  final DesktopSearchController controller;
  final RecentSearches recents;

  /// Une recherche récente choisie : le champ de l'en-tête la reprend.
  final ValueChanged<String> onPickRecent;

  /// La feuille revient au premier plan (fiche refermée) : le champ de
  /// l'en-tête reprend le focus, pour qu'on continue de taper.
  final VoidCallback onReturn;

  /// En dessous, le volet du titre sélectionné prendrait la place de deux
  /// colonnes d'affiches sur une grille qui n'en a déjà que quatre : il se
  /// retire.
  static const double spotlightMinWidth = 1100;

  /// Les derniers ajouts proposés quand rien n'est tapé : trois lignes d'une
  /// grille de bureau.
  static const int recentCount = 24;

  @override
  State<DesktopSearchSheet> createState() => _DesktopSearchSheetState();
}

class _DesktopSearchSheetState extends State<DesktopSearchSheet> {
  /// Ce que le catalogue de demandes connaît pour la recherche affichée.
  late final UnavailableTitlesSearch _catalog =
      UnavailableTitlesSearch(context.read<ApiClient>());

  final ScrollController _scroll = ScrollController();

  /// La carte sélectionnée, telle qu'elle s'est construite : Entrée en fait
  /// partir l'envol de l'affiche, et les flèches la ramènent à l'écran.
  BuildContext? _selectedCell;

  /// La dernière recherche affichée, voir [_shownQuery].
  String _lastQuery = '';

  /// Vrai tant que la feuille est au premier plan.
  bool _current = true;

  int _revealedIndex = -1;

  @override
  void initState() {
    super.initState();
    _catalog.addListener(_onCatalogAnswered);
    widget.controller.attach(_activate);
    widget.controller.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().ensureCatalogLoaded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current == _current) return;
    _current = current;
    if (current) {
      // Au retour d'une fiche de demande, le statut d'un titre a pu
      // changer : « Indispo » devient « Demandé ».
      _catalog.refresh();
      widget.onReturn();
    } else {
      // Une fiche s'ouvre par-dessus : la recherche a servi.
      widget.recents.remember(_lastQuery);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    widget.controller.detach(_activate);
    _catalog.removeListener(_onCatalogAnswered);
    _catalog.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onCatalogAnswered() => setState(() {});

  /// La recherche tapée, figée dès que la feuille se referme : sans cela la
  /// grille laissait place aux derniers ajouts pendant le fondu de sortie.
  String _shownQuery(BuildContext context) {
    final typed = context.watch<SearchProvider>().query.trim();
    if (ModalRoute.of(context)?.isActive ?? true) _lastQuery = typed;
    return _lastQuery;
  }

  // ---------------------------------------------------------------------
  // Sélection au clavier

  void _onSelectionChanged() {
    final controller = widget.controller;
    if (!controller.browsing) {
      _revealedIndex = -1;
      return;
    }
    if (controller.selected == _revealedIndex) return;
    _revealedIndex = controller.selected;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Ramène la carte sélectionnée à l'écran, au plus court : la page ne bouge
  /// pas tant qu'elle y est déjà.
  ///
  /// Le défilement d'une sélection qui n'a pas le focus : dpad ne la voit
  /// pas, et elle n'existe pas sur téléviseur (ADR-0110).
  void _reveal() {
    final cell = _selectedCell;
    if (!mounted || cell == null || !cell.mounted || !_scroll.hasClients) {
      return;
    }
    final box = cell.findRenderObject();
    if (box == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    const margin = 24.0;
    final atTop = viewport.getOffsetToReveal(box, 0).offset - margin;
    final atBottom = viewport.getOffsetToReveal(box, 1).offset + margin;
    final position = _scroll.position;
    final target = position.pixels
        .clamp(atBottom, atTop < atBottom ? atBottom : atTop)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    final duration = AppMotion.move(context);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: duration, curve: AppMotion.curve);
    }
  }

  // ---------------------------------------------------------------------
  // Ouvrir, lancer

  /// Entrée ou Ctrl + Entrée, tapés dans le champ de l'en-tête.
  void _activate({required bool play}) {
    final hit = widget.controller.current;
    if (hit == null) return;
    if (play && hit is LibraryHit && hit.media.type == MediaType.movie) {
      _play(hit.media);
    } else {
      _open(hit);
    }
  }

  /// La fiche du titre, depuis sa carte quand elle est à l'écran.
  void _open(SearchHit hit) {
    final cell = _selectedCell;
    final fromCard = identical(hit, widget.controller.current) &&
        cell != null &&
        cell.mounted;
    final origin = fromCard ? cell : context;
    switch (hit) {
      case LibraryHit(:final media):
        openMediaDetail(
          origin,
          media,
          item: media.type == MediaType.movie
              ? context.read<LibraryProvider>().movieItemFor(media.id)
              : null,
          measureCard: fromCard,
        );
      case UnavailableHit(:final item):
        openRequestDetail(origin, item, measureCard: fromCard);
    }
  }

  void _play(Media media) {
    widget.recents.remember(_lastQuery);
    final item = context.read<LibraryProvider>().movieItemFor(media.id) ??
        HomeMediaItem(
          media: media,
          currentPositionSeconds: 0,
          duration: media.duration,
          isFinished: false,
        );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        settings:
            const RouteSettings(name: SearchRouteObserver.playerRouteName),
        builder: (_) => PlayerScreen(media: item),
      ),
    );
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LibraryProvider>();
    final query = _shownQuery(context);
    // La recherche vient de l'en-tête : c'est ici que le catalogue l'apprend.
    // L'appel ne prévient personne sur le coup, la construction peut le faire.
    _catalog.search(query, enabled: canRequestMedia(context, listen: true));

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        // La hauteur de l'en-tête, que la coquille donne aux pages ouvertes.
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: ValueListenableBuilder<SearchFilter>(
          valueListenable: widget.controller.filter,
          builder: (context, filter, _) {
            final layout = query.isEmpty
                ? SearchLayout.recent(SearchShelves.recentlyAdded(
                    lp, DesktopSearchSheet.recentCount))
                : SearchLayout.of(
                    SearchShelves.of(lp, query,
                        catalog: _catalog.resultsFor(query)),
                    filter,
                  );
            widget.controller.show(layout);
            final results = _results(context, query, layout, filter);
            // À gauche, le titre sélectionné, comme le volet d'une
            // bibliothèque sur téléviseur ; les affiches commencent après
            // lui, par-dessus son image qui déborde et s'efface. Toujours la
            // même pile, volet ou non : la grille garde son défilement quand
            // la fenêtre passe le seuil.
            final pane = DesktopSearchSpotlight.paneWidth(context);
            return LayoutBuilder(
              builder: (context, box) {
                final spotlight = layout.hits.isNotEmpty &&
                    box.maxWidth >= DesktopSearchSheet.spotlightMinWidth;
                return Stack(
                  children: [
                    if (spotlight)
                      Positioned(
                        key: const ValueKey('spotlight'),
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: pane + DesktopSearchSpotlight.overhang,
                        child: IgnorePointer(
                          child: DesktopSearchSpotlight(
                            controller: widget.controller,
                          ),
                        ),
                      ),
                    Positioned(
                      key: const ValueKey('results'),
                      left: spotlight ? pane - _gutter(context) : 0,
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: results,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _results(
    BuildContext context,
    String query,
    SearchLayout layout,
    SearchFilter filter,
  ) {
    if (query.isNotEmpty && layout.total == 0) {
      return EmptyStateView(
        icon: AppIcons.search,
        title: tr('Aucun résultat'),
        message: tr('Aucun film ou série ne correspond à « {0} ».', [query]),
      );
    }
    final padding = _gutter(context);
    final library = layout.library;
    final unavailable = layout.unavailable;

    return StaggeredEntranceScope(
      // La cascade rejoue quand la grille change de nature (derniers ajouts,
      // résultats, autre pastille), pas à chaque frappe.
      playKey: (query.isEmpty, filter),
      maxAnimated: 12,
      child: PosterGridZoomRegion(
        child: CustomScrollView(
          controller: _scroll,
          scrollCacheExtent: AppLayout.imageCacheExtent(context),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding, 20, padding, 0),
              sliver: SliverToBoxAdapter(
                child: query.isEmpty
                    ? _EmptyQueryHeader(
                        recents: widget.recents,
                        onPick: widget.onPickRecent,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: DesktopSearchChips(
                              controller: widget.controller,
                              layout: layout,
                              showUnavailable:
                                  canRequestMedia(context, listen: true),
                            ),
                          ),
                          const PosterGridDisplayMenu(compact: false),
                        ],
                      ),
              ),
            ),
            if (library.isNotEmpty)
              _grid(
                padding: padding,
                start: 0,
                count: library.length,
                builder: (index, highlight) {
                  final media = library[index];
                  final lp = context.read<LibraryProvider>();
                  final movie = media.type == MediaType.movie;
                  return MediaCard(
                    media: media,
                    showDetails: false,
                    highlight: highlight,
                    progress: movie ? lp.movieProgressFor(media.id) : null,
                    watched: movie &&
                        (lp.movieItemFor(media.id)?.isFinished ?? false),
                    item: movie ? lp.movieItemFor(media.id) : null,
                  );
                },
              ),
            if (unavailable.isNotEmpty) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 28, padding, 0),
                sliver: SliverToBoxAdapter(
                  child: _SectionTitle(
                    title: tr('Pas sur le serveur'),
                    subtitle: tr('Ouvrez un titre pour le demander'),
                  ),
                ),
              ),
              _grid(
                padding: padding,
                start: library.length,
                count: unavailable.length,
                builder: (index, highlight) => RequestMediaCard(
                  item: unavailable[index],
                  marksUnavailable: true,
                  showDetails: false,
                  highlight: highlight,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  /// La marge de côté des résultats.
  static double _gutter(BuildContext context) =>
      AppLayout.pagePadding(context).clamp(24.0, 40.0);

  /// Une grille d'affiches dont les cartes portent les rangs [start] à
  /// [start] + [count] - 1 de la sélection.
  Widget _grid({
    required double padding,
    required int start,
    required int count,
    required Widget Function(int index, PosterHighlight highlight) builder,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padding, 18, padding, 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final grid = AppLayout.posterGridDelegate(
            context,
            constraints.crossAxisExtent,
            compact: false,
            withMeta: false,
          );
          final columns = grid is SliverGridDelegateWithFixedCrossAxisCount
              ? grid.crossAxisCount
              : 1;
          widget.controller.layoutColumns(columns);
          return SliverGrid(
            gridDelegate: grid,
            delegate: SliverChildBuilderDelegate(
              (context, index) => StaggeredEntrance(
                index: start + index,
                // En diagonale, ligne et colonne ensemble, comme la page de
                // résultats du téléphone.
                step: index ~/ columns + index % columns,
                child: _SelectableCell(
                  index: start + index,
                  controller: widget.controller,
                  onSelectedBuilt: (cell) => _selectedCell = cell,
                  builder: (highlight) => builder(index, highlight),
                ),
              ),
              childCount: count,
            ),
          );
        },
      ),
    );
  }
}

/// Une carte de la grille qui suit la sélection : seule elle se reconstruit
/// quand la sélection arrive ou repart.
class _SelectableCell extends StatelessWidget {
  const _SelectableCell({
    required this.index,
    required this.controller,
    required this.onSelectedBuilt,
    required this.builder,
  });

  final int index;
  final DesktopSearchController controller;
  final ValueChanged<BuildContext> onSelectedBuilt;
  final Widget Function(PosterHighlight highlight) builder;

  @override
  Widget build(BuildContext context) {
    final hits = controller.hits;
    final hit = index < hits.length ? hits[index] : null;
    final cell = MouseRegion(
      onEnter: (_) => controller.point(index),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final selected = controller.selected == index;
          if (selected) onSelectedBuilt(context);
          return builder(
            !selected
                ? PosterHighlight.none
                : controller.browsing
                    ? PosterHighlight.ringed
                    : PosterHighlight.lifted,
          );
        },
      ),
    );
    // La fiche du volet et son logo sont prêts avant le survol (ADR-0142).
    return switch (hit) {
      LibraryHit(:final media) =>
        LibrarySpotlightWarmup(media: media, child: cell),
      _ => cell,
    };
  }
}

/// Rien de tapé : les recherches récentes, puis le titre des derniers ajouts.
class _EmptyQueryHeader extends StatelessWidget {
  const _EmptyQueryHeader({required this.recents, required this.onPick});

  final RecentSearches recents;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recents,
      builder: (context, _) {
        final items = recents.items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: _SectionTitle(title: tr('Recherches récentes')),
                  ),
                  ExcludeFocus(
                    child: TextButton(
                      onPressed: recents.clear,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: Text(tr('Effacer')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final query in items)
                    RecentSearchChip(query: query, onTap: () => onPick(query)),
                ],
              ),
              const SizedBox(height: 28),
            ],
            Row(
              children: [
                Expanded(child: _SectionTitle(title: tr('Ajoutés récemment'))),
                const PosterGridDisplayMenu(compact: false),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: AppType.headline,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: AppType.subhead,
            ),
          ),
        ],
      ],
    );
  }
}
