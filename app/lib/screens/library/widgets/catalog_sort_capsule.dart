import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../theme/focus_fill.dart';
import '../../../tv/nav/tv_focusable.dart';
import '../../../widgets/global/glass_chrome.dart';

/// Le tri d'un catalogue sur téléviseur : une capsule de verre en haut à
/// droite de la grille (ADR-0125), qui ouvre le menu de [CatalogHeader].
///
/// Le même dessin que la pilule des onglets (`TvTabBar`, ADR-0117) : du verre
/// au repos, pour se lire sur les affiches qui défilent dessous, et le blanc
/// à l'encre noire de toute commande focalisée ([FocusFill], ADR-0112). Un
/// `PopupMenuButton` n'a pas d'état focalisé à lui : son libellé gris restait
/// gris sur le voile du focus.
class CatalogSortCapsule<T> extends StatefulWidget {
  const CatalogSortCapsule({
    super.key,
    required this.sortOptions,
    required this.sort,
    required this.onSortChanged,
  });

  final Map<T, String> sortOptions;
  final T sort;
  final ValueChanged<T> onSortChanged;

  /// La hauteur de la capsule, en pixels de la page TV (1280 de large).
  static const double height = 36;

  @override
  State<CatalogSortCapsule<T>> createState() => _CatalogSortCapsuleState<T>();
}

class _CatalogSortCapsuleState<T> extends State<CatalogSortCapsule<T>> {
  bool _focused = false;

  Future<void> _open() async {
    final button = context.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return;
    // Sous la capsule, calé sur ses bords : le menu, plus large qu'elle,
    // s'arrête à la marge de l'écran.
    final below = Rect.fromPoints(
      button.localToGlobal(button.size.bottomLeft(const Offset(0, 8)),
          ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(const Offset(0, 8)),
          ancestor: overlay),
    );
    final picked = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(below, Offset.zero & overlay.size),
      initialValue: widget.sort,
      constraints: const BoxConstraints(minWidth: 220),
      items: [
        for (final entry in widget.sortOptions.entries)
          PopupMenuItem<T>(
            value: entry.key,
            child: Row(
              children: [
                Expanded(child: Text(tr(entry.value))),
                if (entry.key == widget.sort) ...[
                  const SizedBox(width: 16),
                  const Icon(AppIcons.check, size: 18),
                ],
              ],
            ),
          ),
      ],
    );
    if (picked != null) widget.onSortChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(
      Radius.circular(CatalogSortCapsule.height / 2),
    );
    final ink = _focused ? FocusFill.ink : AppColors.textPrimary;
    final quiet = _focused
        ? FocusFill.ink.withValues(alpha: 0.62)
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      label: tr('Trier'),
      child: TvFocusable(
        onSelect: _open,
        onFocusChange: (focused) => setState(() => _focused = focused),
        // La capsule dessine son focus elle-même, comme un onglet.
        showRing: false,
        focusScale: 1.04,
        borderRadius: radius,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: AnimatedContainer(
            duration: AppMotion.fade(context, AppMotion.micro),
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: _focused
                  ? const [
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            child: GlassSurface(
              borderRadius: radius,
              child: AnimatedContainer(
                duration: AppMotion.fade(context, AppMotion.micro),
                curve: AppMotion.curve,
                // Le verre a un filet de 1 px de chaque côté.
                height: CatalogSortCapsule.height - 2,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: _focused ? FocusFill.fill : Colors.transparent,
                  borderRadius: radius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.sortOrder, size: 17, color: quiet),
                    const SizedBox(width: 9),
                    Text(
                      tr(widget.sortOptions[widget.sort] ?? ''),
                      style: TextStyle(
                        color: ink,
                        fontSize: AppType.callout,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Icon(AppIcons.expand, size: 14, color: quiet),
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
