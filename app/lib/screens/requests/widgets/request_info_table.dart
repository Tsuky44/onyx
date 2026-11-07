import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/media_request.dart';
import '../../../theme/app_icons.dart';
import '../../../utils/format.dart';
import '../../../widgets/global/detail_info_table.dart';

/// La colonne d'informations d'une fiche de demande, présentée sous la forme
/// du cartel moderne partagé avec MediaHub : nature, langue et pays, créateurs,
/// métriques clés (budget, recettes, saisons, durée), équipe et mots-clés.
class RequestInfoTable extends StatelessWidget {
  final RequestMediaDetails details;

  const RequestInfoTable({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final isTv = details.mediaType == RequestMediaType.tv;
    final title = details.title;
    final original = details.originalTitle;
    final date = details.releaseDate;
    final language = details.originalLanguage;
    final country =
        details.countries.isNotEmpty ? details.countries.first : null;
    final director = details.director;
    final writers = details.writers;
    final editors = details.editors;
    final seasons = details.numberOfSeasons ?? 0;
    final episodes = details.numberOfEpisodes ?? 0;
    final studios = details.studios;
    final rating = details.rating;
    final budget = details.budget;
    final revenue = details.revenue;

    final kindParts = [
      isTv ? tr('SÉRIE TÉLÉVISÉE') : tr('FILM'),
      if (language != null && language.isNotEmpty)
        formatLanguage(language).toUpperCase(),
      if (country != null && country.isNotEmpty)
        formatCountry(country).toUpperCase(),
    ];
    final kind = kindParts.join(' · ');

    String? byline;
    if (director != null && director.isNotEmpty) {
      byline = isTv
          ? '${tr('Créée par')} $director'
          : '${tr('Réalisé par')} $director';
    }

    final facts = <CartelFact>[
      if (date != null && date.isNotEmpty)
        CartelFact(
          icon: AppIcons.calendar,
          label: isTv ? tr('Première diffusion') : tr('Sortie'),
          value: detailDateLabel(date),
        ),
      if (!isTv && (details.runtime ?? 0) > 0)
        CartelFact(
          icon: AppIcons.schedule,
          label: tr('Durée'),
          value: formatDuration((details.runtime ?? 0) * 60),
        ),
      if (isTv && seasons > 0)
        CartelFact(
          icon: AppIcons.collection,
          label: tr('Saisons'),
          value:
              '$seasons saison${seasons > 1 ? 's' : ''}${episodes > 0 ? ', $episodes épisodes' : ''}',
        ),
      if (rating > 0)
        CartelFact(
          icon: AppIcons.rating,
          label: tr('Note TMDB'),
          value: '${(rating * 10).round()}%',
        ),
      if (budget != null && budget > 0)
        CartelFact(
          icon: AppIcons.info,
          label: tr('Budget'),
          value: formatMoney(budget),
        ),
      if (revenue != null && revenue > 0)
        CartelFact(
          icon: AppIcons.info,
          label: tr('Recettes'),
          value: formatMoney(revenue),
        ),
    ];

    final rows = <DetailInfoRow>[
      if (original != null && original.isNotEmpty && original != title)
        (label: tr('Titre original'), value: original),
      if (isTv && director != null && director.isNotEmpty)
        (label: tr('Réalisation'), value: director),
      if (writers.isNotEmpty)
        (label: tr('Scénario'), value: writers.join(', ')),
      if (editors.isNotEmpty)
        (label: tr('Montage'), value: editors.join(', ')),
      if (details.tmdbStatus != null &&
          details.tmdbStatus!.isNotEmpty &&
          details.tmdbStatus != 'unknown')
        (label: tr('Statut'), value: detailStatusLabel(details.tmdbStatus!)),
    ];

    return DetailInfoTable(
      rating: rating,
      rows: rows,
      studios: studios,
      kind: kind,
      title: title,
      byline: byline,
      facts: facts,
      keywords: details.keywords,
    );
  }
}
