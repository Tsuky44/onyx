import 'package:flutter/material.dart';

import '../../../../theme/app_motion.dart';
import '../../../../tv/nav/tv_region.dart';
import 'onyx_chrome_theme.dart';
import 'onyx_glass_panel.dart';
import 'onyx_tabs.dart';

/// Les onglets sous la barre de lecture d'un téléviseur, et le volet de verre
/// qu'ils ouvrent (ADR-0130) : Infos, Épisodes, Chapitres, Regarder ensemble,
/// Stats.
///
/// Descendre de la barre sur un onglet ouvre son volet : la barre remonte
/// pour lui laisser la place, comme dans le lecteur d'Apple. Gauche et droite
/// changent d'onglet, Bas entre dans le contenu, et le volet se referme quand
/// la télécommande le quitte (Haut vers la barre, Retour). Un onglet sans rien
/// à ouvrir n'est pas dans [tabs] : l'écran du lecteur ne le donne pas.
///
/// Remplace les trois onglets de l'ADR-0124, où « Infos » dépliait son texte
/// sous la rangée et où les deux autres ouvraient chacun son panneau : c'est
/// le « second chantier » que cette ADR avait laissé de côté.
class OnyxTvTabs extends StatefulWidget {
  const OnyxTvTabs({
    super.key,
    required this.metrics,
    required this.visible,
    required this.tabs,
    required this.open,
    required this.onChanged,
  });

  final OnyxChromeMetrics metrics;

  /// Le chrome est à l'écran. Quand il se cache, le volet se replie : le
  /// chrome revient toujours dans son état de repos.
  final bool visible;

  final List<OnyxTabEntry> tabs;

  /// L'onglet dont le volet est à l'écran, ou nul.
  final OnyxTab? open;
  final ValueChanged<OnyxTab?> onChanged;

  /// La hauteur du contenu d'un onglet : avec la rangée d'onglets et ses
  /// marges, le volet prend un peu moins de la moitié basse de l'écran.
  static const double contentHeight = 238;

  @override
  State<OnyxTvTabs> createState() => _OnyxTvTabsState();
}

class _OnyxTvTabsState extends State<OnyxTvTabs> {
  final Map<OnyxTab, FocusNode> _nodes = <OnyxTab, FocusNode>{};

  /// Le dernier onglet ouvert : la télécommande y revient en redescendant de
  /// la barre, au lieu de l'onglet le plus proche du milieu de l'écran.
  OnyxTab? _lastOpen;

  FocusNode _nodeFor(OnyxTab tab) => _nodes.putIfAbsent(
        tab,
        () => FocusNode(debugLabel: 'onyx-tab-${tab.name}'),
      );

  @override
  void didUpdateWidget(OnyxTvTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != null) _lastOpen = widget.open;
    if (!widget.visible && widget.open != null) {
      // Après l'image : l'écran qui tient l'onglet ouvert est en train de se
      // construire.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.visible && widget.open != null) {
          widget.onChanged(null);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// La télécommande a quitté les onglets et leur volet.
  void _handleFocusChange(bool hasFocus) {
    final open = widget.open;
    if (hasFocus || open == null || !mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    // Le focus n'est allé nulle part : la commande qui le tenait a disparu
    // (« Démarrer une séance », remplacé par le code de la séance). Le volet
    // reste, et son onglet reprend la télécommande.
    if (primary == null || primary is FocusScopeNode) {
      final node = _nodes[open];
      if (node != null && node.context != null && node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final open =
        widget.tabs.where((entry) => entry.tab == widget.open).firstOrNull;
    final isOpen = open != null;
    // Où la télécommande arrive sur la rangée : l'onglet dont le volet est
    // ouvert quand elle remonte du contenu, sinon le dernier ouvert, sinon le
    // premier. Sans cela, la rangée rend l'onglet le plus proche à
    // l'horizontale, et remonter d'une carte changeait de volet.
    final entryTab = widget.tabs.any((entry) => entry.tab == widget.open)
        ? widget.open
        : widget.tabs.any((entry) => entry.tab == _lastOpen)
            ? _lastOpen
            : widget.tabs.firstOrNull?.tab;

    final row = Padding(
      // Le texte du premier onglet s'aligne sur le titre : sa capsule, elle,
      // déborde de son retrait intérieur.
      padding: EdgeInsets.only(
        left: m.gutter - OnyxChromeTab.inset,
        right: m.gutter,
      ),
      child: TvRegion.controls(
        preferredFocus: entryTab == null ? null : _nodeFor(entryTab),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in widget.tabs)
              OnyxChromeTab(
                key: ValueKey('onyx-tab-${entry.tab.name}'),
                label: entry.label,
                focusNode: _nodeFor(entry.tab),
                active: entry.marked,
                selected: entry.tab == widget.open,
                onFocused: () => widget.onChanged(entry.tab),
                onPressed: () => widget.onChanged(entry.tab),
              ),
          ],
        ),
      ),
    );

    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: isOpen ? 20 : 8),
        Stack(
          children: [
            // Toujours là, vide quand le volet est fermé : la rangée
            // d'onglets garde ainsi sa place dans l'arbre, et son focus.
            Positioned.fill(
              child: isOpen
                  ? const OnyxGlassPanel(
                      radius: BorderRadius.zero,
                      outlined: false,
                      elevated: false,
                      child: SizedBox.expand(),
                    )
                  : const SizedBox.shrink(),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: isOpen ? 18 : 0),
                row,
                if (isOpen)
                  Padding(
                    padding: EdgeInsets.fromLTRB(m.gutter, 24, m.gutter, 0),
                    child: SizedBox(
                      height: OnyxTvTabs.contentHeight,
                      width: double.infinity,
                      child: KeyedSubtree(
                        key: ValueKey(open.tab),
                        child: open.builder(context),
                      ),
                    ),
                  ),
                SizedBox(height: m.bottomInset),
              ],
            ),
          ],
        ),
      ],
    );

    return Focus(
      // Jamais une destination : ce nœud ne sert qu'à savoir quand la
      // télécommande quitte les onglets et leur volet.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _handleFocusChange,
      // Sous « réduire les animations », le volet se pose d'un coup. Sans
      // `AnimatedSize` du tout : une durée nulle le fait se redemander une
      // mise en page pendant la sienne.
      child: AppMotion.reduced(context)
          ? panel
          : AnimatedSize(
              duration: AppMotion.emphasis,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: panel,
            ),
    );
  }
}
