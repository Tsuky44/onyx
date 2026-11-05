import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_request.dart';
import '../../models/request_catalog_filters.dart';
import '../../providers/media_requests_provider.dart';
import '../../desktop_window.dart';
import '../../theme/app_colors.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import '../../utils/poster_url.dart';
import '../../widgets/global/app_network_image.dart';
import '../../widgets/global/empty_state.dart';
import '../../widgets/global/poster_grid_zoom_region.dart';
import '../../widgets/global/poster_grid_display_menu.dart';
import '../../widgets/global/staggered_entrance.dart';
import '../../services/api_client.dart';
import 'my_requests_screen.dart';
import 'widgets/request_filters_sheet.dart';
import 'widgets/request_media_card.dart';
import 'widgets/request_type_switch.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

class RequestsScreen extends StatefulWidget {
  final bool embedded;

  const RequestsScreen({super.key, this.embedded = false});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _searchController = TextEditingController();

  final _scrollController = ScrollController();

  String _draftType = 'all';
  RequestCatalogFilters _draftFilters = RequestCatalogFilters.defaults;
  Timer? _searchDebounce;

  /// Le serveur relaie les demandes du compte chez OnyxHub (ADR-0073).
  bool _hasMyRequests = false;

  static const _searchDebounceDuration = Duration(milliseconds: 400);

  /// Largeur d'une cellule de la grille et densité de l'écran, relevées au
  /// dernier rendu : les affiches préchargées doivent être décodées à la
  /// taille où les cartes les dessinent, sinon elles tombent dans une autre
  /// entrée du cache mémoire.
  double? _cellWidth;
  double _devicePixelRatio = 1;

