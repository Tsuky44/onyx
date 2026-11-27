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

/// Proposition C · Mois : grille mensuelle avec mini-affiches dans chaque case
/// et détail du jour sélectionné dans un panneau latéral à droite.
class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
    super.key,
    required this.topInset,
  });

  final double topInset;

  List<DateTime> _monthDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday - 1;
    final start = first.subtract(Duration(days: leading));
    final last = DateTime(month.year, month.month + 1, 0);
    final total = leading + last.day;
    final rows = total <= 35 ? 35 : 42;
    return [
      for (var i = 0; i < rows; i++) start.add(Duration(days: i)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final month = calendar.focusedMonth;
    final today = calendar.today;
    final selected = calendar.selectedDate;
    final days = _monthDays(month);
    final pad = AppLayout.pagePadding(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            scrollCacheExtent: AppLayout.imageCacheExtent(context),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topInset + 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, 20, 14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        tr('{0} {1}', [
                          CalendarFormat.monthFull(month.month),
                          month.year,
                        ]),
                        style: const TextStyle(
                          fontSize: AppType.title2,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CalendarChip(
                        label: tr('Semaine'),
                        selected: calendar.desktopMode == CalendarViewMode.week,
                        onTap: () =>
                            calendar.setDesktopMode(CalendarViewMode.week),
                      ),
                      CalendarChip(
                        label: tr('Mois'),
                        selected:
                            calendar.desktopMode == CalendarViewMode.month,
                        onTap: () =>
                            calendar.setDesktopMode(CalendarViewMode.month),
                      ),
                      CalendarRoundIconButton(
                        icon: AppIcons.back,
                        tooltip: tr('Mois précédent'),
                        onPressed: () => calendar.shiftMonth(-1),
                        size: 32,
                        iconSize: 16,
                      ),
                      CalendarRoundIconButton(
                        icon: AppIcons.chevronRight,
                        tooltip: tr('Mois suivant'),
                        onPressed: () => calendar.shiftMonth(1),
                        size: 32,
                        iconSize: 16,
                      ),
                      CalendarRoundIconButton(
                        icon: AppIcons.filters,
                        tooltip: tr('Gérer les séries suivies'),
                        onPressed: () => showFollowedShowsManager(context),
                        size: 32,
                        iconSize: 16,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, 20, 8),
                  child: Row(
                    children: [
                      for (final label in [
                        tr('Lun'),
                        tr('Mar'),
                        tr('Mer'),
                        tr('Jeu'),
                        tr('Ven'),
                        tr('Sam'),
                        tr('Dim'),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              label.toUpperCase(),
                              style: const TextStyle(
                                fontSize: AppType.caption,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, 20, 0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    scrollCacheExtent: AppLayout.imageCacheExtent(context),
                    itemCount: days.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      mainAxisExtent: 82,
                    ),
                    itemBuilder: (context, index) {
                      final day = days[index];
                      return _MonthDayCell(
                        day: day,
                        isOutsideMonth: day.month != month.month,
                        isToday: day == today,
                        isSelected: day == selected,
                        entries: calendar.entriesOn(day),
                        onTap: () => calendar.selectDate(day),
                      );
                    },
                  ),
                ),
              ),
              const SliverScrollEnd(),
            ],
          ),
        ),
        _MonthSidePanel(
          topInset: topInset,
          day: selected,
          today: today,
          entries: calendar.entriesOn(selected),
        ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.isOutsideMonth,
    required this.isToday,
    required this.isSelected,
    required this.entries,
    required this.onTap,
  });

  final DateTime day;
  final bool isOutsideMonth;
  final bool isToday;
  final bool isSelected;
  final List<CalendarEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isOutsideMonth ? 0.35 : 1.0,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? AppColors.focus : Colors.transparent,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.surfaceElevated,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isToday)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: const TextStyle(
                        fontSize: AppType.footnote,
                        fontWeight: FontWeight.w800,
                        color: AppColors.background,
                      ),
                    ),
                  )
                else
                  Text(
                    '${day.day}',
                    style: const TextStyle(
                      fontSize: AppType.footnote,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final entry in entries.take(2)) ...[
                        SizedBox(
                          width: 22,
                          child: CalendarPoster(
                            title: entry.title,
                            hue: entry.hue,
                            posterUrl: entry.posterUrl,
                            borderRadius: 4,
                          ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      if (entries.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '+${entries.length - 2}',
                            style: const TextStyle(
                              fontSize: AppType.micro,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthSidePanel extends StatelessWidget {
  const _MonthSidePanel({
    required this.topInset,
    required this.day,
    required this.today,
    required this.entries,
  });

  final double topInset;
  final DateTime day;
  final DateTime today;
  final List<CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: CustomScrollView(
        scrollCacheExtent: AppLayout.imageCacheExtent(context),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topInset + 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CalendarFormat.relativeInDays(day, today).toUpperCase(),
                    style: const TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CalendarFormat.dayHeader(day, today),
                    style: const TextStyle(
                      fontSize: AppType.callout,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (entries.isEmpty)
                    Text(
                      tr('Rien ce jour-là'),
                      style: const TextStyle(
                        fontSize: AppType.subhead,
                        color: AppColors.textMuted,
                      ),
                    )
                  else
                    for (final entry in entries) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => notifyCalendarEntryTap(context, entry),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 46,
                                child: CalendarPoster(
                                  title: entry.title,
                                  hue: entry.hue,
                                  posterUrl: entry.posterUrl,
                                  borderRadius: 6,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: AppType.subhead,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: AppType.caption,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    CalendarSourcePill(
                                      source: entry.source,
                                      ready: entry.ready,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                ],
              ),
            ),
          ),
          const SliverScrollEnd(),
        ],
      ),
    );
  }
}
