import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../navigation/detail_flight.dart';
import '../../../navigation/shell_navigator.dart';
import '../../../providers/library_provider.dart';
import '../../../services/api_client.dart';
import '../../../services/unavailable_titles_search.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_deferred_keyboard.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/empty_state.dart';
import '../../../widgets/global/glass_chrome.dart';
import '../../../widgets/global/search_results_route.dart';
import '../../requests/request_availability.dart';
import '../../requests/request_detail_launch.dart';
import '../recent_searches.dart';
import '../search_chips.dart';
import '../search_layout.dart';
import '../search_shelves.dart';
import 'phone_search_row.dart';

/// Ouvre la recherche du téléphone par-dessus la page affichée.
///
/// La seule porte d'entrée : la loupe de la barre du haut aujourd'hui, la
/// pastille du bas de l'écran demain. Rien ne s'ouvre deux fois.
Future<void> openPhoneSearch(BuildContext context) async {
  final navigator = shellNavigatorOf(context);
  var alreadyOpen = false;
  // Un prédicat vrai d'emblée ne retire rien : il donne la page du dessus.
  navigator.popUntil((route) {
    alreadyOpen = route.settings.name == PhoneSearchScreen.routeName;
    return true;
  });
  if (alreadyOpen) return;
  await navigator.push(SearchResultsRoute<void>(
    settings: const RouteSettings(name: PhoneSearchScreen.routeName),
    builder: (_) => const PhoneSearchScreen(),
  ));
}

/// La recherche du catalogue sur téléphone (ADR-0145).
///
/// Une page à elle, ouverte d'un toucher, le clavier levé : son champ est le
/// seul. L'ancienne recherche commençait dans un champ étroit de la barre du
/// haut et passait la frappe, au premier caractère, au champ d'une autre
/// page ; vider ce champ pour corriger une faute refermait tout.
///
/// - Rien de tapé : les recherches récentes, puis les derniers ajouts.
/// - Sinon, les pastilles Tout, Films, Séries, Pas sur le serveur, et les
///   titres en lignes ([PhoneSearchRow]) : ceux de la bibliothèque, puis
///   ceux que le serveur n'a pas (ADR-0129).
/// - Faire défiler baisse le clavier ; vider le champ ne referme rien,
///   « Annuler » ou le geste retour referment.
///
/// Le bureau a sa feuille sous l'en-tête (ADR-0139), le téléviseur son écran
/// (ADR-0126) ; tous rangent les titres par `SearchShelves`.
class PhoneSearchScreen extends StatefulWidget {
  const PhoneSearchScreen({super.key});

  /// Le nom de la route, qui empêche [openPhoneSearch] de l'empiler deux
  /// fois.
  static const String routeName = 'phone-search';

  /// Les derniers ajouts proposés quand rien n'est tapé.
  static const int recentCount = 12;

  @override
  State<PhoneSearchScreen> createState() => _PhoneSearchScreenState();
}

class _PhoneSearchScreenState extends State<PhoneSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldNode = FocusNode(debugLabel: 'phone-search-field');

  /// Ce que le catalogue de demandes connaît pour la recherche affichée.
  late final UnavailableTitlesSearch _catalog =
      UnavailableTitlesSearch(context.read<ApiClient>());

  RecentSearches? _recents;

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
    _controller.dispose();
    _fieldNode.dispose();
    _recents?.dispose();
    super.dispose();
  }

  /// Les recherches récentes du profil ouvert, rechargées quand il change.
  RecentSearches _recentsFor(String? profileKey) {
    final current = _recents;
    if (current != null && current.profileKey == profileKey) return current;
    current?.dispose();
    return _recents = RecentSearches(profileKey);
  }

  void _onTyped() {
    setState(() {
      // Une nouvelle recherche repart de « Tout » : une pastille gardée d'une
      // frappe à l'autre cachait des résultats qu'on n'avait pas choisi de
      // cacher.
      if (_controller.text.trim() != _lastQuery) _filter = SearchFilter.all;
    });
  }

  void _onCatalogAnswered() => setState(() {});

  /// La recherche tapée, figée dès que la page se referme : sans cela les
  /// derniers ajouts reprenaient la place des résultats pendant le fondu de
  /// sortie.
  String _shownQuery() {
    final typed = _controller.text.trim();
    if (ModalRoute.of(context)?.isActive ?? true) _lastQuery = typed;
    return _lastQuery;
  }

  void _hideKeyboard() {
    _fieldNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _pickRecent(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    // On a choisi une recherche connue : ce sont ses résultats qu'on veut
    // voir, pas le clavier.
    _hideKeyboard();
  }

  /// La fiche du titre touché, par l'envol de sa vignette.
  void _open(BuildContext thumbContext, SearchHit hit) {
    _recents?.remember(_lastQuery);
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
    final recents = _recentsFor(RecentSearches.watchProfileKey(context));
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(padding),
            if (layout != null && layout.total > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SearchFilterChips(
                  layout: layout,
                  selected: _filter,
                  onSelected: (filter) => setState(() => _filter = filter),
                  showUnavailable: canRequest,
                  scrolls: true,
                  padding: EdgeInsets.symmetric(horizontal: padding),
                ),
              ),
            Expanded(
              child: layout == null
                  ? _idle(lp, recents, padding)
                  : layout.total == 0
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

  /// Le champ, et « Annuler » qui referme la page.
  Widget _header(double padding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 8, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: TvDeferredKeyboard(
              fieldFocusNode: _fieldNode,
              autofocus: true,
              borderRadius: BorderRadius.circular(
                  GlassSearchInput.heightFor(large: false) / 2),
              builder: (context, focusNode, canRequestFocus) =>
                  GlassSearchInput(
                controller: _controller,
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
                // Vider le champ garde la page : on corrige sa recherche, on
                // ne la quitte pas.
                onClear: _controller.clear,
                onSubmitted: (_) => _hideKeyboard(),
                hint: tr('Rechercher un film ou une série…'),
                focused: focusNode.hasFocus,
                hasText: _controller.text.isNotEmpty,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: Size(0, AppLayout.minTouchTarget(context)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(tr('Annuler')),
          ),
        ],
      ),
    );
  }

  /// Rien de tapé : les recherches récentes, puis les derniers ajouts.
  Widget _idle(LibraryProvider lp, RecentSearches recents, double padding) {
    final recent =
        SearchShelves.recentlyAdded(lp, PhoneSearchScreen.recentCount);
    return ListenableBuilder(
      listenable: recents,
      builder: (context, _) {
        final items = recents.items;
        if (items.isEmpty && recent.isEmpty) {
          return EmptyStateView(
            icon: AppIcons.search,
            title: tr('Rechercher'),
            message: tr('Recherchez et demandez de nouveaux films et séries'),
          );
        }
        return CustomScrollView(
          scrollCacheExtent: AppLayout.imageCacheExtent(context),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (items.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionTitle(
                  title: tr('Recherches récentes'),
                  padding: padding,
                  action: TextButton(
                    onPressed: recents.clear,
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
            _bottomGap(context),
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
        _bottomGap(context),
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

  /// La dernière ligne passe au-dessus de la barre du système.
  Widget _bottomGap(BuildContext context) => SliverToBoxAdapter(
        child: SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).bottom),
      );
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
