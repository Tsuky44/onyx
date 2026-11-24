// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/media_request.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../utils/format.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';
import '../../../widgets/global/media_poster.dart';
import '../../../widgets/global/progress_pill.dart';
import '../../../widgets/global/unavailable_badge.dart';
import '../../../widgets/global/watch_badge.dart';
import '../../../providers/library_provider.dart';
import '../search_layout.dart';

/// Un titre trouvé par la recherche du téléphone : la vignette de l'affiche,
/// le titre, l'année et le type, et ce qu'on en a vu (ADR-0145).
///
/// Une ligne plutôt qu'une affiche : la grille de trois colonnes, sans titre
/// sous les affiches, laissait deviner quel « Dune » était lequel, et le
/// clavier n'en laissait voir qu'une rangée. Une ligne se lit d'un coup
/// d'œil, et cinq tiennent au-dessus du clavier.
class PhoneSearchRow extends StatefulWidget {
  const PhoneSearchRow({
    super.key,
    required this.hit,
    required this.onOpen,
    this.horizontalPadding = 16,
  });

  final SearchHit hit;

  /// Toucher la ligne. Reçoit le contexte de la vignette : la fiche s'ouvre
  /// par l'envol de l'affiche depuis elle (`pushDetailFlight`).
  final ValueChanged<BuildContext> onOpen;

  final double horizontalPadding;

  /// La vignette, au ratio 2:3 des affiches.
  static const double thumbWidth = 52;
  static const double thumbHeight = 78;
  static const double thumbRadius = 8;

  @override
  State<PhoneSearchRow> createState() => _PhoneSearchRowState();
}

class _PhoneSearchRowState extends State<PhoneSearchRow> {
  /// La vignette : la fiche s'ouvre par l'envol de l'affiche depuis elle,
  /// que le doigt ait touché l'image ou le texte.
  final GlobalKey _thumbKey = GlobalKey();

  SearchHit get hit => widget.hit;

  void _open() => widget.onOpen(_thumbKey.currentContext ?? context);

  @override
  Widget build(BuildContext context) {
    final (title, facts, trailing, progress) = switch (hit) {
      LibraryHit(:final media) => _libraryParts(context, media),
      UnavailableHit(:final item) => (
          item.title,
          _facts(item.year, item.mediaType == RequestMediaType.tv),
          UnavailableBadge(
            requested: item.status != RequestMediaStatus.unknown,
          ) as Widget?,
          null as double?,
        ),
    };

    return InkWell(
      onTap: _open,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.horizontalPadding,
          vertical: 6,
        ),
        child: Row(
          children: [
            KeyedSubtree(key: _thumbKey, child: _thumb(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.callout,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    facts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: AppType.subhead,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 96,
                      child: ProgressPill(value: progress),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  (String, String, Widget?, double?) _libraryParts(
    BuildContext context,
    Media media,
  ) {
    final library = context.watch<LibraryProvider>();
    final isMovie = media.type == MediaType.movie;
    final item = isMovie ? library.movieItemFor(media.id) : null;
    final watched = item?.isFinished ?? false;
    final progress = isMovie ? library.movieProgressFor(media.id) : null;
    final inProgress = progress != null && progress > 0 && progress < 0.99;
    return (
      media.title,
      _facts(extractYear(media.releaseDate), media.type == MediaType.show),
      WatchBadge.forMedia(media, watched: watched),
      inProgress ? progress : null,
    );
  }

  /// « 2021  ·  Film » : l'année quand on la connaît, puis le type.
  static String _facts(String? year, bool isShow) => [
        if (year != null && year.isNotEmpty) year,
        isShow ? tr('Série') : tr('Film'),
      ].join('  ·  ');

  Widget _thumb(BuildContext context) {
    return switch (hit) {
      LibraryHit(:final media) => MediaPoster(
          media: media,
          width: PhoneSearchRow.thumbWidth,
          height: PhoneSearchRow.thumbHeight,
          borderRadius: PhoneSearchRow.thumbRadius,
        ),
      UnavailableHit(:final item) => ClipRRect(
          borderRadius: BorderRadius.circular(PhoneSearchRow.thumbRadius),
          child: SizedBox(
            width: PhoneSearchRow.thumbWidth,
            height: PhoneSearchRow.thumbHeight,
            child: AppNetworkImage(
              url: cardPosterUrl(item.posterUrl),
              width: PhoneSearchRow.thumbWidth,
              height: PhoneSearchRow.thumbHeight,
              fadeInDuration: AppMotion.standard,
              // Le voile des titres absents, comme leurs affiches ailleurs
              // (ADR-0129).
              color: AppColors.unavailableTint,
              colorBlendMode: BlendMode.darken,
              placeholder: const ColoredBox(color: AppColors.surfaceElevated),
              errorWidget: const ColoredBox(
                color: AppColors.surfaceElevated,
                child: Icon(
                  AppIcons.movie,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
    };
  }
}
