import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/calendar.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/nav/tv_focusable.dart';
import '../../tv/nav/tv_region.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import '../calendar/widgets/calendar_shared.dart';

/// Rangée « Cette semaine » posée sur l'accueil juste sous « Reprendre la
/// lecture » (point d'entrée 1 de la maquette). Masquée s'il n'y a aucune
/// sortie dans les 7 prochains jours.
class HomeCalendarRow extends StatelessWidget {
  const HomeCalendarRow({super.key});

  @override
  Widget build(BuildContext context) {
    final calendar = Provider.of<CalendarProvider?>(context);
    if (calendar == null) return const SizedBox.shrink();

    final items = calendar.thisWeekEntries;
    if (items.isEmpty) return const SizedBox.shrink();

    final pad = AppLayout.pagePadding(context);
    final compact = AppLayout.isCompact(context);
    final isTv = TvScope.of(context);
    final cardWidth = AppLayout.mediaRowCardWidth(context);
    final gap = AppLayout.mediaRowGap(context);
    final posterHeight = cardWidth / AppLayout.posterOnlyAspectRatio;
    final rowHeight = posterHeight + 36;

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Cette semaine'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: isTv ? FontWeight.w700 : FontWeight.w600,
                          fontSize: isTv
                              ? AppType.title1
                              : (compact ? AppType.headline : AppType.title3),
                          letterSpacing: -0.3,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () => calendar.openCalendar(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr('Tout voir'),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        AppIcons.chevronRight,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TvRegion.rail(
            id: 'home/this-week',
            child: SizedBox(
              height: rowHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                scrollCacheExtent: AppLayout.imageCacheExtent(context),
                padding: EdgeInsets.symmetric(horizontal: pad),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final entry = items[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == items.length - 1 ? 0 : gap,
                    ),
                    child: _HomeCalendarCard(
                      entry: entry,
                      today: calendar.today,
                      width: cardWidth,
                      isFirst: index == 0,
                      onTap: () => calendar.openCalendar(date: entry.date),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCalendarCard extends StatelessWidget {
  const _HomeCalendarCard({
    required this.entry,
    required this.today,
    required this.width,
    required this.isFirst,
    required this.onTap,
  });

  final CalendarEntry entry;
  final DateTime today;
  final double width;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isToday = entry.date == today;
    final dayLabel = CalendarFormat.shortDayLabel(entry, today);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w700,
              color: isToday ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TvFocusable(
            entry: isFirst,
            focusScale: 1.04,
            borderRadius: BorderRadius.circular(10),
            onSelect: onTap,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: CalendarPoster(
                title: entry.title,
                hue: entry.hue,
                posterUrl: entry.posterUrl,
                aspectRatio: AppLayout.posterOnlyAspectRatio,
                showTitleOverlay: true,
                showPlayBadge: entry.ready,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
