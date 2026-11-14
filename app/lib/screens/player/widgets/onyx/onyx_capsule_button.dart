import 'package:flutter/material.dart';

import '../../../../theme/app_motion.dart';
import '../../../../theme/app_type.dart';
import '../../../../theme/focus_fill.dart';
import '../../../../tv/nav/tv_region.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../tv/tv_mode.dart';
import 'onyx_chrome_theme.dart';

/// Une rangée de commandes d'un volet ou d'une fenêtre du lecteur : sur un
/// téléviseur, gauche et droite y restent, Haut et Bas passent à la rangée
/// voisine ([TvRegion.controls]). Ailleurs, rien : le pointeur n'a pas de
/// rangées.
class OnyxControlsRow extends StatelessWidget {
  const OnyxControlsRow({super.key, required this.child, this.preferredFocus});

  final Widget child;

  /// Où la télécommande arrive sur la rangée.
  final FocusNode? preferredFocus;

  @override
  Widget build(BuildContext context) => TvMode.isTv
      ? TvRegion.controls(preferredFocus: preferredFocus, child: child)
      : child;
}

/// Un bouton en capsule du lecteur : « Lire », « Plus tard », « Épisode
/// suivant », une saison (ADR-0130).
///
/// Du verre au repos. Sous la télécommande, la capsule devient blanche à
/// l'encre noire, comme toute commande d'un téléviseur ([FocusFill],
/// ADR-0112) : c'est pourquoi le choix [primary], blanc sous une souris ou un
/// doigt, y reste de verre tant qu'il n'a pas le focus.
class OnyxCapsuleButton extends StatefulWidget {
  const OnyxCapsuleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.selected = false,
    this.large = false,
    this.expanded = false,
    this.busy = false,
    this.focusNode,
  });

  final String label;

  /// Nul : le bouton est présent mais inactif.
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Le choix attendu d'une fenêtre : blanc hors téléviseur.
  final bool primary;

  /// Le choix en cours d'une rangée (la saison affichée).
  final bool selected;

  /// La taille des pages et des fenêtres, plus haute que celle des volets.
  final bool large;

  /// Toute la largeur offerte, le texte au milieu : les réponses empilées
  /// d'une fenêtre de question.
  final bool expanded;

  /// Une attente en cours : un rond qui tourne à la place de l'icône.
  final bool busy;

  final FocusNode? focusNode;

  @override
  State<OnyxCapsuleButton> createState() => _OnyxCapsuleButtonState();
}

class _OnyxCapsuleButtonState extends State<OnyxCapsuleButton> {
  FocusNode? _ownedNode;
  bool _hovered = false;

  FocusNode get _node =>
      widget.focusNode ??
      (_ownedNode ??= FocusNode(debugLabel: 'onyx-capsule'));

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = TvMode.isTv;
    final height = widget.large ? 48.0 : 40.0;
    final radius = BorderRadius.circular(height / 2);
    final enabled = widget.onPressed != null && !widget.busy;
    return TvFocusable(
      focusNode: _node,
      enabled: enabled,
      onSelect: widget.onPressed,
      borderRadius: radius,
      // La capsule dit le focus d'une télécommande ; un clavier garde l'anneau.
      showRing: !tv,
      focusScale: tv ? 1.04 : 1.0,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onPressed : null,
          child: ListenableBuilder(
            listenable: _node,
            builder: (context, _) {
              final lit = tv && _node.hasFocus;
              final white = lit || (!tv && widget.primary);
              final ink = white ? FocusFill.ink : OnyxChromeTheme.title;
              final fill = white
                  ? FocusFill.fill
                  : widget.selected || (_hovered && enabled)
                      ? OnyxChromeTheme.glassControlActive
                      : OnyxChromeTheme.glassControl;
              return AnimatedOpacity(
                duration: AppMotion.move(context, AppMotion.focus),
                opacity: enabled ? 1 : 0.5,
                child: AnimatedContainer(
                  duration: AppMotion.move(context, AppMotion.focus),
                  curve: AppMotion.curve,
                  height: height,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.large ? 26 : 18,
                  ),
                  decoration: BoxDecoration(color: fill, borderRadius: radius),
                  child: Row(
                    mainAxisSize:
                        widget.expanded ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.busy) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: ink),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontSize: widget.large
                                ? AppType.headline
                                : AppType.callout,
                            fontWeight: white || widget.selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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