  late final MediaRequestsProvider _provider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _provider = context.read<MediaRequestsProvider>();
    _provider.onPagePrefetched = _warmPosters;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDraftFromProvider(_provider);
      _provider.load();
      _checkMyRequests();
    });
  }

  Future<void> _checkMyRequests() async {
    try {
      final supported = await context.read<ApiClient>().supportsMyRequests();
      if (mounted && supported) setState(() => _hasMyRequests = true);
    } catch (_) {
      // Serveur muet : l'entrée « Mes demandes » reste cachée, l'onglet marche.
    }
  }

  void _syncDraftFromProvider(MediaRequestsProvider provider) {
    _draftType = provider.type;
    _draftFilters = provider.filters;
    _searchController.text = provider.query;
  }

  /// Les affiches d'une page préchargée, téléchargées et décodées avant
  /// qu'on l'atteigne : le lot s'affiche complet au lieu de se remplir carte
  /// par carte.
  void _warmPosters(List<RequestMediaItem> items) {
    final width = _cellWidth;
    if (!mounted || width == null) return;
    for (final item in items) {
      unawaited(AppNetworkImage.precache(
        cardPosterUrl(item.posterUrl),
        devicePixelRatio: _devicePixelRatio,
        decodeWidth: width,
      ));
    }
  }

  @override
  void dispose() {
    if (_provider.onPagePrefetched == _warmPosters) {
      _provider.onPagePrefetched = null;
    }
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, _runSearch);
  }

  Future<void> _runSearch() async {
    if (!mounted) return;
    final provider = context.read<MediaRequestsProvider>();
    final nextQuery = _searchController.text.trim();
    if (nextQuery == provider.query) return;
    await provider.load(
      query: _searchController.text,
    );
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 900) {
      context.read<MediaRequestsProvider>().loadMore();
    }
  }

  /// Sur un grand écran, une page de résultats peut tenir sans débordement :
  /// aucun événement de défilement n'arrive alors jamais à [_onScroll]. On
  /// enchaîne donc les pages tant que la grille ne remplit pas la vue.
  void _fillViewportIfNeeded() {
    if (!mounted || !_scrollController.hasClients) return;
    final provider = context.read<MediaRequestsProvider>();
    if (provider.isLoading ||
        provider.isLoadingMore ||
        !provider.hasMore ||
        provider.errorMessage != null ||
        provider.items.isEmpty) {
      return;
    }
    if (_scrollController.position.extentAfter < 900) {
      provider.loadMore();
    }
  }

  Future<void> _reloadCatalog() async {
    final provider = context.read<MediaRequestsProvider>();
    await provider.load(
      type: _draftType,
      query: _searchController.text,
      filters: _draftFilters,
    );
    if (mounted) setState(() {});
  }

  void _openAdvancedFilters() {
    RequestFiltersSheet.show(
      context,
      initial: _draftFilters,
      mediaType: _draftType,
      onApply: (filters) {
        setState(() => _draftFilters = filters);
        _reloadCatalog();
      },
    );
  }

  /// Le titre dit ce que montre la grille, comme sur OnyxHub.
  String _title(MediaRequestsProvider provider) {
    if (provider.query.isNotEmpty) {
      return tr('Résultats pour « {0} »', [provider.query]);
    }
    return switch (provider.type) {
      'movie' => tr('Films populaires'),
      'tv' => tr('Séries populaires'),
      _ => tr('Demander'),
    };
  }

  /// Sélecteur de type à gauche, recherche au milieu, menu d'affichage à
  /// droite, sur une seule ligne. Les deux flancs sont de même largeur
  /// (`Expanded`) pour que la recherche reste vraiment centrée. Quand le
  /// flanc gauche ne laisse plus la place au sélecteur, la recherche passe
  /// au-dessus, et le menu d'affichage reste à droite du sélecteur.
  Widget _buildSearchAndTypeRow() {
    final typeSwitch = RequestTypeSwitch(
      selected: _draftType,
      onChanged: (type) {
        setState(() => _draftType = type);
        _reloadCatalog();
      },
    );
    // Sur un téléviseur, les filtres avancés prennent la place du menu
    // d'affichage (absent là-bas) : flottant au-dessus de la grille, le bouton
    // n'était sur la ligne d'aucune affiche, et la télécommande ne l'atteignait
    // jamais.
    final displayMenu = TvMode.isTv
        ? _filtersButton()
        : PosterGridDisplayMenu(compact: AppLayout.isCompact(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        const searchWidth = 360.0;
        final sideWidth = (constraints.maxWidth - searchWidth) / 2;
        if (sideWidth >= RequestTypeSwitch.width + 16) {
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: typeSwitch,
                ),
              ),
              SizedBox(width: searchWidth, child: _buildSearchField()),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: displayMenu,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _buildSearchField(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [typeSwitch, displayMenu],
            ),
          ],
        );
      },
    );
  }

  Widget _filtersButton() => TextButton.icon(
        onPressed: _openAdvancedFilters,
        icon: const Icon(AppIcons.filters),
        label: Text(tr('Filtres avancés')),
      );

  /// Champ de recherche en pilule basse : il ne mange que 40 px de hauteur et
  /// se centre, au lieu de s'étirer sur toute la largeur de la page.
  Widget _buildSearchField() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return TvDeferredKeyboard(
      builder: (context, focusNode, canRequestFocus) => TextField(
        controller: _searchController,
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        onChanged: (_) {
          setState(() {});
          _scheduleSearch();
        },
        onSubmitted: (_) {
          _searchDebounce?.cancel();
          _runSearch();
        },
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: AppType.body),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          hintText: tr('Rechercher un film ou une série…'),
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          prefixIcon: const Icon(AppIcons.search, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 40),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    setState(() {});
                    _runSearch();
                  },
                  tooltip: tr('Effacer'),
                  iconSize: 16,
                  icon: const Icon(AppIcons.close),
                ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MediaRequestsProvider>();
    final horizontalPadding = AppLayout.pagePadding(context);
    final compact = AppLayout.isCompact(context);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _fillViewportIfNeeded());

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: TvMode.isTv
          ? null
          : FloatingActionButton(
              onPressed: _openAdvancedFilters,
              backgroundColor: AppColors.primary,
              tooltip: tr('Filtres avancés'),
              child: const Icon(AppIcons.filters),
            ),
      body: PosterGridZoomRegion(
        child: CustomScrollView(
          scrollCacheExtent: AppLayout.imageCacheExtent(context),
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  shellTabTopInset(context, embedded: widget.embedded),
                  horizontalPadding,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_title(provider),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 26 : 32)),
                        ),
                        if (_hasMyRequests)
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const MyRequestsScreen())),
                            icon: const Icon(AppIcons.request),
                            label: Text(tr('Mes demandes')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        tr('Recherchez et demandez de nouveaux films et séries'),
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    _buildSearchAndTypeRow(),
                    if (!provider.filters.isDefault) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          Chip(
                            label: Text(tr('Filtres avancés actifs')),
                            deleteIcon: const Icon(AppIcons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                _draftFilters = RequestCatalogFilters.defaults;
                              });
                              _reloadCatalog();
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (provider.isLoading)
              const SliverFillRemaining(child: LoadingView())
            else if (provider.errorMessage != null && provider.items.isEmpty)
              SliverFillRemaining(
                child: ErrorStateView(
                    message: provider.errorMessage!, onRetry: _reloadCatalog),
              )
            else if (provider.items.isEmpty)
              SliverFillRemaining(
                child: EmptyStateView(
                  icon: AppIcons.search,
                  title: tr('Aucun média trouvé'),
                  message:
                      tr('Essayez une autre recherche ou un autre filtre.'),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    horizontalPadding, 8, horizontalPadding, 36),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final grid = AppLayout.posterGridDelegate(
                      context,
                      constraints.crossAxisExtent,
                      compact: AppLayout.isCompact(context),
                      withMeta: false,
                    ) as SliverGridDelegateWithFixedCrossAxisCount;
                    final columns = grid.crossAxisCount;
                    _cellWidth = (constraints.crossAxisExtent -
                            grid.crossAxisSpacing * (columns - 1)) /
                        columns;
                    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
                    // La grille est recréée à chaque nouveau résultat (le
                    // chargement la remplace par LoadingView) : la cascade
                    // rejoue alors, et pas aux pages ajoutées en bas.
                    return StaggeredEntranceScope(
                      playKey: provider.type,
                      child: SliverGrid(
                        gridDelegate: grid,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = provider.items[index];
                            return StaggeredEntrance(
                              index: index,
                              child: RequestMediaCard(item: item),
                            );
                          },
                          childCount: provider.items.length,
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (provider.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
