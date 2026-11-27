import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/calendar.dart';
import '../../../providers/calendar_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/empty_state.dart';
import '../../../widgets/global/onyx_toast.dart';
import 'calendar_shared.dart';

/// Ouvre le panneau « Gérer les séries suivies » en feuille sur mobile ou en
/// dialogue centré sur bureau/tablette.
Future<void> showFollowedShowsManager(BuildContext context) {
  final compact = AppLayout.isCompact(context);
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FollowedShowsContent(isSheet: true),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: const _FollowedShowsContent(isSheet: false),
      ),
    ),
  );
}

class _FollowedShowsContent extends StatelessWidget {
  const _FollowedShowsContent({required this.isSheet});

  final bool isSheet;

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final shows = calendar.followedShows;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, isSheet ? 4 : 20, 20, 20),
        child: Column(
          mainAxisSize: isSheet ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Séries suivies'),
                    style: const TextStyle(
                      fontSize: AppType.title2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (!isSheet)
                  IconButton(
                    tooltip: tr('Fermer'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      AppIcons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr('Retirez une série pour masquer ses sorties du calendrier.'),
              style: const TextStyle(
                fontSize: AppType.subhead,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (shows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: EmptyStateView(
                  icon: AppIcons.calendar,
                  title: tr('Aucune série suivie'),
                  message: tr(
                    'Suivez une série depuis sa fiche pour voir ses prochains épisodes ici.',
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: isSheet,
                  scrollCacheExtent: AppLayout.imageCacheExtent(context),
                  itemCount: shows.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: AppColors.border.withValues(alpha: 0.6),
                  ),
                  itemBuilder: (context, index) => _FollowedShowTile(
                    show: shows[index],
                    onRemove: () {
                      calendar.unfollowById(shows[index].id);
                      showOnyxToast(context, tr('Retirée du calendrier'));
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FollowedShowTile extends StatelessWidget {
  const _FollowedShowTile({
    required this.show,
    required this.onRemove,
  });

  final CalendarFollowedShow show;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: CalendarPoster(
              title: show.title,
              hue: show.hue,
              borderRadius: 6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  show.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppType.callout,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    CalendarSourcePill(source: show.source),
                    if (show.nextSummary != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        show.nextSummary!,
                        style: const TextStyle(
                          fontSize: AppType.footnote,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRemove,
            child: Text(
              tr('Ne plus suivre'),
              style: const TextStyle(
                fontSize: AppType.footnote,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
