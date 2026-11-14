import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../navigation/shell_navigator.dart';
import '../../providers/library_provider.dart';
import '../../providers/search_provider.dart';
import '../../screens/library/search_results_screen.dart';
import '../../screens/search/tv_search_screen.dart';
import '../../screens/search/tv_system_search_screen.dart';
import '../../services/tv_system_search.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../tv/tv_focus.dart';
import '../../tv/tv_mode.dart';
import 'glass_chrome.dart';
import 'tv_tab_bar.dart';
import 'search_results_route.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

/// La recherche du catalogue dans la barre de navigation.
///
/// Dès le premier caractère tapé, la page de résultats s'ouvre
/// ([SearchResultsScreen]) : une grille d'affiches en pleine page, mise à jour
/// à chaque frappe. La liste déroulante sous le champ a disparu — elle montrait
/// huit titres dans une fenêtre étroite, et il fallait un clic de plus pour
/// voir le reste.
class GlassCatalogSearch extends StatefulWidget {
  final bool expandInline;
  final double collapsedWidth;
  final double expandedWidth;

  /// When true, the idle state is a circular search icon instead of a field.
  final bool compactTrigger;

  /// Sur téléviseur, la recherche est une entrée de la pilule des onglets
  /// ([TvTabBarItem]), à côté d'eux et dans le même dessin (ADR-0117).
  final bool tabBarTrigger;

  /// Vrai quand ce champ reste à l'écran au-dessus des pages que la coquille
  /// ouvre — la barre de verre du grand écran. Il reste alors le seul champ :
  /// on continue d'y taper, et la page de résultats le suit.
  ///
  /// Faux pour la barre du téléphone, que la coquille retire dès qu'une page
  /// s'ouvre : la frappe passe au champ de la page de résultats.
  final bool staysAbovePages;

  const GlassCatalogSearch({
    super.key,
    this.expandInline = true,
    this.collapsedWidth = 180,
    this.expandedWidth = 300,
    this.compactTrigger = false,
    this.tabBarTrigger = false,
    this.staysAbovePages = false,
  });

  @override
  State<GlassCatalogSearch> createState() => _GlassCatalogSearchState();
}

