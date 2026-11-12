import 'package:flutter/material.dart';

import '../../desktop_window.dart';
import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/account_menu.dart';
import '../../widgets/global/app_download_button.dart';
import '../../widgets/global/glass_catalog_search.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/interface_tour/tour_anchor.dart';
import '../../widgets/global/tv_tab_bar.dart';
import 'shell_indexer_status.dart';
import 'shell_tabs.dart';

/// L'en-tête d'un téléviseur : la marque à gauche, la pilule des onglets au
/// centre (la recherche y suit Accueil), le compte à droite (ADR-0117).
///
/// Les mêmes entrées que [ShellDesktopHeader], dans la disposition des apps de
/// salon. La bande de verre pleine largeur a disparu : seule la pilule porte
/// du verre, et un voile sombre qui se dissout vers le bas garde la marque et
/// le compte lisibles quand une page défile dessous.
///
/// Les marges sont celles d'un téléviseur ([tvShellHeaderTopGap],
/// [AppLayout.pagePadding]) : la barre du grand écran était à 6 px du bord
/// haut, dans la zone qu'un téléviseur peut rogner.
class ShellTvHeader extends StatelessWidget {
  const ShellTvHeader({
    super.key,
    required this.selected,
    required this.onTabSelected,
    required this.libraries,
    required this.homeProvider,
    required this.authProvider,
    required this.canDownload,
    required this.nodeFor,
    this.canUseLists = false,
    this.canRequestMedia = false,
  });

  /// L'identifiant de l'onglet affiché (voir [ShellTabs]).
  final String selected;
  final ValueChanged<String> onTabSelected;

  /// Les bibliothèques du serveur : un onglet chacune, sous son nom.
  final List<MediaLibrary> libraries;
  final HomeProvider homeProvider;
  final AuthProvider authProvider;
  final bool canDownload;
  final bool canUseLists;
  final bool canRequestMedia;

  /// Le nœud de focus d'un onglet, possédé par la coquille.
  final FocusNode Function(String tab) nodeFor;

  /// La place gardée de chaque côté de la pilule, pour qu'elle reste au
  /// centre quelle que soit la largeur de ce qui l'entoure.
  static const double _sideWidth = 230;

  Widget _tab(String tab, String label) => TvTabBarItem(
        label: label,
        selected: selected == tab,
        focusNode: nodeFor(tab),
        onTap: () => onTabSelected(tab),
      );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0.74),
            AppColors.background.withValues(alpha: 0.42),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0, 0.6, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppLayout.pagePadding(context),
            tvShellHeaderTopGap,
            AppLayout.pagePadding(context),
            tvShellHeaderBottomGap,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _sideWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: GlassBrand(
                    onTap: () => onTabSelected(ShellTabs.home),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  heightFactor: 1,
                  child: TvTabBar(
                    children: [
                      TourTarget(
                        anchor: TourAnchor.library,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _tab(ShellTabs.home, tr('Accueil')),
                            // La recherche est une entrée de la barre, comme
                            // dans les apps de salon : OK l'ouvre, le focus
                            // seul non. Juste à droite d'Accueil (demande du
                            // 2026-11-12) : au bout de la pilule, il fallait
                            // traverser toutes les bibliothèques pour
                            // l'atteindre, et elle sortait de vue dès qu'un
                            // serveur en compte trop.
                            const TourTarget(
                              anchor: TourAnchor.search,
                              child: GlassCatalogSearch(
                                tabBarTrigger: true,
                                staysAbovePages: true,
                              ),
                            ),
                            for (final library in libraries)
                              _tab(ShellTabs.library(library),
                                  ShellTabs.label(library)),
                          ],
                        ),
                      ),
                      if (canRequestMedia)
                        TourTarget(
                          anchor: TourAnchor.requests,
                          child: _tab(ShellTabs.requests, tr('Demandes')),
                        ),
                      if (canUseLists) _tab(ShellTabs.lists, tr('Listes')),
                      if (canDownload)
                        TourTarget(
                          anchor: TourAnchor.downloads,
                          child:
                              _tab(ShellTabs.downloads, tr('Téléchargements')),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: _sideWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShellIndexerStatus(homeProvider: homeProvider),
                    const AppDownloadButton(),
                    AccountMenu(authProvider: authProvider),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
