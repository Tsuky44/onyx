import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../providers/search_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../library/search_results_screen.dart';
import '../search/desktop/recent_searches.dart';

/// La recherche du téléphone (ADR-0142) : le rond de verre de la barre
/// d'onglets s'étire sur toute la largeur et devient le champ, posé juste
/// au-dessus du clavier ; la page des résultats s'ouvre derrière lui et suit
/// la frappe ([SearchResultsScreen.docked]).
///
/// La barre du haut n'a plus de champ : deux champs de recherche à l'écran
/// laissaient le doute sur celui qui commande.
///
/// Un seul état pour la barre, qui dessine, et pour la coquille, qui laisse la
/// place à la bulle sous ses pages : [isOpen], et [isExpanded] tant que les
/// résultats sont au premier plan. Une fiche ouverte depuis les résultats les
/// recouvre ([isCovered]) : la bulle rend la place à la capsule, et revient
/// au retour.
class PhoneSearchSession extends ChangeNotifier {
  PhoneSearchSession({required this.provider, required this.navigatorKey}) {
    controller.addListener(() => provider.setQuery(controller.text));
  }

  /// La recherche que la page des résultats suit.
  final SearchProvider provider;

  /// Le navigateur des pages de la coquille : les résultats s'y ouvrent, sous
  /// la barre, qui reste au-dessus d'eux.
  final GlobalKey<NavigatorState> navigatorKey;

  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'phone-search');

  /// Le temps que la bulle met à prendre toute la largeur. Le clavier monte
  /// ensuite, au rythme du système.
  static const Duration expand = Duration(milliseconds: 320);

  bool _open = false;
  bool _covered = false;

  /// La page des résultats est dans la pile, au premier plan ou non.
  bool get isOpen => _open;

  /// Une fiche ouverte depuis les résultats les recouvre.
  bool get isCovered => _open && _covered;

  /// La bulle est déployée : la recherche est ouverte et ses résultats sont
  /// au premier plan.
  bool get isExpanded => _open && !_covered;

  Route<void>? _route;
  RecentSearches? _recents;
  bool _disposed = false;

  /// Les recherches récentes du profil connecté (`"<serveur>:<profil>"`) :
  /// les mêmes que celles du bureau, rangées par profil.
  RecentSearches recentsFor(String? profileKey) {
    final current = _recents;
    if (current != null && current.profileKey == profileKey) return current;
    current?.dispose();
    return _recents = RecentSearches(profileKey);
  }

  /// Le rond de recherche est touché : la bulle s'étire, la page des
  /// résultats s'ouvre derrière elle. La barre donne le focus au champ quand
  /// la bulle a fini de s'étirer.
  ///
  /// Touché depuis une fiche ouverte des résultats, il y ramène.
  void open({required bool reduced}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    if (_open) {
      final route = _route;
      if (_covered && route != null && route.isActive) {
        route.navigator!.popUntil((r) => r == route);
      }
      return;
    }
    _open = true;
    _covered = false;
    notifyListeners();

    final duration = reduced ? Duration.zero : AppMotion.standard;
    final route = PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (_, __, ___) => _CoverWatch(
        onCovered: _setCovered,
        child: SearchResultsScreen.docked(
          recents: _recents,
          onRecent: useRecent,
        ),
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    _route = route;
    navigator.push(route).whenComplete(() {
      // Retour, ou le geste de retour d'iOS : la page est partie seule.
      if (!identical(_route, route)) return;
      _route = null;
      _reset();
    });
  }

  /// La croix de la bulle : la recherche se referme et rend la page d'avant,
  /// fiches ouvertes depuis les résultats comprises.
  void close() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      final navigator = route.navigator!;
      navigator.popUntil((r) => r == route);
      navigator.pop();
    }
    _reset();
  }

  /// Une fiche s'ouvre par-dessus les résultats, ou s'en va.
  void _setCovered(bool covered) {
    if (_disposed || !_open || covered == _covered) return;
    _covered = covered;
    // Le clavier descend avec la bulle : la fiche n'en a pas l'usage.
    if (covered) focusNode.unfocus();
    notifyListeners();
  }

  /// La touche « Rechercher » : la recherche a servi.
  void submit(String query) => _recents?.remember(query);

  /// Une recherche récente, touchée : elle est retapée.
  void useRecent(String query) {
    controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _reset() {
    if (!_open || _disposed) return;
    _open = false;
    _covered = false;
    focusNode.unfocus();
    controller.clear();
    provider.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    controller.dispose();
    focusNode.dispose();
    _recents?.dispose();
    super.dispose();
  }
}

/// Prévient la recherche quand une fiche recouvre sa page de résultats, et
/// quand elle s'en va.
class _CoverWatch extends StatefulWidget {
  const _CoverWatch({required this.onCovered, required this.child});

  final ValueChanged<bool> onCovered;
  final Widget child;

  @override
  State<_CoverWatch> createState() => _CoverWatchState();
}

class _CoverWatchState extends State<_CoverWatch> {
  bool _covered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // Une page qui se referme n'est pas recouverte : elle s'en va.
    final covered = route != null && route.isActive && !route.isCurrent;
    if (covered == _covered) return;
    _covered = covered;
    // Les dépendances changent pendant la construction : la barre, elle, se
    // redessine après.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCovered(_covered);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Le champ dans la bulle : la loupe, la frappe, la croix qui referme.
class PhoneSearchField extends StatelessWidget {
  const PhoneSearchField({super.key, required this.session});

  final PhoneSearchSession session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 16),
        Icon(
          AppIcons.search,
          size: 20,
          color: AppColors.textPrimary.withValues(alpha: 0.92),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TvDeferredKeyboard(
            fieldFocusNode: session.focusNode,
            builder: (context, focusNode, canRequestFocus) => TextField(
              controller: session.controller,
              focusNode: focusNode,
              canRequestFocus: canRequestFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: session.submit,
              cursorColor: AppColors.accent,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.headline,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: tr('Titre, film, série…'),
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.8),
                  fontSize: AppType.headline,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Semantics(
            button: true,
            label: tr('Fermer la recherche'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: session.close,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                child: const Icon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Réduit la barre d'onglets quand la page défile vers le bas, et la rend en
/// entier dès qu'on remonte ou qu'on revient en haut (ADR-0142) : l'image
/// prend la place, et les onglets reviennent au premier geste vers le haut.
///
/// Ne lit que la liste principale de la page (profondeur 0) : les rangées
/// horizontales défilent sans que la page ait bougé.
class TabBarScrollWatch extends StatelessWidget {
  const TabBarScrollWatch({
    super.key,
    required this.minimized,
    required this.child,
  });

  final ValueNotifier<bool> minimized;
  final Widget child;

  /// Assez loin du haut pour qu'un rebond n'y compte pas.
  static const double threshold = 24;

  /// Un tremblement du doigt n'est pas un sens.
  static const double _jitter = 2;

  bool _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    if (metrics.pixels <= threshold) {
      minimized.value = false;
      return false;
    }
    // Le sens de chaque pas du doigt, pas celui d'un élan qui s'achève : un
    // élan vers le bas qui ralentit ne doit pas rendre la capsule.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > _jitter) {
        minimized.value = true;
      } else if (delta < -_jitter) {
        minimized.value = false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: child,
    );
  }
}
