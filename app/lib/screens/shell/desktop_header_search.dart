import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../navigation/shell_navigator.dart';
import '../../providers/library_provider.dart';
import '../../providers/search_provider.dart';
import '../../theme/app_motion.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../utils/app_platform.dart';
import '../search/desktop/desktop_search_controller.dart';
import '../search/desktop/desktop_search_hotkey.dart';
import '../search/desktop/desktop_search_route.dart';
import '../search/desktop/desktop_search_sheet.dart';
import '../search/recent_searches.dart';

/// Le champ de recherche de l'en-tête du bureau (ADR-0139).
///
/// Le focus, un clic, Ctrl K ou « / » ouvrent la recherche : le voile de
/// [DesktopSearchRoute] descend sur la page, et [ShellDesktopHeader] fait
/// glisser ce champ au centre à la place des onglets. Le champ garde le focus
/// tout du long : la frappe filtre, Bas fait entrer les flèches dans la
/// grille, Entrée ouvre la fiche du titre sélectionné, Ctrl + Entrée lance le
/// film, Échap referme et rend la page d'avant.
///
/// [SearchProvider.isExpanded] dit à l'en-tête que la recherche est ouverte ;
/// [SearchProvider.query] porte la frappe jusqu'à la feuille.
///
/// Le téléphone et le téléviseur gardent leur recherche (`GlassCatalogSearch`).
class DesktopHeaderSearch extends StatefulWidget {
  const DesktopHeaderSearch({super.key, required this.width});

  /// La largeur du champ, que l'en-tête anime entre repos et ouverture.
  final double width;

  @override
  State<DesktopHeaderSearch> createState() => _DesktopHeaderSearchState();
}