class _GlassCatalogSearchState extends State<GlassCatalogSearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final FocusNode _tvSearchNode =
      FocusNode(debugLabel: 'tv-search-header-button');

  /// La page de résultats ouverte par la frappe, tant qu'elle est dans la pile.
  Route<void>? _resultsRoute;

  /// La page sur laquelle on était quand la frappe a ouvert les résultats :
  /// celle où l'on revient quand la recherche s'efface.
  Route<dynamic>? _routeBeforeResults;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().ensureCatalogLoaded();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _tvSearchNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    context.read<SearchProvider>().setExpanded(_focusNode.hasFocus);
  }

  void _onQueryChanged(String value) {
    if (widget.staysAbovePages) {
      context.read<SearchProvider>().setQuery(value);
    }
    if (value.trim().isNotEmpty) {
      _openResults(value);
    } else if (widget.staysAbovePages) {
      // Le champ vidé à la main rend la page d'avant. Le focus reste dans le
      // champ : on efface souvent pour retaper autre chose. La page rendue le
      // réclame en revenant au premier plan ; le redemander dans la même
      // frame l'emporte, sans que le champ se replie puis se rouvre.
      _closeResults();
      _focusNode.requestFocus();
    }
  }

  /// Ouvre la page de résultats, ou y ramène si elle est déjà dans la pile.
  void _openResults(String typed) {
    final navigator = shellNavigatorOf(context);
    final open = _resultsRoute;
    if (open != null && open.isActive) {
      // Une fiche ouverte depuis les résultats les recouvre : reprendre la
      // frappe y ramène, au lieu de filtrer une grille qu'on ne voit pas.
      if (!open.isCurrent) navigator.popUntil((route) => route == open);
      return;
    }

    final followsHeader = widget.staysAbovePages;
    if (!followsHeader) {
      // La frappe passe au champ de la page. Celui-ci se vide avant : un
      // caractère arrivé avant que la page ne prenne le focus y resterait, et
      // on le retrouverait au retour. Le clavier, lui, reste ouvert — le
      // refermer ici le ferait clignoter sous le doigt.
      _controller.clear();
      context.read<SearchProvider>().clear();
    }

    // Un prédicat vrai d'emblée ne retire rien : il donne la page du dessus.
    navigator.popUntil((route) {
      _routeBeforeResults = route;
      return true;
    });

    final route = SearchResultsRoute<void>(
      // Sous la barre de verre, la page ne prend pas le focus en s'ouvrant :
      // il reste dans ce champ, où l'on est en train de taper.
      requestFocus: followsHeader ? false : null,
      builder: (_) => followsHeader
          ? const SearchResultsScreen.followingHeader()
          : SearchResultsScreen(
              query: typed,
              autofocusField: true,
              closesWhenEmptied: true,
            ),
    );
    _resultsRoute = route;
    navigator.push(route).whenComplete(() {
      if (!identical(_resultsRoute, route)) return;
      _resultsRoute = null;
      _routeBeforeResults = null;
      // La page s'est refermée sans que le champ se vide (Retour, un onglet
      // de la barre) : la recherche se referme avec elle.
      if (followsHeader && mounted) _resetField();
    });
  }

  /// Referme les résultats et rend la page sur laquelle on était avant de
  /// chercher, fiches ouvertes depuis les résultats comprises.
  void _closeResults() {
    final route = _resultsRoute;
    final before = _routeBeforeResults;
    _resultsRoute = null;
    _routeBeforeResults = null;
    if (route == null || !route.isActive) return;
    final navigator = route.navigator!;
    if (route.isCurrent) {
      navigator.pop();
      return;
    }
    // Une fiche recouvre les résultats. Ils partent d'abord de dessous, sans
    // se voir ; puis la fiche se referme par son propre geste, sur la page
    // d'avant — au lieu de deux pages qui s'effacent l'une sur l'autre.
    navigator.removeRoute(route);
    navigator.popUntil(
      (r) => (before != null && before.isActive) ? r == before : r.isFirst,
    );
  }

  void _resetField() {
    _controller.clear();
    context.read<SearchProvider>().clear();
    _focusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// La croix du champ : referme la recherche et rend la page d'avant.
  void _clear() {
    _closeResults();
    _resetField();
  }

  Future<void> _openTvSearch(BuildContext context) async {
    // Sur l'Apple TV, l'écran de recherche du système, son clavier en ligne
    // au-dessus des résultats (ADR-0129). Ailleurs, la page de recherche d'un
    // téléviseur, dont le champ ouvre le clavier du système (ADR-0126).
    await shellNavigatorOf(context).push(
      MaterialPageRoute(
        builder: (_) => TvSystemSearch.isSupported
            ? const TvSystemSearchScreen()
            : const TvSearchScreen(),
      ),
    );
    if (mounted) {
      _tvSearchNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context) || TvMode.isTv;
    if (isTv) {
      if (widget.tabBarTrigger) {
        return TvTabBarItem(
          label: tr('Rechercher'),
          icon: AppIcons.search,
          selected: false,
          selectOnFocus: false,
          focusNode: _tvSearchNode,
          onTap: () => _openTvSearch(context),
        );
      }
      if (widget.compactTrigger) {
        return TvFocusable(
          focusNode: _tvSearchNode,
          onSelect: () => _openTvSearch(context),
          borderRadius: BorderRadius.circular(20),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _openTvSearch(context),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                AppIcons.search,
                size: 20,
                color: AppColors.textPrimary.withValues(alpha: 0.92),
              ),
            ),
          ),
        );
      }

      return TvFocusable(
        focusNode: _tvSearchNode,
        onSelect: () => _openTvSearch(context),
        borderRadius: BorderRadius.circular(17),
        focusScale: 1.0,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _openTvSearch(context),
          child: Container(
            height: 34,
            width: widget.collapsedWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.search,
                  size: 17,
                  color: AppColors.textSecondary.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Rechercher'),
                    style: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.7),
                      fontSize: AppType.subhead,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final search = context.watch<SearchProvider>();
    final expanded =
        widget.expandInline && (search.isExpanded || search.isActive);
    final showField = !widget.compactTrigger || expanded;
    final width = showField
        ? (expanded ? widget.expandedWidth : widget.collapsedWidth)
        : 40.0;

    if (widget.compactTrigger && !showField) {
      return GlassIconButton(
        size: 40,
        onTap: () {
          context.read<SearchProvider>().setExpanded(true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _focusNode.requestFocus();
              SystemChannels.textInput.invokeMethod('TextInput.show');
            }
          });
        },
        child: Icon(
          AppIcons.search,
          size: 20,
          color: AppColors.textPrimary.withValues(alpha: 0.92),
        ),
      );
    }

    return TvDeferredKeyboard(
      fieldFocusNode: _focusNode,
      borderRadius: BorderRadius.circular(17),
      builder: (context, focusNode, canRequestFocus) => AnimatedContainer(
        duration: AppMotion.move(context),
        curve: AppMotion.curve,
        width: width,
        child: GlassSearchInput(
          controller: _controller,
          focusNode: _focusNode,
          canRequestFocus: canRequestFocus,
          onChanged: _onQueryChanged,
          // Entrée ramène aux résultats quand une fiche les recouvre.
          onSubmitted: _onQueryChanged,
          onClear: _clear,
          hint: expanded ? tr('Titre, film, série…') : tr('Rechercher'),
          focused: _focusNode.hasFocus,
          hasText: _controller.text.isNotEmpty,
        ),
      ),
    );
  }
}
