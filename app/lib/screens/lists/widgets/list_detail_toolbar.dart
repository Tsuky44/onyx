// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/onyx_menu.dart';
import '../../player/widgets/onyx/onyx_capsule_button.dart';
import '../../player/widgets/onyx/onyx_chrome_theme.dart';
import '../list_detail_view.dart';

/// Les onglets Tous / À voir / Vus / À demander d'une liste et son tri, sous
/// l'en-tête, en capsules (ADR-0161) : l'onglet ouvert est la capsule
/// blanche, les autres du verre. Un onglet sans titre ne se montre pas, sauf
/// « Tous » et celui qui est ouvert.
class ListDetailToolbar extends StatelessWidget {
  const ListDetailToolbar({
    super.key,
    required this.filter,
    required this.counts,
    required this.sort,
    required this.onFilter,
    required this.onSort,
  });

  final WatchListFilter filter;
  final Map<WatchListFilter, int> counts;
  final WatchListSort sort;
  final ValueChanged<WatchListFilter> onFilter;
  final ValueChanged<WatchListSort> onSort;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final tabs = [
      for (final f in WatchListFilter.values)
        if (f == WatchListFilter.all || f == filter || (counts[f] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              selected: f == filter,
              child: OnyxCapsuleButton(
                label: '${f.label} · ${counts[f] ?? 0}',
                primary: f == filter,
                selected: f == filter,
                onPressed: () => onFilter(f),
              ),
            ),
          ),
    ];
    final sorter = OnyxMenuButton<WatchListSort>(
      tooltip: tr('Trier'),
      items: [
        for (final s in WatchListSort.values)
          OnyxMenuItem(value: s, label: s.label, checked: s == sort),
      ],
      onSelected: onSort,
      child: _GlassChip(
        icon: AppIcons.sort,
        label: compact ? null : sort.label,
      ),
    );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: tabs),
          ),
        ),
        const SizedBox(width: 8),
        sorter,
      ],
    );
  }
}

/// L'apparence d'une capsule de verre, sans geste à elle : le déclencheur
/// d'un [OnyxMenuButton], qui tient le geste et le focus.
class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: label == null ? 12 : 16),
      decoration: BoxDecoration(
        color: OnyxChromeTheme.glassControl,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: OnyxChromeTheme.title),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: OnyxChromeTheme.title,
                    fontSize: AppType.callout,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(AppIcons.expand, size: 16, color: OnyxChromeTheme.meta),
          ],
        ],
      ),
    );
  }
}
