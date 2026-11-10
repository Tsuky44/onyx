import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/library_provider.dart';
import '../../providers/search_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/empty_state.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/media_card.dart';
import '../../widgets/global/poster_grid_zoom_region.dart';
import '../../widgets/global/staggered_entrance.dart';
import '../../widgets/global/poster_grid_display_menu.dart';
import '../../widgets/global/search_results_route.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

/// Full-page grid of catalog results, updated live in real time as the user types.
class SearchResultsScreen extends StatefulWidget {
  final String query;
  final bool autofocusField;

  /// Vrai quand la page n'a pas de champ : elle affiche la recherche tapée
  /// dans la barre de navigation, restée à l'écran au-dessus d'elle
  /// ([SearchProvider.query]). Deux champs de recherche l'un sous l'autre
  /// auraient laissé le doute sur celui qui commande.
  final bool followsHeader;

  /// Vrai quand la page a été ouverte par la frappe dans la barre : vider son
  /// champ la referme et rend la page d'avant, comme sur grand écran. Faux
  /// pour la recherche ouverte à vide (télévision), qu'un champ vide ne doit
  /// pas refermer.
  final bool closesWhenEmptied;

  const SearchResultsScreen({
    super.key,
    this.query = '',
    this.autofocusField = false,
    this.closesWhenEmptied = false,
  }) : followsHeader = false;

  const SearchResultsScreen.followingHeader({super.key})
      : query = '',
        autofocusField = false,
        closesWhenEmptied = false,
        followsHeader = true;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final TextEditingController _controller;
  final FocusNode _fieldNode = FocusNode(debugLabel: 'search-results-field');

