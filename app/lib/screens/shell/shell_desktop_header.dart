import 'package:flutter/material.dart';

import '../../desktop_window.dart';
import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../utils/app_platform.dart';
import '../../utils/window_controls.dart';
import '../../widgets/global/account_menu.dart';
import '../../widgets/global/app_download_button.dart';
import '../../widgets/global/glass_catalog_search.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/interface_tour/tour_anchor.dart';
import 'shell_indexer_status.dart';
import 'shell_tabs.dart';

/// L'en-tête de verre des grands écrans : la marque, les onglets, la
/// recherche et le compte.
class ShellDesktopHeader extends StatelessWidget {
  /// L'identifiant de l'onglet affiché (voir [ShellTabs]).
  final String selected;
  final ValueChanged<String> onTabSelected;

  /// Les bibliothèques du serveur : un onglet chacune, sous son nom.
  final List<MediaLibrary> libraries;
  final HomeProvider homeProvider;
  final AuthProvider authProvider;

  /// Faux sur le web, où il n'y a pas d'espace de stockage applicatif : sans
  /// destination possible, l'onglet n'existe pas.
  final bool canDownload;

  /// Le serveur tient des listes (ADR-0070).
  final bool canUseLists;

  /// Le droit request_media et un compagnon réglé ([canRequestMedia]).
  final bool canRequestMedia;

  /// Le nœud de focus d'un onglet, possédé par la coquille.
  final FocusNode Function(String tab) nodeFor;

  const ShellDesktopHeader({
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

  Widget _tab(String tab, String label) => GlassNavTab(
        label: label,
        selected: selected == tab,
        focusNode: nodeFor(tab),
        onTap: () => onTabSelected(tab),
      );

  @override
  Widget build(BuildContext context) {
    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28,
          6 + macOSWindowControlsTopInset,
          28,
          10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GlassBrand(onTap: () => onTabSelected(ShellTabs.home)),
            const SizedBox(width: 20),
            // Le nombre de bibliothèques n'est pas borné : au-delà de la
            // place disponible leurs onglets défilent, sans pousser la
            // recherche ni le compte hors de l'en-tête.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TourTarget(
                      anchor: TourAnchor.library,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _tab(ShellTabs.home, tr('Accueil')),
                          for (final library in libraries)
                            _tab(ShellTabs.library(library),
                                ShellTabs.label(library)),
                        ],
                      ),
                    ),
                    // The whole request catalog sits behind request_media
                    // server-side, and asks MediaHub for every request: an
                    // account without the right, or a server without a
                    // companion, gets no entry point either.
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
            ),
            const SizedBox(width: 12),
            const TourTarget(
              anchor: TourAnchor.search,
              child: GlassCatalogSearch(
                collapsedWidth: 200,
                expandedWidth: 280,
                staysAbovePages: true,
              ),
            ),
            const SizedBox(width: 12),
            ShellIndexerStatus(homeProvider: homeProvider),
            const AppDownloadButton(),
            AccountMenu(authProvider: authProvider),
          ],
        ),
      ),
    );

    return GlassHeaderStrip(
      child: AppPlatform.isMacOS
          ? Stack(
              children: [
                // Empty zones (title bar / spacer) drag the window; buttons
                // above still receive hits and don't block trackpad scroll.
                const Positioned.fill(
                  child: WindowDragArea(child: SizedBox.expand()),
                ),
                header,
              ],
            )
          : header,
    );
  }
}
