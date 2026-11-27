import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/calendar.dart';
import '../../../providers/calendar_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/empty_state.dart';
import '../../../widgets/global/sliver_scroll_end.dart';
import 'calendar_shared.dart';
import 'followed_shows_sheet.dart';

/// Proposition A · Agenda : liste continue groupée par jour, conçue pour
/// l'écran du téléphone (< 700 px).
class CalendarAgendaView extends StatefulWidget {
  const CalendarAgendaView({
    super.key,
    required this.topInset,
  });

  final double topInset;

  @override
  State<CalendarAgendaView> createState() => _CalendarAgendaViewState();
}

class _CalendarAgendaViewState extends State<CalendarAgendaView> {
  CalendarKindFilter _kind = CalendarKindFilter.all;
  CalendarSourceFilter _source = CalendarSourceFilter.all;

  List<CalendarEntry> _applyFilters(List<CalendarEntry> all) {
    return all.where((entry) {
      if (_kind == CalendarKindFilter.shows &&
          entry.kind != CalendarEntryKind.show) {
        return false;
      }
      return switch (_source) {
        CalendarSourceFilter.all => true,
        CalendarSourceFilter.mine => entry.source == CalendarSource.watching ||
            entry.source == CalendarSource.followed,
        CalendarSourceFilter.request => entry.source == CalendarSource.request,
        CalendarSourceFilter.server => entry.source == CalendarSource.server,
        CalendarSourceFilter.movie => entry.kind == CalendarEntryKind.movie,
      };
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final filtered = _applyFilters(calendar.entries);
    final byDay = <DateTime, List<CalendarEntry>>{};
    for (final entry in filtered) {
      byDay.putIfAbsent(entry.date, () => []).add(entry);
    }
    final days = byDay.keys.toList()..sort();
    final pad = AppLayout.pagePadding(context);

    return CustomScrollView(
      scrollCacheExtent: AppLayout.imageCacheExtent(context),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: widget.topInset)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 6, pad, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('À venir'),
                    style: const TextStyle(
                      fontSize: AppType.title1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                CalendarRoundIconButton(
                  icon: AppIcons.filters,
                  tooltip: tr('Gérer les séries suivies'),
                  onPressed: () => showFollowedShowsManager(context),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: _AgendaKindSegment(
              value: _kind,
              onChanged: (next) => setState(() => _kind = next),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Row(
                children: [
                  for (final (value, label) in [
                    (CalendarSourceFilter.all, tr('Tout')),
                    (CalendarSourceFilter.mine, tr('Mes séries')),
                    (CalendarSourceFilter.request, tr('Demandés')),
                    (CalendarSourceFilter.server, tr('Sur le serveur')),
                    (CalendarSourceFilter.movie, tr('Films')),
                  ]) ...[
                    CalendarChip(
                      label: label,
                      selected: _source == value,
                      onTap: () => setState(() => _source = value),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (days.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateView(
                icon: AppIcons.calendar,
                title: calendar.entries.isEmpty
                    ? tr('Rien de prévu pour l’instant')
                    : tr('Rien de prévu avec ce filtre.'),
                message: calendar.entries.isEmpty
                    ? tr(
                        'Suivez une série depuis sa fiche pour voir ses prochains épisodes ici.',
                      )
                    : '',
              ),
            ),
          )
        else
          for (final day in days) ...[
            SliverToBoxAdapter(
              child: _AgendaDayHeader(
                day: day,
                today: calendar.today,
                padding: pad,
              ),
            ),
            SliverList.builder(
              itemCount: byDay[day]!.length,
              itemBuilder: (context, index) => _AgendaEntryRow(
                entry: byDay[day]![index],
                horizontalPadding: pad,
                onTap: () =>
                    notifyCalendarEntryTap(context, byDay[day]![index]),
              ),
            ),
          ],
        const SliverScrollEnd(),
      ],
    );
  }
}

class _AgendaKindSegment extends StatelessWidget {
  const _AgendaKindSegment({
    required this.value,
    required this.onChanged,
  });

  final CalendarKindFilter value;
  final ValueChanged<CalendarKindFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: tr('Tout'),
            selected: value == CalendarKindFilter.all,
            onTap: () => onChanged(CalendarKindFilter.all),
          ),
          _SegmentButton(
            label: tr('Séries'),
            selected: value == CalendarKindFilter.shows,
            onTap: () => onChanged(CalendarKindFilter.shows),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fade(context, AppMotion.micro),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppType.footnote,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgendaDayHeader extends StatelessWidget {
  const _AgendaDayHeader({
    required this.day,
    required this.today,
    required this.padding,
  });

  final DateTime day;
  final DateTime today;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final n = day.difference(today).inDays;
    final sub = n > 1 && n < 7 ? tr('dans {0} jours', [n]) : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 16, padding, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            CalendarFormat.dayHeader(day, today),
            style: const TextStyle(
              fontSize: AppType.headline,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(width: 8),
            Text(
              sub,
              style: const TextStyle(
                fontSize: AppType.footnote,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgendaEntryRow extends StatelessWidget {
  const _AgendaEntryRow({
    required this.entry,
    required this.horizontalPadding,
    required this.onTap,
  });

  final CalendarEntry entry;
  final double horizontalPadding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = entry.timeLabel != null
        ? '${entry.subtitle} · ${entry.timeLabel}'
        : entry.subtitle;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 6,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: CalendarPoster(
                title: entry.title,
                hue: entry.hue,
                posterUrl: entry.posterUrl,
                aspectRatio: 16 / 9,
                showPlayBadge: entry.ready,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppType.callout,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppType.footnote,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CalendarSourcePill(
                        source: entry.source,
                        ready: entry.ready,
                      ),
                      if (!entry.ready)
                        Text(
                          CalendarFormat.whyLabel(entry.source),
                          style: const TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