  /// La dernière recherche affichée, voir [_shownQuery].
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _controller.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LibraryProvider>().ensureCatalogLoaded();
      }
    });
  }

  void _onQueryChanged() {
    if (widget.closesWhenEmptied && _controller.text.trim().isEmpty) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.of(context).pop();
        return;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  /// La recherche tapée, figée dès que la page se referme.
  ///
  /// C'est le champ vidé qui la referme : sans cela la grille laissait place
  /// à l'état vide pendant le fondu de sortie.
  String _shownQuery(BuildContext context) {
    final typed = widget.followsHeader
        ? context.watch<SearchProvider>().query.trim()
        : _controller.text.trim();
    if (ModalRoute.of(context)?.isActive ?? true) _lastQuery = typed;
    return _lastQuery;
  }

  /// Les pas de la cascade en diagonale : de quoi couvrir un premier écran
  /// de bureau (neuf colonnes sur trois lignes) sans dépasser 650 ms.
  static const _cascadeSteps = 12;

  /// Pendant l'ouverture, les affiches attendent que l'en-tête commence à se
  /// poser ; une grille qui réapparaît plus tard (après « Aucun résultat »)
  /// part tout de suite.
  Duration _cascadeDelay(BuildContext context) {
    final route = ModalRoute.of(context);
    final opening = route is SearchResultsRoute &&
        route.animation?.status == AnimationStatus.forward;
    return opening
        ? AppMotion.reveal * SearchResultsRoute.headerStart
        : Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LibraryProvider>();
    final isTv = TvScope.of(context) || TvMode.isTv;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width >= 900 ? 48.0 : 16.0;
    final query = _shownQuery(context);
    final results = query.isEmpty ? const <Media>[] : lp.searchCatalog(query);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: !isTv,
        titleSpacing:
            isTv ? horizontalPadding : NavigationToolbar.kMiddleSpacing,
        title: widget.followsHeader
            ? Text(tr('Recherche'))
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: TvDeferredKeyboard(
                  fieldFocusNode: _fieldNode,
                  autofocus: widget.autofocusField,
                  borderRadius: BorderRadius.circular(17),
                  builder: (context, focusNode, canRequestFocus) =>
                      GlassSearchInput(
                    controller: _controller,
                    focusNode: focusNode,
                    canRequestFocus: canRequestFocus,
                    // Ouverte par la frappe, la page reçoit le premier caractère
                    // déjà tapé : le sélectionner au focus (défaut du bureau et du
                    // web) le ferait remplacer par le suivant.
                    selectAllOnFocus: widget.autofocusField ? false : null,
                    onClear: () {
                      _controller.clear();
                    },
                    onSubmitted: (_) {
                      if (results.isNotEmpty) {
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                        FocusScope.of(context)
                            .focusInDirection(TraversalDirection.down);
                      }
                    },
                    hint: tr('Rechercher un film ou une série…'),
                    focused: focusNode.hasFocus,
                    hasText: _controller.text.isNotEmpty,
                  ),
                ),
              ),
      ),
      body: query.isEmpty
          ? SearchResultsEntrance(
              child: EmptyStateView(
                icon: AppIcons.search,
                title: tr('Rechercher'),
                message:
                    tr('Recherchez et demandez de nouveaux films et séries'),
              ),
            )
          : results.isEmpty
              ? SearchResultsEntrance(
                  child: EmptyStateView(
                    icon: AppIcons.search,
                    title: tr('Aucun résultat'),
                    message: tr('Aucun film ou série ne correspond à « {0} ».',
                        [query]),
                  ),
                )
              // Les affiches suivent l'en-tête en cascade
              // (`SearchResultsRoute`). La clé est fixe : la cascade ne rejoue
              // pas à chaque frappe, seulement quand la grille réapparaît.
              : StaggeredEntranceScope(
                  playKey: 'search-results',
                  maxAnimated: _cascadeSteps,
                  delay: _cascadeDelay(context),
                  child: PosterGridZoomRegion(
                    child: CustomScrollView(
                      scrollCacheExtent: AppLayout.imageCacheExtent(context),
                      slivers: [
                        SliverToBoxAdapter(
                          child: SearchResultsEntrance(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                  horizontalPadding, 8, horizontalPadding, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr('Résultats pour « {0} »', [query]),
                                          style: const TextStyle(
                                            fontSize: AppType.headline,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          tr('{0} résultat{1}', [
                                            results.length,
                                            results.length > 1 ? 's' : ''
                                          ]),
                                          style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: AppType.subhead),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PosterGridDisplayMenu(
                                      compact: AppLayout.isCompact(context)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              horizontalPadding, 20, horizontalPadding, 48),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final grid = AppLayout.posterGridDelegate(
                                context,
                                constraints.crossAxisExtent,
                                compact: AppLayout.isCompact(context),
                                withMeta: false,
                              );
                              final columns = grid
                                      is SliverGridDelegateWithFixedCrossAxisCount
                                  ? grid.crossAxisCount
                                  : 1;
                              return SliverGrid(
                                gridDelegate: grid,
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final media = results[index];
                                    return StaggeredEntrance(
                                      index: index,
                                      // En diagonale, ligne et colonne
                                      // ensemble : tout le premier écran
                                      // arrive, dernière ligne comprise, dans
                                      // le temps qu'il fallait à seize cartes
                                      // l'une après l'autre.
                                      step: index ~/ columns + index % columns,
                                      child: MediaCard(
                                        media: media,
                                        // Jamais sous l'en-tête : la première
                                        // affiche prendrait le focus au champ où
                                        // l'on tape.
                                        autofocus: !widget.autofocusField &&
                                            !widget.followsHeader &&
                                            index == 0,
                                        progress: media.type == MediaType.movie
                                            ? lp.movieProgressFor(media.id)
                                            : null,
                                        watched:
                                            media.type == MediaType.movie &&
                                                (lp
                                                        .movieItemFor(media.id)
                                                        ?.isFinished ??
                                                    false),
                                        item: media.type == MediaType.movie
                                            ? lp.movieItemFor(media.id)
                                            : null,
                                      ),
                                    );
                                  },
                                  childCount: results.length,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
