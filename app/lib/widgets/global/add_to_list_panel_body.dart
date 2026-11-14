import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/watch_list.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import 'empty_state.dart';
import 'onyx_menu.dart';
import 'onyx_menu_panel.dart';

/// Le contenu de « Ajouter à une liste » dans un panneau de grand écran
/// (ADR-0131) : un titre de section en petites capitales, les listes avec
/// leur coche, un filet, puis « Nouvelle liste ». Les lignes sont celles des
/// menus : survol et focus les remplissent de blanc à l'encre noire.
class AddToListPanelBody extends StatelessWidget {
  const AddToListPanelBody({
    super.key,
    required this.title,
    required this.lists,
    required this.error,
    required this.pending,
    required this.onToggle,
    required this.onCreate,
    required this.onRetry,
  });

  final String title;
  final List<WatchList>? lists;
  final String? error;
  final Set<int> pending;
  final ValueChanged<WatchList> onToggle;
  final VoidCallback onCreate;
  final VoidCallback onRetry;

  static String _sublabel(WatchList list) => !list.isMine
      ? tr('Par {0}', [list.owner.username])
      : list.isShared
          ? tr('Partagée')
          : tr('Privée');

  @override
  Widget build(BuildContext context) {
    final metrics = OnyxMenuMetrics.of(context);
    final lists = this.lists;
    final Widget body;
    if (error != null) {
      body = Flexible(child: ErrorStateView(message: error!, onRetry: onRetry));
    } else if (lists == null) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    } else {
      body = Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(
              horizontal: OnyxMenuMetrics.padding, vertical: 2),
          children: [
            for (final list in lists)
              _row(
                metrics,
                OnyxMenuItem<int>(
                  value: list.id,
                  label: list.displayName,
                  subtitle: _sublabel(list),
                  icon: list.isWatchLater
                      ? (list.contains ? AppIcons.inList : AppIcons.addToList)
                      : list.isShared
                          ? AppIcons.sharedList
                          : AppIcons.privateList,
                  checked: list.contains,
                  enabled: !pending.contains(list.id),
                ),
                () => onToggle(list),
              ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Ajouter à une liste').toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppType.footnote,
                ),
              ),
            ],
          ),
        ),
        body,
        const OnyxMenuHairline(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              OnyxMenuMetrics.padding, 0, OnyxMenuMetrics.padding, 6),
          child: _row(
            metrics,
            OnyxMenuItem<int>(
              value: -1,
              label: tr('Nouvelle liste'),
              icon: AppIcons.add,
            ),
            onCreate,
          ),
        ),
      ],
    );
  }

  Widget _row(
    OnyxMenuMetrics metrics,
    OnyxMenuItem<int> item,
    VoidCallback onSelect,
  ) =>
      OnyxMenuRow(
        item: item,
        height: metrics.rowHeight(item),
        reserveCheck: true,
        onSelect: onSelect,
      );
}
