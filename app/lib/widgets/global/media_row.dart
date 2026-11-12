import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';
import '../../tv/nav/tv_region.dart';
import '../../utils/responsive.dart';
import 'continue_watching_card.dart';
import 'media_card.dart';
import 'poster_card.dart';
import 'poster_launch_route.dart';
import '../../theme/app_icons.dart';
import '../../l10n/tr.dart';

class MediaRow extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  final VoidCallback? onSeeAll;

  /// Sans lui, une affiche ouvre sa fiche par l'envol ([MediaCard.onTap]).
  final void Function(dynamic item)? onItemTap;

  /// Lecture depuis « Reprendre ». Sans elle, la carte retombe sur [onItemTap].
  final void Function(HomeMediaItem item, LaunchOrigin? origin)?
      onContinueWatchingPlay;
  final void Function(HomeMediaItem item, LaunchOrigin? origin)?
      onContinueWatchingTitleTap;
  final Future<void> Function(HomeMediaItem item)?
      onContinueWatchingMarkWatched;
  final Future<void> Function(HomeMediaItem item)? onContinueWatchingRemove;
  final bool isContinueWatching;

  /// Hands the remote's starting position to this row's first card. Set by the
  /// screen on its topmost row, so a television opens on the content rather
  /// than on whichever header control the traversal policy sorts first.
  final bool autofocusFirstItem;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.onItemTap,
    this.onContinueWatchingPlay,
    this.onContinueWatchingTitleTap,
    this.onContinueWatchingMarkWatched,
    this.onContinueWatchingRemove,
    this.onSeeAll,
    this.isContinueWatching = false,
    this.autofocusFirstItem = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final horizontalPadding = AppLayout.pagePadding(context);
    final cardWidth = AppLayout.mediaRowCardWidth(context);
    final compact = AppLayout.isCompact(context);
    final isTv = TvScope.of(context);
    final gap = AppLayout.mediaRowGap(context);
    final room = PosterCard.railRoom(context);
    final rowHeight = (isContinueWatching
            ? ContinueWatchingCard.rowHeight
            : cardWidth / AppLayout.posterOnlyAspectRatio) +
        room.vertical;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  // Sur téléviseur, un cran au-dessus : le titre d'une
                  // rangée se lit du canapé (ADR-0118).
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: isTv ? FontWeight.w700 : FontWeight.w600,
                        fontSize: isTv ? AppType.title1 : (compact ? 17 : 20),
                        letterSpacing: -0.3,
                      ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr('Tout voir'),
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      SizedBox(width: 2),
                      Icon(AppIcons.chevronRight,
                          size: 20, color: AppColors.textSecondary),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // La marge réservée au zoom des affiches ([PosterCard.railRoom]) est
        // reprise ici, pour que l'écart visible sous le titre ne change pas —
        // sauf sur téléviseur, où elle le dépasse.
        SizedBox(height: (14 - room.top).clamp(0, 14).toDouble()),
        // On entre dans cette rangée par sa première carte, d'où que l'on
        // vienne (ADR-0113). Le titre la nomme : l'accueil n'a pas deux
        // rangées du même nom, et la mémoire la retrouve après un
        // rechargement.
        TvRegion.rail(
          id: 'home/$title',
          child: SizedBox(
            height: rowHeight,
            child: ListView.builder(
              // Borné à un écran de part et d'autre (la valeur d'`AppLayout`,
              // qui précharge les affiches) : chaque flèche de dpad parcourt
              // toutes les cartes construites (constat C5, 1,7 à 4,3 ms au
              // simulateur jusqu'à 120 cartes).
              scrollCacheExtent: AppLayout.imageCacheExtent(context),
              scrollDirection: Axis.horizontal,
              // Sur téléviseur, l'ombre de l'affiche soulevée déborde de la
              // rangée : découpée à son bord, elle s'arrêtait net.
              clipBehavior: isTv ? Clip.none : Clip.hardEdge,
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: room.top,
                bottom: room.bottom,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  // Une carte, un média (constat C7) : voir [TvRegion.itemKey].
                  key: TvRegion.itemKey(context, _mediaIdOf(item)),
                  padding: EdgeInsets.only(
                      right: index < items.length - 1 ? gap : 0),
                  child: isContinueWatching
                      ? ContinueWatchingCard(
                          item: item as HomeMediaItem,
                          autofocus: autofocusFirstItem && index == 0,
                          onTap: (origin) => onContinueWatchingPlay != null
                              ? onContinueWatchingPlay!(item, origin)
                              : onItemTap?.call(item),
                          onTitleTap: onContinueWatchingTitleTap != null
                              ? (origin) =>
                                  onContinueWatchingTitleTap!(item, origin)
                              : null,
                          onMarkAsWatched: onContinueWatchingMarkWatched,
                          onRemoveFromRow: onContinueWatchingRemove,
                        )
                      : SizedBox(
                          width: cardWidth,
                          child: MediaCard(
                            media: item as Media,
                            compact: true,
                            autofocus: autofocusFirstItem && index == 0,
                            onTap: onItemTap == null
                                ? null
                                : () => onItemTap!(item),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// L'identifiant du média d'une carte, qu'elle soit à reprendre ou non.
  static int _mediaIdOf(dynamic item) =>
      item is HomeMediaItem ? item.media.id : (item as Media).id;
}
