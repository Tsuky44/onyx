import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Ce que le bandeau d'accueil montre d'une série (ADR-0154) : l'épisode que
/// son bouton de lecture lance, et des images d'épisodes pour le fond qui
/// défile.
@immutable
class HeroSeriesPreview {
  const HeroSeriesPreview({this.next, this.stills = const []});

  /// L'épisode à reprendre, ou le suivant à voir : celui que lance aussi la
  /// fiche de la série. Nul quand le serveur n'a rien à lire.
  final HomeMediaItem? next;

  /// Des épisodes de la saison de [next], jusqu'à lui compris, qui ont une
  /// image ([pickHeroStills]).
  final List<HomeMediaItem> stills;
}

bool _hasStill(HomeMediaItem episode) =>
    episode.media.posterUrl?.trim().isNotEmpty == true;

/// Au plus [max] épisodes dont l'image passera derrière le bandeau : ceux de
/// la saison de [next] jusqu'à lui compris, répartis sur la saison, [next] en
/// dernier.
///
/// Jamais un épisode d'après [next] : le fond défile sous les yeux de
/// quelqu'un qui n'a pas encore vu la suite, et une image en dit parfois plus
/// que le résumé.
List<HomeMediaItem> pickHeroStills(
  List<HomeMediaItem> episodes,
  HomeMediaItem next, {
  int max = 3,
}) {
  final season = next.media.effectiveSeasonNumber;
  final last = next.media.effectiveEpisodeNumber;
  if (last == null || last <= 0 || max <= 0) return const [];
  final candidates = [
    for (final episode in episodes)
      if (_hasStill(episode) &&
          episode.media.effectiveSeasonNumber == season &&
          (episode.media.effectiveEpisodeNumber ?? 0) > 0 &&
          episode.media.effectiveEpisodeNumber! <= last)
        episode,
  ]..sort((a, b) => a.media.effectiveEpisodeNumber!
      .compareTo(b.media.effectiveEpisodeNumber!));
  if (candidates.length <= max) return candidates;
  if (max == 1) return [candidates.last];
  // Plus d'épisodes que de places : un écart régulier, du premier au dernier.
  // Avec plus de candidats que de places, le pas dépasse 1 et les rangs
  // arrondis restent distincts.
  return [
    for (var i = 0; i < max; i++)
      candidates[(i * (candidates.length - 1) / (max - 1)).round()],
  ];
}

class _Entry {
  _Entry(this.preview) : at = DateTime.now();
  final HeroSeriesPreview preview;
  final DateTime at;
}

/// Les aperçus de séries du bandeau, gardés le temps d'une visite de l'accueil.
///
/// Le bandeau se reconstruit à chaque tour du carrousel : sans mémoire, chaque
/// passage redemandait l'épisode à reprendre et la liste de sa saison. Une
/// réponse sert dix minutes au plus, et l'accueil oublie tout au retour du
/// lecteur ([clear]) : l'épisode à suivre vient de changer.
abstract final class HeroSeriesPreviewCache {
  static const Duration maxAge = Duration(minutes: 10);

  static final Map<String, _Entry> _entries = {};
  static final Map<String, Future<HeroSeriesPreview>> _pending = {};

  /// Monte à chaque [clear] : une réponse partie avant n'est pas gardée.
  static int _generation = 0;

  /// [known] est l'épisode d'une diapositive de « Reprendre » : il est déjà
  /// l'épisode à lancer, et seule la liste de sa saison manque.
  static String _key(int showId, HomeMediaItem? known) =>
      '$showId:${known?.media.id ?? 0}';

  /// L'aperçu déjà connu de [showId], s'il n'a pas vieilli.
  static HeroSeriesPreview? peek(int showId, {HomeMediaItem? known}) {
    final entry = _entries[_key(showId, known)];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > maxAge) return null;
    return entry.preview;
  }

  /// L'aperçu de [showId] ; deux bandeaux qui le demandent ensemble partagent
  /// la même requête.
  static Future<HeroSeriesPreview> load(
    ApiClient api,
    int showId, {
    HomeMediaItem? known,
  }) {
    final cached = peek(showId, known: known);
    if (cached != null) return Future.value(cached);
    final key = _key(showId, known);
    final pending = _pending[key];
    if (pending != null) return pending;
    final generation = _generation;
    final request = _fetch(api, showId, known).then((preview) {
      if (generation == _generation) _entries[key] = _Entry(preview);
      return preview;
    });
    // Un bloc, pas une flèche : `remove` rend la requête elle-même, et
    // `whenComplete` attendait alors sa propre fin.
    return _pending[key] = request.whenComplete(() {
      _pending.remove(key);
    });
  }

  static Future<HeroSeriesPreview> _fetch(
    ApiClient api,
    int showId,
    HomeMediaItem? known,
  ) async {
    var next = known;
    if (next == null) {
      final resume = await api.getShowResumeEpisode(showId);
      next = resume.hasEpisode ? resume.episode : null;
    }
    if (next == null) return const HeroSeriesPreview();
    final season = next.media.effectiveSeasonNumber;
    if (season == null || season < 0) return HeroSeriesPreview(next: next);
    try {
      final episodes = await api.getShowSeasonEpisodes(showId, season);
      return HeroSeriesPreview(
        next: next,
        stills: pickHeroStills(episodes, next),
      );
    } catch (e) {
      // Sans la liste de la saison, le fond reste sur l'image de la série :
      // l'épisode à lancer, lui, est connu et le bouton le dit.
      debugPrint('HeroSeriesPreviewCache: saison $season de $showId: $e');
      return HeroSeriesPreview(next: next);
    }
  }

  /// Oublie tout : après une lecture, l'épisode à suivre a changé.
  static void clear() {
    _generation++;
    _entries.clear();
  }

  @visibleForTesting
  static void reset() {
    clear();
    _pending.clear();
  }
}
