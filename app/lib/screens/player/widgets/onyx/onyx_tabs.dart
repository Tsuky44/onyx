import 'package:flutter/material.dart';

import '../../../../theme/app_motion.dart';
import '../../../../theme/app_type.dart';
import '../../../../theme/focus_fill.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../tv/tv_mode.dart';
import 'onyx_chrome_theme.dart';

/// Les onglets du lecteur (ADR-0130), dans l'ordre où ils se rangent.
enum OnyxTab { info, episodes, chapters, watchParty, stats }

/// Un onglet et ce qu'il ouvre.
///
/// Le chrome ne connaît que cela : un nom et de quoi construire le contenu.
/// L'écran du lecteur décide lesquels existent (un film n'a pas d'épisodes,
/// une lecture hors ligne pas de séance) et leur donne leurs données.
class OnyxTabEntry {
  const OnyxTabEntry({
    required this.tab,
    required this.label,
    required this.builder,
    this.marked = false,
  });

  final OnyxTab tab;
  final String label;

  /// Ce que l'onglet ouvre est en cours (une séance à plusieurs) : son nom
  /// reste clair même fermé.
  final bool marked;

  final WidgetBuilder builder;
}

/// Un onglet du lecteur : du texte au repos, une capsule blanche à l'encre
/// noire sous la télécommande ([FocusFill], ADR-0112), une capsule de verre
/// quand son volet est à l'écran sans qu'il tienne le focus.
class OnyxChromeTab extends StatefulWidget {
  const OnyxChromeTab({
    super.key,
    required this.label,
    required this.onPressed,
    this.onFocused,
    this.active = false,
    this.selected = false,
    this.focusNode,
  });

  final String label;

  /// OK à la télécommande, ou un clic.
  final VoidCallback onPressed;

  /// La télécommande arrive sur l'onglet. Sur un téléviseur, c'est ce qui
  /// ouvre son volet : il n'y a rien d'autre à faire d'un onglet qu'on a
  /// rejoint.
  final VoidCallback? onFocused;

  /// Son nom reste clair : ce qu'il ouvre est en cours.
  final bool active;

  /// Son volet est à l'écran.
  final bool selected;

  /// Fourni quand le volet doit pouvoir rendre la télécommande à l'onglet.
  final FocusNode? focusNode;

  static const double height = 36;

  /// Le retrait du texte dans la capsule : le premier onglet se décale
  /// d'autant pour que son texte s'aligne sur le titre.
  static const double inset = 16;

  @override
  State<OnyxChromeTab> createState() => _OnyxChromeTabState();
}

class _OnyxChromeTabState extends State<OnyxChromeTab> {
  FocusNode? _ownedNode;
  bool _hovered = false;

  FocusNode get _node =>
      widget.focusNode ?? (_ownedNode ??= FocusNode(debugLabel: 'onyx-tab'));

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(OnyxChromeTab.height / 2));
    final tv = TvMode.isTv;
    return TvFocusable(
      focusNode: _node,
      onSelect: widget.onPressed,
      onFocusChange: (focused) {
        if (focused) widget.onFocused?.call();
      },
      borderRadius: radius,
      // La capsule dit le focus d'une télécommande ; un clavier garde l'anneau.
      showRing: !tv,
      focusScale: tv ? 1.04 : 1.0,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: ListenableBuilder(
            listenable: _node,
            builder: (context, _) {
              final lit = tv && _node.hasFocus;
              final clear = widget.selected || widget.active || _hovered;
              return AnimatedContainer(
                duration: AppMotion.move(context, AppMotion.focus),
                curve: AppMotion.curve,
                height: OnyxChromeTab.height,
                padding: const EdgeInsets.symmetric(
                  horizontal: OnyxChromeTab.inset,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lit
                      ? FocusFill.fill
                      : widget.selected
                          ? OnyxChromeTheme.glassControl
                          : Colors.transparent,
                  borderRadius: radius,
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: lit
                        ? FocusFill.ink
                        : clear
                            ? OnyxChromeTheme.title
                            : OnyxChromeTheme.meta,
                    fontSize: AppType.headline,
                    fontWeight:
                        lit || clear ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
