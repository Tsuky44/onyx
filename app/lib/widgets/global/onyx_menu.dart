import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../tv/tv_mode.dart';
import 'onyx_menu_route.dart';

export 'onyx_menu_route.dart' show showOnyxMenu;

/// Une ligne d'[OnyxMenuButton].
///
/// [leading] remplace [icon] quand la ligne porte autre chose qu'une icône
/// (la pastille d'une personne, par exemple). Dès qu'une ligne du menu est
/// [checked], le menu est un menu de choix : chaque ligne réserve la place de
/// la coche à droite, et une longue liste s'ouvre défilée sur la ligne cochée.
/// Les lignes [destructive] se rangent en fin de menu, sous un filet que le
/// panneau pose lui-même. Une ligne qui porte une [section] ouvre un groupe :
/// un filet (sauf en tête de menu) puis ce titre en petites capitales.
@immutable
class OnyxMenuItem<T> {
  const OnyxMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.leading,
    this.subtitle,
    this.checked = false,
    this.destructive = false,
    this.enabled = true,
    this.section,
  }) : assert(icon == null || leading == null,
            'Une ligne a une icône ou un widget de tête, pas les deux.');

  /// Rendu à [OnyxMenuButton.onSelected]. Peut être nul : un choix nul
  /// (« Automatique ») se distingue d'un menu fermé sans choix.
  final T value;
  final String label;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final bool checked;
  final bool destructive;
  final bool enabled;

  /// Le titre du groupe que cette ligne ouvre (« Administration »).
  final String? section;
}

/// Un menu surgissant dans la matière du menu du compte (ADR-0126) : un
/// panneau sombre dont la ligne survolée ou focalisée se remplit de blanc à
/// l'encre noire. Voir ADR-0130.
///
/// Le déclencheur est soit [icon] (un bouton-icône), soit [child] (le
/// déclencheur de l'appelant, rendu cliquable). Exactement l'un des deux.
///
/// ```dart
/// OnyxMenuButton<SortMode>(
///   tooltip: tr('Trier'),
///   icon: AppIcons.sort,
///   items: [
///     for (final mode in SortMode.values)
///       OnyxMenuItem(value: mode, label: mode.label, checked: mode == sort),
///   ],
///   onSelected: onSortChanged,
/// )
/// ```
///
/// Sur un téléviseur, le bouton rend encore le `PopupMenuButton` de Material,
/// le temps que la TV ait sa propre refonte : rien n'y change.
class OnyxMenuButton<T> extends StatefulWidget {
  const OnyxMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon,
    this.child,
    this.tooltip,
    this.iconColor,
    this.enabled = true,
  }) : assert((icon == null) != (child == null),
            'Un déclencheur : icon ou child, l’un des deux.');

  final List<OnyxMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData? icon;
  final Widget? child;
  final String? tooltip;

  /// La couleur de [icon] ; `textSecondary` par défaut.
  final Color? iconColor;
  final bool enabled;

  @override
  State<OnyxMenuButton<T>> createState() => _OnyxMenuButtonState<T>();
}

class _OnyxMenuButtonState<T> extends State<OnyxMenuButton<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final pick = await showOnyxMenu<T>(
      context: context,
      anchorKey: _anchorKey,
      items: widget.items,
    );
    if (pick != null && mounted) widget.onSelected(pick.value);
  }

  @override
  Widget build(BuildContext context) {
    if (TvScope.of(context)) return _materialFallback();
    final enabled = widget.enabled && widget.items.isNotEmpty;
    final icon = widget.icon;
    if (icon != null) {
      return IconButton(
        key: _anchorKey,
        tooltip: widget.tooltip,
        onPressed: enabled ? _open : null,
        icon: Icon(icon, color: widget.iconColor ?? AppColors.textSecondary),
      );
    }
    final trigger = InkWell(
      key: _anchorKey,
      onTap: enabled ? _open : null,
      borderRadius: BorderRadius.circular(12),
      child: widget.child,
    );
    final tooltip = widget.tooltip;
    return tooltip == null
        ? trigger
        : Tooltip(message: tooltip, child: trigger);
  }

  /// L'ancien menu, pour un téléviseur. Les valeurs passent dans un
  /// enregistrement : `PopupMenuButton` prend un choix nul pour une fermeture.
  Widget _materialFallback() {
    final icon = widget.icon;
    return PopupMenuButton<({T value})>(
      tooltip: widget.tooltip,
      enabled: widget.enabled,
      color: AppColors.surfaceElevated,
      onSelected: (pick) => widget.onSelected(pick.value),
      icon: icon == null
          ? null
          : Icon(icon, color: widget.iconColor ?? AppColors.textSecondary),
      itemBuilder: (_) => [
        for (final item in widget.items)
          PopupMenuItem<({T value})>(
            value: (value: item.value),
            enabled: item.enabled,
            child: Row(
              children: [
                if (item.leading != null) ...[
                  item.leading!,
                  const SizedBox(width: 12),
                ] else if (item.icon != null) ...[
                  Icon(item.icon, size: 18),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    style: item.destructive
                        ? const TextStyle(color: AppColors.error)
                        : null,
                  ),
                ),
                if (item.checked) ...[
                  const SizedBox(width: 12),
                  const Icon(AppIcons.check, size: 16),
                ],
              ],
            ),
          ),
      ],
      child: widget.child,
    );
  }
}
