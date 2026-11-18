import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../navigation/detail_flight.dart';
import '../../../providers/library_provider.dart';
import '../../../services/api_client.dart';
import '../../../services/unavailable_titles_search.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/empty_state.dart';
import '../../../widgets/global/sliver_scroll_end.dart';
import '../../requests/request_availability.dart';
import '../../requests/request_detail_launch.dart';
import '../../shell/phone_search.dart';
import '../search_chips.dart';
import '../search_layout.dart';
import '../search_shelves.dart';
import 'phone_search_row.dart';

/// La page de recherche du téléphone (ADR-0145), ouverte sous la bulle de la
/// barre d'onglets (ADR-0142).
///
/// Le champ n'est pas ici : c'est la bulle, posée au-dessus du clavier, qui le
/// porte ([PhoneSearchSession.controller]), avec la croix qui referme tout.
/// La page lit sa frappe.
///
/// - Rien de tapé : les recherches récentes, puis les derniers ajouts.
/// - Sinon, les pastilles Tout, Films, Séries, Pas sur le serveur, et les
///   titres en lignes ([PhoneSearchRow]) : ceux de la bibliothèque, puis
///   ceux que le serveur n'a pas (ADR-0129).
/// - Faire défiler baisse le clavier ; vider le champ ne referme rien.
///
/// Le bureau a sa feuille sous l'en-tête (ADR-0139), le téléviseur son écran
/// (ADR-0126) ; tous rangent les titres par `SearchShelves`.
class PhoneSearchScreen extends StatefulWidget {
  const PhoneSearchScreen({super.key, required this.session});

  /// La bulle qui porte le champ, et les recherches récentes du profil.
  final PhoneSearchSession session;

  /// Les derniers ajouts proposés quand rien n'est tapé.
  static const int recentCount = 12;

  @override
  State<PhoneSearchScreen> createState() => _PhoneSearchScreenState();
}

class _PhoneSearchScreenState extends State<PhoneSearchScreen> {
  /// Ce que le catalogue de demandes connaît pour la recherche affichée.
  late final UnavailableTitlesSearch _catalog =
      UnavailableTitlesSearch(context.read<ApiClient>());

  TextEditingController get _controller => widget.session.controller;

  SearchFilter _filter = SearchFilter.all;

  /// La dernière recherche affichée, voir [_shownQuery].
  String _lastQuery = '';

