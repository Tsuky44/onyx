// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../widgets/global/app_network_image.dart';
import '../../../widgets/global/onyx_menu.dart';
import 'list_progress.dart';
import 'watch_list_tile.dart' show watchListCaption;

/// Les listes où le compte peut ranger des titres, sauf [except] : les
/// siennes puis celles où il est invité à les remplir (ADR-0127). Ce que
/// proposent « Déplacer vers… » et « Copier vers… ».
List<WatchList> listTargets(WatchListsOverview overview, {int? except}) => [
      for (final list in [
        ...overview.mine,
        ...overview.shared.where((l) => l.canEdit),
      ])
        if (list.id != except) list,
    ];

/// Ce que le compte a choisi dans « Déplacer vers… » : une liste, ou une
/// liste à créer ([list] nulle).
@immutable
class ListTarget {
  const ListTarget(this.list);

  final WatchList? list;

  bool get isNew => list == null;
}

/// Demande dans quelle liste ranger des titres, dans un menu Onyx collé à
/// [anchor] (ADR-0161) : chaque liste avec la mosaïque de ses affiches et sa
/// légende, les siennes puis celles des autres, et « Nouvelle liste… » en
/// pied. Null quand on ferme sans choisir.
Future<ListTarget?> showListTargetPicker(
  BuildContext context, {
  required BuildContext anchor,
  required List<WatchList> targets,
}) async {
  final mine = [
    for (final l in targets)
      if (l.isMine) l
  ];
  final others = [
    for (final l in targets)
      if (!l.isMine) l
  ];
  OnyxMenuItem<WatchList?> row(WatchList list, String? section) =>
      OnyxMenuItem<WatchList?>(
        value: list,
        label: list.displayName,
        subtitle: watchListCaption(list),
        leading: _Mosaic(urls: watchListPosterUrls(context, list, max: 4)),
        section: section,
      );
  final pick = await showOnyxMenu<WatchList?>(
    context: context,
    anchorContext: anchor,
    items: [
      for (final (i, l) in mine.indexed)
        row(l, i == 0 && others.isNotEmpty ? tr('Mes listes') : null),
      for (final (i, l) in others.indexed)
        row(l, i == 0 ? tr('Partagées avec moi') : null),
      OnyxMenuItem<WatchList?>(
        value: null,
        label: tr('Nouvelle liste…'),
        icon: AppIcons.add,
      ),
    ],
  );
  return pick == null ? null : ListTarget(pick.value);
}

/// Quatre affiches en carré de deux sur deux, au format d'une affiche : une
/// liste se reconnaît à ce qu'elle contient avant son nom.
class _Mosaic extends StatelessWidget {
  const _Mosaic({required this.urls});

  final List<String?> urls;

  static const double _width = 28;

  @override
  Widget build(BuildContext context) {
    Widget tile(int i) => Expanded(
          child: i < urls.length && urls[i] != null
              ? AppNetworkImage(
                  url: urls[i],
                  fit: BoxFit.cover,
                  decodeWidth: _width,
                  placeholder: const ColoredBox(color: AppColors.surfaceHover),
                  errorWidget: const ColoredBox(color: AppColors.surfaceHover),
                )
              : const ColoredBox(color: AppColors.surfaceHover),
        );
    // Le filet garde la forme d'une liste encore vide, que ses cases grises
    // laisseraient fondre dans le panneau.
    return Container(
      width: _width,
      height: _width * 1.5,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Column(
          children: [
            Expanded(child: Row(children: [tile(0), tile(1)])),
            Expanded(child: Row(children: [tile(2), tile(3)])),
          ],
        ),
      ),
    );
  }
}