class _DesktopHeaderSearchState extends State<DesktopHeaderSearch>
    implements DesktopSearchSummoner {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'desktop-header-search');
  final DesktopSearchController _selection = DesktopSearchController();

  RecentSearches? _recents;

  /// La feuille de résultats, tant qu'elle est dans la pile.
  DesktopSearchRoute<void>? _route;

  /// La page sur laquelle on était en ouvrant la recherche : celle où l'on
  /// revient en la refermant, fiches ouvertes depuis les résultats comprises.
  Route<dynamic>? _routeBefore;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    DesktopSearchHotkey.register(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().ensureCatalogLoaded();
    });
  }

  @override
  void dispose() {
    DesktopSearchHotkey.unregister(this);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    _selection.dispose();
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

  bool get _isOpen => _route?.isActive ?? false;

  /// Le raccourci, tel que l'infobulle du champ le nomme.
  static String get _shortcutLabel => AppPlatform.isMacOS ? '⌘ K' : 'Ctrl K';

  /// L'infobulle attend qu'on s'arrête sur le champ : elle n'apparaît pas
  /// sous un pointeur qui le traverse pour cliquer.
  static const Duration _tooltipDelay = Duration(milliseconds: 700);

  // ---------------------------------------------------------------------
  // Raccourci (Ctrl K, « / »)

  @override
  bool get canSummon {
    if (!mounted) return false;
    // Le lecteur plein écran, un dialogue ou un menu recouvrent la coquille :
    // la touche ne doit pas ouvrir une recherche qu'on ne verrait pas.
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  @override
  void summon() {
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    if (_focusNode.hasFocus) {
      _open();
    } else {
      _focusNode.requestFocus();
    }
  }

  // ---------------------------------------------------------------------
  // Ouvrir, refermer

  void _onFocusChanged() {
    if (_focusNode.hasFocus) _open();
    setState(() {});
  }

  /// Ouvre la feuille, ou y ramène quand une fiche ouverte depuis les
  /// résultats la recouvre.
  void _open() {
    final navigator = shellNavigatorOf(context);
    final open = _route;
    if (open != null && open.isActive) {
      if (!open.isCurrent) navigator.popUntil((route) => route == open);
      return;
    }

    // Un prédicat vrai d'emblée ne retire rien : il donne la page du dessus.
    navigator.popUntil((route) {
      _routeBefore = route;
      return true;
    });
    final recents = _recents!;
    final route = DesktopSearchRoute<void>(
      builder: (_) => DesktopSearchSheet(
        controller: _selection,
        recents: recents,
        onPickRecent: _pickRecent,
        onReturn: _refocus,
      ),
    );
    _route = route;
    _selection.restart();
    context.read<SearchProvider>().setExpanded(true);
    navigator.push(route).whenComplete(() {
      if (!identical(_route, route)) return;
      // Refermée sans Échap : Retour de la souris, un onglet choisi, le
      // rappel de la page à gauche de l'en-tête.
      _route = null;
      _routeBefore = null;
      if (mounted) _reset();
    });
  }

  /// Referme la feuille et rend la page d'avant.
  void _close() {
    final route = _route;
    final before = _routeBefore;
    _route = null;
    _routeBefore = null;
    _reset();
    if (route == null || !route.isActive) return;
    final navigator = route.navigator!;
    if (route.isCurrent) {
      navigator.pop();
      return;
    }
    // Une fiche recouvre les résultats. Ils partent d'abord de dessous, sans
    // se voir ; puis la fiche se referme par son propre geste.
    navigator.removeRoute(route);
    navigator.popUntil(
      (r) => (before != null && before.isActive) ? r == before : r.isFirst,
    );
  }

  void _reset() {
    _controller.clear();
    context.read<SearchProvider>().clear();
    _selection.restart();
    _focusNode.unfocus();
  }

  void _refocus() {
    if (mounted && _isOpen) _focusNode.requestFocus();
  }

  // ---------------------------------------------------------------------
  // Frappe et touches

  void _onChanged(String value) {
    context.read<SearchProvider>().setQuery(value);
    _selection.restart();
    // Reprendre la frappe sur une fiche ouverte depuis les résultats ramène
    // aux résultats, au lieu de filtrer une grille qu'on ne voit pas.
    _open();
  }

  void _pickRecent(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _onChanged(query);
    _focusNode.requestFocus();
  }

  void _clearText() {
    _controller.clear();
    _onChanged('');
    _focusNode.requestFocus();
  }

  void _onSubmitted(String _) {
    if (!_isOpen) return;
    final keyboard = HardwareKeyboard.instance;
    _selection.activate(
      play: keyboard.isControlPressed || keyboard.isMetaPressed,
    );
  }

  /// Une flèche que la grille prend, ou null pour la laisser au champ.
  bool _arrow(TraversalDirection direction) =>
      _isOpen && _selection.arrow(direction);

  @override
  Widget build(BuildContext context) {
    _recentsFor(RecentSearches.watchProfileKey(context));
    final open = context.select<SearchProvider, bool>((s) => s.isExpanded);
    final focused = _focusNode.hasFocus;
    final hasText = _controller.text.isNotEmpty;

    return Actions(
      actions: <Type, Action<Intent>>{
        ExtendSelectionVerticallyToAdjacentLineIntent: _VerticalArrowAction(
          (forward) => _arrow(
            forward ? TraversalDirection.down : TraversalDirection.up,
          ),
        ),
        ExtendSelectionByCharacterIntent: _HorizontalArrowAction(
          browsing: () => _isOpen && _selection.browsing,
          step: (forward) => _arrow(
            forward ? TraversalDirection.right : TraversalDirection.left,
          ),
        ),
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            if (_isOpen) {
              _close();
            } else {
              _focusNode.unfocus();
            }
            return null;
          },
        ),
      },
      child: TvDeferredKeyboard(
        fieldFocusNode: _focusNode,
        borderRadius: BorderRadius.circular(17),
        builder: (context, focusNode, canRequestFocus) => Tooltip(
          // Le raccourci se dit au survol, pas dessiné dans le champ : des
          // touches peintes dans l'en-tête l'alourdissaient.
          message: open ? '' : tr('Rechercher ({0})', [_shortcutLabel]),
          waitDuration: _tooltipDelay,
          child: AnimatedContainer(
            duration: AppMotion.move(context),
            curve: AppMotion.curve,
            width: widget.width,
            child: GlassSearchInput(
              controller: _controller,
              focusNode: _focusNode,
              canRequestFocus: canRequestFocus,
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
              onClear: _clearText,
              hint: open ? tr('Titre, film, série…') : tr('Rechercher'),
              focused: focused,
              hasText: hasText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Haut et Bas dans le champ : la grille les prend quand elle peut, sinon
/// ils gardent leur sens de champ (curseur au début, à la fin).
///
/// Les actions du champ de Flutter se laissent remplacer par un ancêtre
/// (`Action.overridable`) : c'est par là que passent les flèches, sans
/// second gestionnaire de touches (ADR-0110).
///
/// Le champ range Haut, Bas, Page précédente et Page suivante sous une seule
/// action, typée [DirectionalCaretMovementIntent]. Depuis Flutter 3.47, le
/// remplaçant se cherche sous le type exact de l'intention
/// ([ExtendSelectionVerticallyToAdjacentLineIntent]) et non plus sous ce
/// type commun : déclarée pour celui-ci, l'action n'était plus jamais
/// trouvée et Bas restait au curseur (ADR-0167). Page précédente et Page
/// suivante gardent l'action du champ.
class _VerticalArrowAction extends Action<DirectionalCaretMovementIntent> {
  _VerticalArrowAction(this.take);

  final bool Function(bool forward) take;

  @override
  Object? invoke(DirectionalCaretMovementIntent intent) {
    if (intent is ExtendSelectionVerticallyToAdjacentLineIntent &&
        intent.collapseSelection &&
        take(intent.forward)) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}

/// Gauche et Droite : le curseur du champ, sauf quand Bas a fait entrer les
/// flèches dans la grille.
class _HorizontalArrowAction extends Action<ExtendSelectionByCharacterIntent> {
  _HorizontalArrowAction({required this.browsing, required this.step});

  final bool Function() browsing;
  final bool Function(bool forward) step;

  @override
  Object? invoke(ExtendSelectionByCharacterIntent intent) {
    if (intent.collapseSelection && browsing() && step(intent.forward)) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}
