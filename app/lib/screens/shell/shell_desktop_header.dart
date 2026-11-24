import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../desktop_window.dart';
import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/search_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../utils/window_controls.dart';
import '../../widgets/global/account_menu.dart';
import '../../widgets/global/app_download_button.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/interface_tour/tour_anchor.dart';
import '../../widgets/global/window_caption_buttons.dart';
import 'desktop_header_search.dart';
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

  /// Le nom de l'onglet affiché, que rappelle le retour de la recherche.
  String _labelOf(String tab) {
    for (final library in libraries) {
      if (ShellTabs.library(library) == tab) return ShellTabs.label(library);
    }
    return switch (tab) {
      ShellTabs.requests => tr('Demandes'),
      ShellTabs.lists => tr('Listes'),
      ShellTabs.downloads => tr('Téléchargements'),
      _ => tr('Accueil'),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Le nombre de bibliothèques n'est pas borné : au-delà de la place
    // disponible leurs onglets défilent, sans pousser la recherche ni le
    // compte hors de l'en-tête.
    final tabs = SingleChildScrollView(
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
                  _tab(ShellTabs.library(library), ShellTabs.label(library)),
              ],
            ),
          ),
          // The whole request catalog sits behind request_media
          // server-side, and asks MediaHub for every request: an account
          // without the right, or a server without a companion, gets no
          // entry point either.
          if (canRequestMedia)
            TourTarget(
              anchor: TourAnchor.requests,
              child: _tab(ShellTabs.requests, tr('Demandes')),
            ),
          if (canUseLists) _tab(ShellTabs.lists, tr('Listes')),
          if (canDownload)
            TourTarget(
              anchor: TourAnchor.downloads,
              child: _tab(ShellTabs.downloads, tr('Téléchargements')),
            ),
        ],
      ),
    );

    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28,
          6 + macOSWindowControlsTopInset,
          // Les contrôles de la fenêtre ont leur propre marge intérieure :
          // Fermer reste près du coin, où la main le cherche.
          useDesktopCaptionBar ? 12 : 28,
          10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GlassBrand(onTap: () => onTabSelected(ShellTabs.home)),
            const SizedBox(width: 20),
            // Les onglets et la recherche se partagent le milieu de
            // l'en-tête : quand la recherche s'ouvre, les onglets s'effacent
            // et le champ glisse au centre (ADR-0139).
            Expanded(
              child: _SearchAndTabs(
                tabs: tabs,
                selectedLabel: _labelOf(selected),
                onBack: () => onTabSelected(selected),
              ),
            ),
            const SizedBox(width: 12),
            ShellIndexerStatus(homeProvider: homeProvider),
            const AppDownloadButton(),
            AccountMenu(authProvider: authProvider),
            if (useDesktopCaptionBar) const _WindowControlsCluster(),
          ],
        ),
      ),
    );

    return GlassHeaderStrip(
      child: useHiddenNativeTitleBar
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

/// Sous Windows, les contrôles de la fenêtre au bout de la rangée, après un
/// trait qui les sépare du compte (ADR-0157) : l'en-tête les porte, et la
/// bande du haut s'efface ([WindowCaptionHost]).
class _WindowControlsCluster extends StatelessWidget {
  const _WindowControlsCluster();

  @override
  Widget build(BuildContext context) {
    return WindowCaptionHost(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.only(left: 18, right: 14),
            color: Colors.white.withValues(alpha: 0.16),
          ),
          const WindowCaptionButtons(),
        ],
      ),
    );
  }
}

/// Le milieu de l'en-tête : les onglets au repos, la recherche ouverte.
///
/// Au repos, le champ attend à droite des onglets et montre son raccourci.
/// Ouvert, il glisse au centre en s'élargissant ; les onglets s'effacent, et
/// un rappel de la page quittée (« ‹ Accueil ») prend leur place à gauche
/// pour y revenir d'un clic.
class _SearchAndTabs extends StatelessWidget {
  const _SearchAndTabs({
    required this.tabs,
    required this.selectedLabel,
    required this.onBack,
  });

  final Widget tabs;
  final String selectedLabel;
  final VoidCallback onBack;

  /// Le champ au repos : « Rechercher » et son raccourci y tiennent.
  static const double idleWidth = 230;

  /// Le champ ouvert, au plus : une recherche de titre n'a pas besoin de
  /// plus, et le centre de l'en-tête reste aéré.
  static const double openWidth = 620;

  /// La place du rappel de la page quittée, de part et d'autre du champ
  /// centré.
  static const double backWidth = 150;

  /// La hauteur de la rangée de l'en-tête (`shellHeaderHeight`).
  static const double rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    final open = context.select<SearchProvider, bool>((s) => s.isExpanded);
    final move = AppMotion.move(context);
    final fade = AppMotion.fade(context);

    return LayoutBuilder(
      builder: (context, box) {
        final width = open
            ? math.max(
                idleWidth,
                math.min(openWidth, box.maxWidth - 2 * backWidth),
              )
            : math.min(idleWidth, box.maxWidth);
        return SizedBox(
          height: rowHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                right: idleWidth + 16,
                child: AnimatedOpacity(
                  opacity: open ? 0 : 1,
                  duration: fade,
                  curve: AppMotion.curve,
                  child: IgnorePointer(
                    ignoring: open,
                    child: ExcludeFocus(
                      excluding: open,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: tabs,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: backWidth,
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: fade,
                  curve: AppMotion.curve,
                  child: IgnorePointer(
                    ignoring: !open,
                    child: _BackToPage(label: selectedLabel, onTap: onBack),
                  ),
                ),
              ),
              AnimatedAlign(
                alignment: open ? Alignment.center : Alignment.centerRight,
                duration: move,
                curve: AppMotion.curve,
                child: TourTarget(
                  anchor: TourAnchor.search,
                  child: DesktopHeaderSearch(width: width),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// « ‹ Accueil » : referme la recherche et rend la page qu'on regardait.
class _BackToPage extends StatefulWidget {
  const _BackToPage({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_BackToPage> createState() => _BackToPageState();
}

class _BackToPageState extends State<_BackToPage> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ink = _hovered ? AppColors.textPrimary : AppColors.textSecondary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: tr('Fermer la recherche'),
        child: Semantics(
          button: true,
          label: tr('Revenir à {0}', [widget.label]),
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.back, size: 16, color: ink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
