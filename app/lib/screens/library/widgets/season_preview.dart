import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../utils/format.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/season_hover_preview.dart';
import 'season_tabs.dart';

/// La fiche au survol d'une saison de la bibliothèque. [fallbackPosterUrl] est
/// l'affiche de la série, pour une saison que TMDB n'illustre pas.
SeasonPreviewInfo seasonPreviewInfo(
  Media season, {
  required String? serverBaseUrl,
  String? fallbackPosterUrl,
}) {
  return SeasonPreviewInfo(
    title: seasonLabel(season),
    facts: seasonFacts(season),
    overview: season.overview ?? '',
    posterUrl: cardPosterUrl(
      season.posterUrl?.isNotEmpty == true
          ? season.posterUrl
          : fallbackPosterUrl,
      serverBaseUrl: serverBaseUrl,
    ),
  );
}

/// « 2021 · 10 épisodes · manquante » : ce qu'on sait d'une saison sans
/// l'ouvrir, dans le même ordre sur la fiche au survol et sur sa page.
List<String> seasonFacts(Media season, {int? episodeCount}) {
  final facts = <String>[];
  final year = extractYear(season.releaseDate);
  if (year != null) facts.add(year);
  final count = episodeCount ?? season.episodeCount ?? 0;
  if (count > 0) {
    facts.add(count > 1 ? tr('{0} épisodes', [count]) : tr('1 épisode'));
  }
  if (!season.isAvailable) {
    facts.add(season.isRequested ? tr('demandée') : tr('manquante'));
  }
  return facts;
}
