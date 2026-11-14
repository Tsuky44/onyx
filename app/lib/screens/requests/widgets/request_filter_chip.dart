import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';

/// Une capsule de la rangée des filtres des demandes.
///
/// Au repos : un contour discret et un chevron, elle ouvre son menu. Active
/// (un filtre posé) : blanche à l'encre noire, comme la ligne allumée des
/// menus Onyx (ADR-0130), avec la valeur ou le compte et un ✕ qui retire le
/// filtre sans rouvrir le menu.
///
/// [onTap] est nul quand un `OnyxMenuButton` enveloppe la capsule et
/// s'occupe d'ouvrir le menu.
class RequestFilterChip extends StatefulWidget {
  const RequestFilterChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
    this.onClear,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  /// Le ✕ d'une capsule active. Nul : pas de ✕ (le tri a toujours une valeur).
  final VoidCallback? onClear;

  static const double height = 34;

  @override
  State<RequestFilterChip> createState() => _RequestFilterChipState();
}

class _RequestFilterChipState extends State<RequestFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final foreground = active ? AppColors.background : AppColors.textPrimary;
    final background = active
        ? AppColors.textPrimary
        : _hovered
            ? AppColors.surfaceElevated
            : AppColors.surface;
    final clear = active ? widget.onClear : null;
    final pill = AnimatedContainer(
      duration: AppMotion.fade(context, AppMotion.micro),
      curve: AppMotion.curve,
      height: RequestFilterChip.height,
      padding: EdgeInsets.only(left: 14, right: clear == null ? 12 : 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? AppColors.textPrimary : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: AppType.subhead,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          if (clear == null)
            Icon(AppIcons.expand, size: 14, color: foreground)
          else
            _ClearButton(color: foreground, onPressed: clear),
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? pill
          // InkWell pour le focus clavier et Entrée ; son encre passe sous
          // le fond de la capsule, c'est le survol qui éclaire.
          : InkWell(
              onTap: widget.onTap,
              customBorder: const StadiumBorder(),
              onFocusChange: (focused) => setState(() => _hovered = focused),
              child: pill,
            ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.color, required this.onPressed});

  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Retirer le filtre'),
      child: Semantics(
        button: true,
        label: tr('Retirer le filtre'),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(AppIcons.close, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}
