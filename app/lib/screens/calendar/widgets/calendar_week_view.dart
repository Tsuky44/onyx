import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/calendar.dart';
import '../../../providers/calendar_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/sliver_scroll_end.dart';
import 'calendar_shared.dart';
import 'followed_shows_sheet.dart';

/// Proposition B · Semaine : sept colonnes (une par jour) avec les affiches
/// empilées, pensée pour le bureau et la tablette (>= 700 px).
class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({
    super.key,
    required this.topInset,
  });

  final double topInset;

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final start = calendar.weekStart;
    final today = calendar.today;
    final pad = AppLayout.pagePadding(context);
    final isCurrentWeek = start == today;

    return CustomScrollView(
      scrollCacheExtent: AppLayout.imageCacheExtent(context),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: topInset + 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: _WeekHeader(
              title: isCurrentWeek
                  ? tr('Les 7 prochains jours')
                  : CalendarFormat.rangeLabel(
                      start, start.add(const Duration(days: 6))),
              mode: calendar.desktopMode,
              onModeChanged: calendar.setDesktopMode,
              onPrev: () => calendar.shiftWeek(-1),
              onNext: () => calendar.shiftWeek(1),
              onManageFollowed: () => showFollowedShowsManager(context),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _WeekDayColumn(
                        day: start.add(Duration(days: i)),
                        today: today,
                        entries:
                            calendar.entriesOn(start.add(Duration(days: i))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SliverScrollEnd(),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.title,
    required this.mode,
    required this.onModeChanged,
    required this.onPrev,
    required this.onNext,
    required this.onManageFollowed,
  });

  final String title;
  final CalendarViewMode mode;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onManageFollowed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: AppType.title1,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        CalendarChip(
          label: tr('Semaine'),
          selected: mode == CalendarViewMode.week,
          onTap: () => onModeChanged(CalendarViewMode.week),
        ),
        CalendarChip(
          label: tr('Mois'),
          selected: mode == CalendarViewMode.month,
          onTap: () => onModeChanged(CalendarViewMode.month),
        ),
        CalendarRoundIconButton(
          icon: AppIcons.back,
          tooltip: tr('Semaine précédente'),
          onPressed: onPrev,
          size: 32,
          iconSize: 16,
        ),
        CalendarRoundIconButton(
          icon: AppIcons.chevronRight,
          tooltip: tr('Semaine suivante'),
          onPressed: onNext,
          size: 32,
          iconSize: 16,
        ),
        CalendarRoundIconButton(
          icon: AppIcons.filters,
          tooltip: tr('Gérer les séries suivies'),
          onPressed: onManageFollowed,
          size: 32,
          iconSize: 16,
        ),
      ],
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.day,
    required this.today,
    required this.entries,
  });

  final DateTime day;
  final DateTime today;
  final List<CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    final hasItems = entries.isNotEmpty;
    final dayName =
        isToday ? tr('Aujourd’hui') : CalendarFormat.weekdayShort(day.weekday);

    return Container(
      constraints: const BoxConstraints(minHeight: 340),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isToday ? AppColors.surfaceElevated : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? AppColors.focus.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    dayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.footnote,
                      fontWeight: FontWeight.w700,
                      color: hasItems || isToday
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: AppType.title3,
                    fontWeight: FontWeight.w800,
                    color: isToday
                        ? AppColors.textPrimary
                        : (hasItems
                            ? AppColors.textPrimary
                            : AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          if (!hasItems)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text(
                tr('Rien ce jour-là'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppType.caption,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0) const SizedBox(height: 12),
              _WeekEntryCard(entry: entry),
            ],
        ],
      ),
    );
  }
}

class _WeekEntryCard extends StatelessWidget {
  const _WeekEntryCard({required this.entry});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => notifyCalendarEntryTap(context, entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CalendarPoster(
            title: entry.title,
            hue: entry.hue,
            posterUrl: entry.posterUrl,
            aspectRatio: 2 / 3,
            showTitleOverlay: true,
            showPlayBadge: entry.ready,
          ),
          const SizedBox(height: 5),
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppType.footnote,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.shortEpisodeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          CalendarSourcePill(source: entry.source, ready: entry.ready),
        ],
      ),
    );
  }
}
