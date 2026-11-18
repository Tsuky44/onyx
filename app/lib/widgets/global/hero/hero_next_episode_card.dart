import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/format.dart';
import '../../../utils/poster_url.dart';
import '../app_network_image.dart';
import '../detail_actions.dart';
import '../liquid_glass.dart';
import '../progress_pill.dart';

/// « S2 E4 · Le phare » : un épisode tel que la carte « À suivre » et la
/// légende du fond vivant le nomment.
String heroEpisodeTitle(HomeMediaItem episode) {
  final title = episode.episodeTitle?.trim();
  final name = title != null && title.isNotEmpty ? title : episode.media.title;
  final code = episodeShortCode(episode.media);
  return code == null ? name : '$code · $name';
}

/// Ce que la carte « À suivre » dit de l'épisode que le bandeau lance.
@immutable
class HeroEpisodeSummary {
  const HeroEpisodeSummary({
    required this.kicker,
    required this.title,
    this.detail,
    this.progress,
  });

  /// « À suivre », « Nouvel épisode » ou « Premier épisode ».
  final String kicker;

  /// « S2 E4 · Le phare ».
  final String title;

  /// Le temps restant d'un épisode commencé, sa durée sinon.
  final String? detail;

  /// La part vue, pour un épisode commencé.
  final double? progress;

  factory HeroEpisodeSummary.of(HomeMediaItem episode) {
    final started = episode.currentPositionSeconds > 0 && !episode.isFinished;
    final media = episode.media;
    final first =
        media.effectiveSeasonNumber == 1 && media.effectiveEpisodeNumber == 1;
    final kicker = episode.hasNewEpisode
        ? tr('Nouvel épisode')
        : first && !started
            ? tr('Premier épisode')
            : tr('À suivre');
    final duration = episode.effectiveDuration;
    final detail = started
        ? formatRemaining(duration - episode.currentPositionSeconds)
        : formatDuration(duration);
    return HeroEpisodeSummary(
      kicker: kicker,
      title: heroEpisodeTitle(episode),
      detail: detail == null || detail.isEmpty ? null : detail,
      progress: started ? episode.percentWatched : null,
    );
  }
}

/// La carte « À suivre » du bandeau d'une série, sur grand écran
/// (ADR-0154) : l'image de l'épisode que le bouton de lecture lance, où l'on
/// en est, et son nom. La toucher lance l'épisode, comme le bouton.
///
/// Absente du téléphone : sous le texte et les boutons, elle chargeait trop
/// le bas de l'écran.
class HeroNextEpisodeCard extends StatelessWidget {
  const HeroNextEpisodeCard({
    super.key,
    required this.episode,
    required this.onTap,
  });

  static const double width = 304;
  static const double _padding = 10;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(20));

  final HomeMediaItem episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final api = Provider.of<ApiClient>(context, listen: false);
    final summary = HeroEpisodeSummary.of(episode);
    // La même adresse que le fond du bandeau : l'image se télécharge une fois.
    final still = resolveHeroImageUrl(episode.media.posterUrl,
        serverBaseUrl: api.baseUrl);
    return SizedBox(
      width: width,
      child: LiquidGlass(
        borderRadius: _radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: _radius,
            child: Padding(
              padding: const EdgeInsets.all(_padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (still != null)
                            AppNetworkImage(
                              url: still,
                              fit: BoxFit.cover,
                              decodeWidth: width - 2 * _padding,
                              placeholder: const ColoredBox(
                                  color: AppColors.surfaceElevated),
                              errorWidget: const ColoredBox(
                                  color: AppColors.surfaceElevated),
                            )
                          else
                            const ColoredBox(color: AppColors.surfaceElevated),
                          const Center(child: _PlayDisc()),
                          if (summary.progress != null)
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 10,
                              child: ProgressPill(value: summary.progress!),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.kicker.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppType.callout,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (summary.detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            summary.detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: AppType.subhead,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayDisc extends StatelessWidget {
  const _PlayDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.background.withValues(alpha: 0.45),
      ),
      child: const Icon(AppIcons.play, color: AppColors.textPrimary, size: 20),
    );
  }
}
