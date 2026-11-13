import 'package:flutter/material.dart';
import '../../../models/media_request.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../tv/nav/tv_region.dart';
import '../../../widgets/global/season_bubbles.dart';
import '../../../widgets/global/season_hover_preview.dart';
import '../../../l10n/tr.dart';
import 'request_season_panel.dart';
import 'season_frame.dart';

/// Les saisons d'une demande : les bulles ([SeasonBubbleRow]) et un panneau
/// d'épisodes dessous. Toucher une bulle ouvre le panneau de sa saison, une
/// seule à la fois ; retoucher la saison ouverte replie le tout. C'est dans ce
/// panneau, et seulement là, qu'une saison se demande.
///
/// À la souris, laisser le curseur sur une bulle ouvre la fiche de la saison
/// ([SeasonHoverPreview]), comme sur la fiche d'une série de la bibliothèque ;
/// un clic dessus déplie le panneau de la saison.
class RequestSeasonList extends StatefulWidget {
  final int tmdbId;
  final RequestMediaItem showItem;
  final List<RequestSeason> seasons;

  const RequestSeasonList({
    super.key,
    required this.tmdbId,
    required this.showItem,
    required this.seasons,
  });

  @override
  State<RequestSeasonList> createState() => _RequestSeasonListState();
}

class _RequestSeasonListState extends State<RequestSeasonList> {
  int? _selected;

  /// Sens du dernier changement de saison (+1 vers la droite) : le contenu
  /// entrant glisse depuis ce côté.
  double _direction = 1;

  final _frameKey = GlobalKey();

  /// Abscisse, dans le cadre du panneau, du centre de la bulle ouverte.
  final _beamX = ValueNotifier<double?>(null);

  /// Épisodes déjà chargés par numéro de saison : passer d'une saison à
  /// l'autre ne refait pas d'appel réseau.
  final Map<int, List<RequestEpisode>> _cache = {};

  @override
  void dispose() {
    _beamX.dispose();
    super.dispose();
  }

  void _select(int number) {
    final previous = _selected;
    setState(() {
      if (previous != null && previous != number) {
        _direction = number > previous ? 1 : -1;
      }
      _selected = previous == number ? null : number;
    });
  }

  /// Ouvrir depuis la fiche au survol ne replie jamais : la saison déjà ouverte
  /// reste ouverte, contrairement au second toucher sur sa bulle.
  void _open(int number) {
    if (_selected != number) _select(number);
  }

  /// Tout ce que MediaHub attend encore, même en partie : le sablier.
  static bool _isRequested(RequestMediaStatus status) =>
      status == RequestMediaStatus.pending ||
      status == RequestMediaStatus.processing ||
      status == RequestMediaStatus.partial;

  SeasonBubbleEntry _entry(RequestSeason season) {
    final title = seasonTitle(season);
    final count = tr('{0} épisodes', [season.episodeCount]);
    final year = season.year;
    return SeasonBubbleEntry(
      id: season.number,
      code: season.number == 0 ? 'SP' : '${season.number}',
      title: title,
      detail: year == null ? count : '$count · $year',
      semanticLabel: '$title, $count',
      posterUrl: season.posterUrl,
      requested: _isRequested(season.status),
      missing: season.status.canRequest,
      missingBadge: true,
      // La fiche au survol dit déjà tout ça.
      tooltip: null,
    );
  }

  /// « 2021 · 10 épisodes · manquante », dans le même ordre que la fiche d'une
  /// saison de la bibliothèque.
  SeasonPreviewInfo _preview(RequestSeason season) {
    final year = season.year;
    return SeasonPreviewInfo(
      title: seasonTitle(season),
      facts: [
        if (year != null) '$year',
        if (season.episodeCount > 0)
          season.episodeCount > 1
              ? tr('{0} épisodes', [season.episodeCount])
              : tr('1 épisode'),
        if (_isRequested(season.status))
          tr('demandée')
        else if (season.status.canRequest)
          tr('manquante'),
      ],
      overview: season.overview,
      posterUrl: season.posterUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.seasons]
      ..sort((a, b) => a.number.compareTo(b.number));
    final selected = sorted.where((s) => s.number == _selected).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Saisons'),
          style: TextStyle(
            fontSize: AppType.title2,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        SeasonBubbleRow(
          entries: [for (final season in sorted) _entry(season)],
          selected: _selected,
          onTap: _select,
          frameKey: _frameKey,
          beamX: _beamX,
          wrap: (entry, bubble) {
            final season = sorted.firstWhere((s) => s.number == entry.id);
            return SeasonHoverPreview(
              info: _preview(season),
              openLabel: tr('Voir les épisodes'),
              onOpen: () => _open(season.number),
              child: bubble,
            );
          },
        ),
        const SizedBox(height: 4),
        SeasonSizeTween(
          duration: AppMotion.emphasis,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: selected == null
              ? const SizedBox(width: double.infinity)
              : SeasonFrame(
                  key: _frameKey,
                  beamX: _beamX,
                  direction: _direction,
                  // Sa propre section sous la télécommande : Bas depuis une
                  // bulle entre par le haut du panneau (« Demander »). Dans
                  // la section des bulles, le parcours géométrique sautait
                  // la pastille, hors du faisceau d'une bulle calée à gauche,
                  // pour la première affiche tout en bas de la fiche.
                  child: TvRegion.section(
                    child: RequestSeasonPanel(
                      key: ValueKey(selected.number),
                      tmdbId: widget.tmdbId,
                      showItem: widget.showItem,
                      season: selected,
                      cache: _cache,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