  /// Vrai tant que la page est au premier plan.
  bool _current = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTyped);
    _catalog.addListener(_onCatalogAnswered);
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
    // Au retour d'une fiche de demande, le statut d'un titre a pu changer :
    // « Indispo » devient « Demandé ».
    if (current) _catalog.refresh();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTyped);
    _catalog.removeListener(_onCatalogAnswered);
    _catalog.dispose();
    super.dispose();
  }

  void _onTyped() {
    // La croix de la bulle vide le champ pendant que la page s'en va.
    if (!mounted) return;
    setState(() {
      // Une nouvelle recherche repart de « Tout » : une pastille gardée d'une
      // frappe à l'autre cachait des résultats qu'on n'avait pas choisi de
      // cacher.
      if (_controller.text.trim() != _lastQuery) _filter = SearchFilter.all;
    });
  }

  void _onCatalogAnswered() => setState(() {});

  /// La recherche tapée, figée dès que la page se referme : la croix de la
  /// bulle vide le champ, et sans cela les derniers ajouts reprenaient la
  /// place des résultats pendant le fondu de sortie.
  String _shownQuery() {
    final typed = _controller.text.trim();
    if (ModalRoute.of(context)?.isActive ?? true) _lastQuery = typed;
    return _lastQuery;
  }

  void _hideKeyboard() {
    widget.session.focusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _pickRecent(String query) {
    widget.session.useRecent(query);
    // On a choisi une recherche connue : ce sont ses résultats qu'on veut
    // voir, pas le clavier.
    _hideKeyboard();
  }

  /// La fiche du titre touché, par l'envol de sa vignette.
  void _open(BuildContext thumbContext, SearchHit hit) {
    widget.session.recents?.remember(_lastQuery);
    _hideKeyboard();
    switch (hit) {
      case LibraryHit(:final media):
        openMediaDetail(
          thumbContext,
          media,
          item: media.type == MediaType.movie
              ? context.read<LibraryProvider>().movieItemFor(media.id)
              : null,
        );
      case UnavailableHit(:final item):
        openRequestDetail(thumbContext, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LibraryProvider>();
    final query = _shownQuery();
    final canRequest = canRequestMedia(context, listen: true);
    // C'est ici que le catalogue de demandes apprend la recherche. L'appel ne
    // prévient personne sur le coup, la construction peut le faire.
    _catalog.search(query, enabled: canRequest);
    final padding = AppLayout.pagePadding(context);
    final layout = query.isEmpty
        ? null
        : SearchLayout.of(
            SearchShelves.of(lp, query, catalog: _catalog.resultsFor(query)),
            _filter,
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: layout == null
            ? _idle(lp, padding)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  if (layout.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SearchFilterChips(
                        layout: layout,
                        selected: _filter,
                        onSelected: (filter) =>
                            setState(() => _filter = filter),
                        showUnavailable: canRequest,
                        scrolls: true,
                        padding: EdgeInsets.symmetric(horizontal: padding),
                      ),
                    ),
                  Expanded(
                    child: layout.total == 0
                        ? EmptyStateView(
                            icon: AppIcons.search,
                            title: tr('Aucun résultat'),
                            message: tr(
                                'Aucun film ou série ne correspond à « {0} ».',
                                [query]),
                          )
                        : _results(layout, padding),
                  ),
                ],
              ),
      ),
    );
  }

  /// Rien de tapé : le titre de la page, les recherches récentes, puis les
  /// derniers ajouts.
  Widget _idle(LibraryProvider lp, double padding) {
    final recents = widget.session.recents;
    final recent =
        SearchShelves.recentlyAdded(lp, PhoneSearchScreen.recentCount);
    return ListenableBuilder(
      listenable: recents ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        final items = recents?.items ?? const <String>[];
        return CustomScrollView(
          scrollCacheExtent: AppLayout.imageCacheExtent(context),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
                child: Text(
                  tr('Rechercher'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppType.display,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (items.isEmpty && recent.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: Text(
                    tr('Recherchez et demandez de nouveaux films et séries'),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: AppType.subhead,
                    ),
                  ),
                ),
              ),
            if (items.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionTitle(
                  title: tr('Recherches récentes'),
                  padding: padding,
                  action: TextButton(
                    onPressed: recents!.clear,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: Text(tr('Effacer')),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 4, padding, 24),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final query in items)
                        RecentSearchChip(
                          query: query,
                          onTap: () => _pickRecent(query),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (recent.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionTitle(
                  title: tr('Ajoutés récemment'),
                  padding: padding,
                ),
              ),
              _rows([for (final media in recent) LibraryHit(media)], padding),
            ],
            const SliverScrollEnd(base: 24),
          ],
        );
      },
    );
  }

  Widget _results(SearchLayout layout, double padding) {
    final library = [for (final media in layout.library) LibraryHit(media)];
    final unavailable = [
      for (final item in layout.unavailable) UnavailableHit(item),
    ];
    return CustomScrollView(
      scrollCacheExtent: AppLayout.imageCacheExtent(context),
      // Faire défiler, c'est vouloir lire les résultats : le clavier en
      // cachait la moitié.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (library.isNotEmpty) _rows(library, padding),
        if (unavailable.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: library.isEmpty ? 0 : 16),
              child: _SectionTitle(
                title: tr('Pas sur le serveur'),
                subtitle: tr('Ouvrez un titre pour le demander'),
                padding: padding,
              ),
            ),
          ),
          _rows(unavailable, padding),
        ],
        // La dernière ligne passe au-dessus de la bulle et du clavier.
        const SliverScrollEnd(base: 24),
      ],
    );
  }

  Widget _rows(List<SearchHit> hits, double padding) {
    return SliverList.builder(
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return PhoneSearchRow(
          key: ValueKey(hit.identity),
          hit: hit,
          horizontalPadding: padding,
          onOpen: (thumbContext) => _open(thumbContext, hit),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.padding,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final double padding;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 4, action == null ? padding : 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: AppType.subhead,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
