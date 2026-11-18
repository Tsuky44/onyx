import 'package:flutter/material.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../media_countdown.dart';

/// « Prochain épisode le 26 nov. », quand la fiche TMDB d'une série en
/// annonce un à venir : la même règle que le compte à rebours de sa fiche.
String? heroNextAirLabel(MediaDetails? details) {
  if (details == null) return null;
  final countdown = CountdownModel.forShow(
    nextEpisode: details.nextEpisodeToAir,
    lastEpisode: details.lastEpisodeToAir,
    status: details.status,
  );
  if (countdown == null || countdown.kind != CountdownKind.next) return null;
  final day = CountdownModel.parseDay(countdown.target);
  if (day == null) return null;
  return tr('Prochain épisode le {0}', [LocaleFormats.shortDate(day)]);
}

/// Le surtitre du bandeau : « SÉRIE · 3 SAISONS », et la pastille « Nouvel
/// épisode » quand l'épisode à lancer vient de sortir (ADR-0147).
class HeroEyebrow extends StatelessWidget {
  const HeroEyebrow({super.key, required this.text, this.newEpisode = false});

  final String text;
  final bool newEpisode;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: AppType.caption,
        letterSpacing: 1.6,
      ),
    );
    if (!newEpisode) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: label),
        const SizedBox(width: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.16),
            border: Border.all(
                color: AppColors.accentMuted.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 6),
                ),
                const SizedBox(width: 6),
                Text(
                  tr('Nouvel épisode'),
                  style: const TextStyle(
                    color: AppColors.accentMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: AppType.caption,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// La ligne sous le titre : l'année, les genres, la note, puis [trailing]
/// (le prochain épisode d'une série, l'épisode d'une reprise de film).
class HeroMetaLine extends StatelessWidget {
  const HeroMetaLine({
    super.key,
    this.year,
    this.genres = const [],
    this.rating = 0,
    this.trailing,
  });

  final String? year;
  final List<String> genres;

  /// La note TMDB sur 10 ; rien sous 0,1.
  final double rating;
  final String? trailing;

  static const _separator = TextSpan(text: '  ·  ');

  bool get isEmpty =>
      (year == null || year!.isEmpty) &&
      genres.isEmpty &&
      rating < 0.1 &&
      (trailing == null || trailing!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final parts = <InlineSpan>[
      if (year != null && year!.isNotEmpty) TextSpan(text: year),
      if (genres.isNotEmpty) TextSpan(text: genres.take(2).join(', ')),
      if (rating >= 0.1)
        TextSpan(children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(AppIcons.rating, size: 13, color: AppColors.rating),
            ),
          ),
          TextSpan(
            text: LocaleFormats.decimal(rating.toStringAsFixed(1)),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ]),
      if (trailing != null && trailing!.isNotEmpty) TextSpan(text: trailing),
    ];
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) _separator,
          parts[i],
        ],
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: AppType.body,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
