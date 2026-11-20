import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../navigation/play_link.dart';
import '../../../models/media.dart' show MediaType;
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/poster_url.dart';
import '../../player/widgets/onyx/onyx_capsule_button.dart';
import 'list_progress.dart';
import 'watch_list_tile.dart' show watchListCaption;

/// « À regarder plus tard » en grand, en tête de la vue large (ADR-0070,
/// ADR-0159) : un éventail de ses affiches, où elle en est, et le prochain
/// titre à lancer.
class WatchLaterHero extends StatelessWidget {
  const WatchLaterHero({
    super.key,
    required this.list,
    required this.onOpen,
    required this.onPlayed,
  });

  final WatchList list;
  final VoidCallback onOpen;

  /// La lecture est revenue : la progression a pu changer.
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WatchListPosterFan(
                urls: watchListPosterUrls(context, list, max: 4)),
            const SizedBox(width: 28),
            Expanded(child: _Summary(list: list, onOpen: onOpen)),
            const SizedBox(width: 24),
            const VerticalDivider(width: 1, color: AppColors.border),
            const SizedBox(width: 24),
            SizedBox(
              width: 280,
              child: _NextUp(list: list, onPlayed: onPlayed),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.list, required this.onOpen});

  final WatchList list;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final watched = list.watchedCount;
    final toRequest = list.toRequestCount;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(AppIcons.inList, size: 22, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                list.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppType.title2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (list.hasProgress && list.itemCount > 0) ...[
          WatchListProgressBar(value: list.watchedFraction, height: 6),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: AppType.subhead),
              children: [
                TextSpan(text: watchedOfText(watched!, list.itemCount)),
                TextSpan(
                    text:
                        ' · ${tr('{0} sur le serveur', [list.onServerCount])}'),
                if (toRequest > 0)
                  TextSpan(
                    text: ' · ${toRequestText(toRequest)}',
                    style: const TextStyle(color: AppColors.warning),
                  ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ] else
          Text(
            list.itemCount == 0 ? tr('Aucun titre') : watchListCaption(list),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: AppType.subhead),
          ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: OnyxCapsuleButton(
            label: tr('Ouvrir la liste'),
            onPressed: onOpen,
          ),
        ),
      ],
    );
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({required this.list, required this.onPlayed});

  final WatchList list;
  final VoidCallback onPlayed;

  Future<void> _play(BuildContext context, WatchListNext next) async {
    final navigator = Navigator.of(context);
    // La fiche lance la lecture : le film à sa position, la série à
    // l'épisode à reprendre (PlayLink, ADR-0091).
    await navigator.push(PlayLink.routeFor(
      next.mediaType == WatchListMediaType.show
          ? MediaType.show
          : MediaType.movie,
      next.mediaId,
    ));
    onPlayed();
  }

  @override
  Widget build(BuildContext context) {
    final next = list.nextItem;
    final baseUrl = context.read<ApiClient>().baseUrl;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Prochain à regarder'),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        if (next == null)
          Text(
            list.hasProgress && (list.onServerCount ?? 0) > 0
                ? tr('Tout ce que le serveur a de cette liste est vu.')
                : tr('Rien à lancer pour l’instant.'),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: AppType.subhead),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: WatchListPoster(
                  url: cardPosterUrl(next.posterUrl, serverBaseUrl: baseUrl),
                  width: 56,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppType.callout,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (next.year != null) next.year!,
                        next.mediaType == WatchListMediaType.show
                            ? tr('Série')
                            : tr('Film'),
                      ].join(' · '),
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: AppType.footnote),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OnyxCapsuleButton(
              label: tr('Lire'),
              icon: AppIcons.play,
              primary: true,
              onPressed: () => _play(context, next),
            ),
          ),
        ],
      ],
    );
  }
}
