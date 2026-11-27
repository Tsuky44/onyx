import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/calendar.dart';
import '../../../providers/calendar_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../tv/nav/tv_focusable.dart';
import '../../../tv/nav/tv_region.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/detail_hero.dart';
import '../../../widgets/global/empty_state.dart';
import '../../../widgets/global/sliver_scroll_end.dart';
import 'calendar_shared.dart';

/// Proposition D · Affiche : la prochaine sortie en grand format hero avec
/// compte à rebours géant, suivie de rangées horizontales d'affiches par
/// période. Conçue pour la TV et le pilotage à la télécommande.
class CalendarDisplayView extends StatelessWidget {
  const CalendarDisplayView({
    super.key,
    required this.topInset,
  });

  final double topInset;

  CalendarEntry? _pickHero(List<CalendarEntry> entries) {
    if (entries.isEmpty) return null;
    for (final entry in entries) {
      if (entry.source == CalendarSource.request &&
          entry.kind == CalendarEntryKind.show) {
        return entry;
      }
    }
    return entries.first;
  }

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final entries = calendar.entries;
    final today = calendar.today;
    final hero = _pickHero(entries);

    if (hero == null) {
      return Padding(
        padding: EdgeInsets.only(top: topInset),
        child: EmptyStateView(
          icon: AppIcons.calendar,
          title: tr('Rien de prévu pour l’instant'),
          message: tr(
            'Suivez une série depuis sa fiche pour voir ses prochains épisodes ici.',
          ),
        ),
      );
    }

    final thisWeek = entries.where((e) {
      final d = e.date.difference(today).inDays;
      return d >= 0 && d < 7;
    }).toList(growable: false);

    final nextWeek = entries.where((e) {
      final d = e.date.difference(today).inDays;
      return d >= 7 && d < 14;
    }).toList(growable: false);

    final later = entries.where((e) {
      final d = e.date.difference(today).inDays;
      return d >= 14;
    }).toList(growable: false);

    final pad = AppLayout.pagePadding(context);

    return TvRegion.sections(
      child: CustomScrollView(
        scrollCacheExtent: AppLayout.imageCacheExtent(context),
        slivers: [
          SliverToBoxAdapter(
            child: TvRegion.section(
              id: 'calendar-hero',
              child: _DisplayHero(
                entry: hero,
                today: today,
                topInset: topInset,
                horizontalPadding: pad,
              ),
            ),
          ),
          if (thisWeek.isNotEmpty)
            SliverToBoxAdapter(
              child: _DisplayRail(
                id: 'calendar-this-week',
                title: tr('Cette semaine'),
                range: CalendarFormat.rangeLabel(
                  today,
                  today.add(const Duration(days: 6)),
                ),
                entries: thisWeek,
                today: today,
                horizontalPadding: pad,
              ),
            ),
          if (nextWeek.isNotEmpty)
            SliverToBoxAdapter(
              child: _DisplayRail(
                id: 'calendar-next-week',
                title: tr('La semaine prochaine'),
                range: CalendarFormat.rangeLabel(
                  today.add(const Duration(days: 7)),
                  today.add(const Duration(days: 13)),
                ),
                entries: nextWeek,
                today: today,
                horizontalPadding: pad,
              ),
            ),
          if (later.isNotEmpty)
            SliverToBoxAdapter(
              child: _DisplayRail(
                id: 'calendar-later',
                title: tr('Plus tard'),
                range: '',
                entries: later,
                today: today,
                horizontalPadding: pad,
              ),
            ),
          const SliverScrollEnd(),
        ],
      ),
    );
  }
}

class _DisplayHero extends StatelessWidget {
  const _DisplayHero({
    required this.entry,
    required this.today,
    required this.topInset,
    required this.horizontalPadding,
  });

  final CalendarEntry entry;
  final DateTime today;
  final double topInset;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final daysLeft = entry.date.difference(today).inDays;
    final big = daysLeft <= 0 ? tr('Jour J') : tr('J-{0}', [daysLeft]);
    final hue = entry.hue;
    final gradStart = HSLColor.fromAHSL(1, hue % 360, 0.55, 0.34).toColor();
    final gradMid = HSLColor.fromAHSL(1, (hue + 20) % 360, 0.50, 0.12).toColor();
    final sourceLabel = CalendarFormat.sourceLabel(
      entry.source,
      ready: entry.ready,
    );

    return SizedBox(
      height: 360 + topInset * 0.4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.5, -0.4),
                radius: 1.25,
                colors: [gradStart, gradMid, AppColors.background],
                stops: const [0.0, 0.55, 0.9],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.background,
                ],
                stops: const [0.3, 0.96],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.background.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
          Positioned(
            left: horizontalPadding,
            right: horizontalPadding,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Prochaine sortie · {0}', [sourceLabel]).toUpperCase(),
                  style: const TextStyle(
                    fontSize: AppType.footnote,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppType.hero,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.0,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      big,
                      style: const TextStyle(
                        fontSize: AppType.countdown,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -2.0,
                        height: 0.85,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.subtitle,
                            style: const TextStyle(
                              fontSize: AppType.subhead,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 180,
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: Stack(
                                children: [
                                  ColoredBox(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    child: const SizedBox.expand(),
                                  ),
                                  const FractionallySizedBox(
                                    widthFactor: 0.84,
                                    heightFactor: 1,
                                    child: ColoredBox(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    HeroPill(
                      label: entry.ready
                          ? tr('Lecture')
                          : tr('Revoir l’épisode précédent'),
                      icon: AppIcons.play,
                      style: HeroPillStyle.primary,
                      onPressed: () => notifyCalendarEntryTap(context, entry),
                    ),
                    HeroPill(
                      label: tr('Fiche'),
                      style: HeroPillStyle.glass,
                      onPressed: () => notifyCalendarEntryTap(context, entry),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisplayRail extends StatelessWidget {
  const _DisplayRail({
    required this.id,
    required this.title,
    required this.range,
    required this.entries,
    required this.today,
    required this.horizontalPadding,
  });

  final String id;
  final String title;
  final String range;
  final List<CalendarEntry> entries;
  final DateTime today;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppType.headline,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (range.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    range,
                    style: const TextStyle(
                      fontSize: AppType.footnote,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TvRegion.rail(
            id: id,
            child: SizedBox(
              height: 244,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                scrollCacheExtent: AppLayout.imageCacheExtent(context),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == entries.length - 1 ? 0 : 16,
                    ),
                    child: SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            CalendarFormat.shortDayLabel(entry, today),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TvFocusable(
                            entry: index == 0,
                            focusScale: 1.04,
                            borderRadius: BorderRadius.circular(10),
                            onSelect: () =>
                                notifyCalendarEntryTap(context, entry),
                            child: CalendarPoster(
                              title: entry.title,
                              hue: entry.hue,
                              posterUrl: entry.posterUrl,
                              aspectRatio: 2 / 3,
                              showTitleOverlay: true,
                              showPlayBadge: entry.ready,
                            ),
                          ),
                        ],
                      ),
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
