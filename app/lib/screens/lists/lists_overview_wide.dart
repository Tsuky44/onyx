import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/tr.dart';
import '../../models/watch_list.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/responsive.dart';
import '../../utils/search_match.dart' show foldForSearch;
import '../../widgets/global/onyx_menu.dart';
import '../../widgets/global/sliver_scroll_end.dart';
import 'widgets/watch_later_hero.dart';
import 'widgets/watch_list_cards.dart';

/// L'ordre de « Mes listes » dans la vue large.
enum WatchListSort {
  /// Celui du serveur : la dernière modifiée d'abord.
  recent,
  name;

  String get label => switch (this) {
        WatchListSort.recent => tr('Récentes'),
        WatchListSort.name => tr('Nom'),
      };
}

/// Les listes de [lists] dans l'ordre [sort] ; « À regarder plus tard » n'y
/// est pas, elle a son encart.
List<WatchList> sortedWatchLists(List<WatchList> lists, WatchListSort sort) {
  final sorted = [...lists];
  if (sort == WatchListSort.name) {
    // foldForSearch : « À commander » se range avec les A, pas après les Z.
    sorted.sort((a, b) =>
        foldForSearch(a.displayName).compareTo(foldForSearch(b.displayName)));
  }
  return sorted;
}

/// Les colonnes de la grille de cartes de la vue large.
const int kListsWideColumns = 3;
const double _gridGap = 20;

/// La vue d'ensemble des listes pour la grande fenêtre (ADR-0159) : l'encart
/// « À regarder plus tard », « Mes listes » en cartes à bandeau d'affiches,
/// puis « Partagées par les autres » au second plan.
///
/// Rend des slivers, à poser dans le défilement de l'écran des listes.
List<Widget> wideListsSlivers(
  BuildContext context, {
  required WatchListsOverview overview,
  required WatchListSort sort,
  required ValueChanged<WatchListSort> onSort,
  required ValueChanged<WatchList> onOpen,
  required VoidCallback onRefresh,
}) {
  final padding = AppLayout.pagePadding(context);
  final watchLater = overview.mine.where((l) => l.isWatchLater).firstOrNull;
  final mine = sortedWatchLists(
      overview.mine.where((l) => !l.isWatchLater).toList(), sort);

  SliverGridDelegate delegate(double Function(double width) extent) =>
      _FixedExtentGrid(extent);

  return [
    if (watchLater != null)
      SliverPadding(
        padding: EdgeInsets.fromLTRB(padding, 0, padding, 8),
        sliver: SliverToBoxAdapter(
          child: WatchLaterHero(
            list: watchLater,
            onOpen: () => onOpen(watchLater),
            onPlayed: onRefresh,
          ),
        ),
      ),
    _WideSection(
      title: '${tr('Mes listes')} · ${mine.length}',
      trailing: mine.length > 1 ? _SortMenu(sort: sort, onSort: onSort) : null,
    ),
    if (mine.isEmpty)
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        sliver: SliverToBoxAdapter(
          child: Text(
            tr('Créez une liste pour y ranger ce que vous voulez regarder.'),
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      )
    else
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        sliver: SliverGrid(
          gridDelegate:
              delegate((width) => WatchListCard.heightFor(context, width)),
          delegate: SliverChildBuilderDelegate(
            (context, index) => WatchListCard(
              list: mine[index],
              onTap: () => onOpen(mine[index]),
            ),
            childCount: mine.length,
          ),
        ),
      ),
    _WideSection(
        title: '${tr('Partagées par les autres')} · ${overview.shared.length}'),
    SliverPadding(
      padding: EdgeInsets.fromLTRB(
          padding, 0, padding, SliverScrollEnd.extentOf(context)),
      sliver: overview.shared.isEmpty
          ? const SliverToBoxAdapter(child: NoSharedListsFrame())
          : SliverGrid(
              gridDelegate: delegate((_) {
                final scaler = MediaQuery.textScalerOf(context);
                return scaler.scale(96);
              }),
              delegate: SliverChildBuilderDelegate(
                (context, index) => SharedWatchListCard(
                  list: overview.shared[index],
                  onTap: () => onOpen(overview.shared[index]),
                ),
                childCount: overview.shared.length,
              ),
            ),
    ),
  ];
}

/// Trois colonnes de cartes dont la hauteur se déduit de leur largeur : le
/// bandeau d'affiches garde ses proportions quelle que soit la fenêtre.
class _FixedExtentGrid extends SliverGridDelegate {
  const _FixedExtentGrid(this.extentFor);

  final double Function(double cardWidth) extentFor;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width =
        (constraints.crossAxisExtent - (kListsWideColumns - 1) * _gridGap) /
            kListsWideColumns;
    final height = extentFor(width);
    return SliverGridRegularTileLayout(
      crossAxisCount: kListsWideColumns,
      mainAxisStride: height + _gridGap,
      crossAxisStride: width + _gridGap,
      childMainAxisExtent: height,
      childCrossAxisExtent: width,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(_FixedExtentGrid old) => true;
}

class _WideSection extends StatelessWidget {
  const _WideSection({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final padding = AppLayout.pagePadding(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padding, 24, padding, 14),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppType.title3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onSort});

  final WatchListSort sort;
  final ValueChanged<WatchListSort> onSort;

  @override
  Widget build(BuildContext context) {
    // Le menu d'Onyx (ADR-0130), comme le tri du détail d'une liste.
    return OnyxMenuButton<WatchListSort>(
      tooltip: tr('Trier'),
      onSelected: onSort,
      items: [
        for (final option in WatchListSort.values)
          OnyxMenuItem(
              value: option, label: option.label, checked: option == sort),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.sortOrder,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              sort.label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: AppType.subhead),
            ),
          ],
        ),
      ),
    );
  }
}
