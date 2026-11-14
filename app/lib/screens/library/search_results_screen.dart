import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/media_request.dart';
import '../../models/models.dart';
import '../../providers/library_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/api_client.dart';
import '../../services/unavailable_titles_search.dart';
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
import '../requests/request_availability.dart';
import '../requests/widgets/request_media_card.dart';
import '../search/search_shelves.dart';

/// Full-page grid of catalog results, updated live in real time as the user types.
///
/// Sous les titres de la bibliothèque, ceux que le serveur n'a pas : affiches
/// voilées sous leur propre titre, qui ouvrent la fiche de demande (ADR-0129).
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

  /// Ce que le catalogue de demandes connaît pour la recherche affichée.
  late final UnavailableTitlesSearch _catalog =
      UnavailableTitlesSearch(context.read<ApiClient>());

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _controller.addListener(_onQueryChanged);
    _catalog.addListener(_onCatalogAnswered);
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

  void _onCatalogAnswered() => setState(() {});

  /// Vrai tant que la page est au premier plan.
  bool _current = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Au retour d'une fiche de demande, le statut d'un titre a pu changer :
    // « Indispo » devient « Demandé ».
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_current) _catalog.refresh();
    _current = current;
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _catalog.removeListener(_onCatalogAnswered);
    _catalog.dispose();
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
    // La recherche vient du champ de la page ou de la barre de navigation :
    // c'est ici, où elles se rejoignent, que le catalogue l'apprend. L'appel
    // ne prévient personne sur le coup, la construction peut le faire.
    _catalog.search(query, enabled: canRequestMedia(context, listen: true));
    final shelves = SearchShelves.of(
      lp,
      query,
      catalog: _catalog.resultsFor(query),
    );
    final results = shelves.library;
    final unavailable = shelves.unavailable;

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
          : shelves.isEmpty
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
                                          results.isEmpty
                                              ? tr('Rien dans la bibliothèque')
                                              : tr('{0} résultat{1}', [
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
                          // Sans titre de la bibliothèque, la grille vide ne
                          // garde pas de hauteur au-dessus du rayon des
                          // absents. Ses marges de côté restent : les deux
                          // grilles partagent le zoom de la page, qui part de
                          // leur largeur (`PosterGridZoom.apply`).
                          padding: results.isEmpty
                              ? EdgeInsets.symmetric(
                                  horizontal: horizontalPadding)
                              : EdgeInsets.fromLTRB(horizontalPadding, 20,
                                  horizontalPadding, unavailable.isEmpty ? 48 : 8),
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
                        if (unavailable.isNotEmpty)
                          ..._unavailableShelf(unavailable, horizontalPadding),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// Le rayon des titres que le serveur n'a pas, sous ceux de la
  /// bibliothèque : son titre, puis ses affiches voilées.
  List<Widget> _unavailableShelf(
    List<RequestMediaItem> unavailable,
    double horizontalPadding,
  ) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Pas sur le serveur'),
                style: const TextStyle(
                  fontSize: AppType.headline,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Ouvrez un titre pour le demander'),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: AppType.subhead,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding:
            EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 48),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) => SliverGrid(
            gridDelegate: AppLayout.posterGridDelegate(
              context,
              constraints.crossAxisExtent,
              compact: AppLayout.isCompact(context),
              withMeta: false,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => RequestMediaCard(
                item: unavailable[index],
                marksUnavailable: true,
              ),
              childCount: unavailable.length,
            ),
          ),
        ),
      ),
    ];
  }
}
