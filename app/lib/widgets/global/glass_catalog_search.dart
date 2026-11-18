import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/library_provider.dart';
import '../../screens/search/tv_search_screen.dart';
import '../../screens/search/tv_system_search_screen.dart';
import '../../services/tv_system_search.dart';
import '../../theme/app_colors.dart';
import '../../navigation/shell_navigator.dart';
import '../../tv/tv_focus.dart';
import '../../tv/tv_mode.dart';
import 'tv_tab_bar.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

/// La porte de la recherche du catalogue sur téléviseur : l'écran de
/// recherche du système (Apple TV) ou celui de l'app ([TvSearchScreen]).
///
/// Le bureau a la sienne, dans son en-tête (`DesktopHeaderSearch`,
/// ADR-0139) ; le téléphone le rond de sa barre d'onglets, qui s'étire en
/// bulle au-dessus de la page de recherche (`PhoneSearchSession`, ADR-0142
/// et ADR-0145). Hors d'un téléviseur, elle ne dessine rien.
class GlassCatalogSearch extends StatefulWidget {
  /// La largeur du champ d'un téléviseur, hors de la pilule des onglets.
  final double collapsedWidth;

  /// Sur téléviseur, le repos est une loupe ronde plutôt qu'un champ.
  final bool compactTrigger;

  /// Sur téléviseur, la recherche est une entrée de la pilule des onglets
  /// ([TvTabBarItem]), à côté d'eux et dans le même dessin (ADR-0117).
  final bool tabBarTrigger;

  const GlassCatalogSearch({
    super.key,
    this.collapsedWidth = 180,
    this.compactTrigger = false,
    this.tabBarTrigger = false,
  });

  @override
  State<GlassCatalogSearch> createState() => _GlassCatalogSearchState();
}

class _GlassCatalogSearchState extends State<GlassCatalogSearch> {
  final FocusNode _tvSearchNode =
      FocusNode(debugLabel: 'tv-search-header-button');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().ensureCatalogLoaded();
    });
  }

  @override
  void dispose() {
    _tvSearchNode.dispose();
    super.dispose();
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

    return const SizedBox.shrink();
  }
}
