import 'package:flutter/material.dart';

import '../../../../l10n/tr.dart';
import '../../../../models/models.dart';
import '../../../../theme/app_type.dart';
import '../../../../theme/focus_fill.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../tv/tv_mode.dart';
import '../../../../utils/format.dart';
import '../../../../widgets/global/media_download_button.dart';
import '../../../../widgets/global/media_poster.dart';
import '../../../../widgets/global/season_download_button.dart';
import '../onyx/onyx_capsule_button.dart';
import '../onyx/onyx_chrome_theme.dart';

/// L'onglet « Épisodes » du lecteur : les saisons en boutons, les épisodes en
/// cartes, celui qu'on regarde marqué (ADR-0130).
///
/// Une seule rangée de cartes, posée d'emblée sur l'épisode en cours : la
/// suite est à droite, ce qui précède à gauche. Le panneau d'avant montrait
/// deux fois la même saison (« À suivre », puis la saison entière).
class PlayerEpisodesTab extends StatefulWidget {
  const PlayerEpisodesTab({
    super.key,
    required this.showTitle,
    required this.currentEpisodeId,
    required this.seasons,
    required this.selectedSeasonId,
    required this.onSeasonChanged,
    required this.episodes,
    required this.isLoading,
    required this.onEpisodeSelected,
  });

  final String showTitle;
  final int currentEpisodeId;
  final List<Media> seasons;
  final int selectedSeasonId;
  final ValueChanged<int> onSeasonChanged;
  final List<HomeMediaItem> episodes;
  final bool isLoading;
  final ValueChanged<HomeMediaItem> onEpisodeSelected;

  @override
  State<PlayerEpisodesTab> createState() => _PlayerEpisodesTabState();
}

class _PlayerEpisodesTabState extends State<PlayerEpisodesTab> {
  static const double _gap = 14;

  /// Le titre et la durée sous l'image d'une carte.
  static const double _captionHeight = 46;

  final ScrollController _scroll = ScrollController();

  /// Un nœud par saison et par épisode, le même tant que l'onglet vit. La
  /// télécommande entre dans une rangée par celui de la saison affichée ou de
  /// l'épisode en cours ; un nœud « de l'élément en cours » passé de l'un à
  /// l'autre ferait perdre le focus au bouton qu'on vient de presser.
  final Map<int, FocusNode> _seasonNodes = <int, FocusNode>{};
  final Map<int, FocusNode> _episodeNodes = <int, FocusNode>{};

  FocusNode _seasonNode(int id) => _seasonNodes.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'player-season-$id'),
      );

  FocusNode _episodeNode(int id) => _episodeNodes.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'player-episode-$id'),
      );

  double _cardWidth = 240;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(PlayerEpisodesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final arrived = oldWidget.isLoading && !widget.isLoading;
    if (arrived || oldWidget.selectedSeasonId != widget.selectedSeasonId) {
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _seasonNodes.values) {
      node.dispose();
    }
    for (final node in _episodeNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  int get _currentIndex => widget.episodes
      .indexWhere((episode) => episode.media.id == widget.currentEpisodeId);

  /// Pose la rangée sur l'épisode en cours, ou à son début pour une autre
  /// saison. Par le calcul et non par un défilement « jusqu'à la carte » : les
  /// cartes ont toutes la même largeur, et la liste ne les construit pas
  /// toutes.
  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _currentIndex;
      final target = index <= 0 ? 0.0 : index * (_cardWidth + _gap);
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  int? get _selectedSeasonNumber {
    for (final season in widget.seasons) {
      if (season.id == widget.selectedSeasonId) {
        return season.effectiveSeasonNumber;
      }
    }
    return widget.episodes.firstOrNull?.media.effectiveSeasonNumber;
  }

  @override
  Widget build(BuildContext context) {
    final tv = TvMode.isTv;
    // Ce que le serveur dit de la série, relu sur ses épisodes : le lecteur
    // n'a pas toujours son identifiant (ouvert depuis autre chose qu'une
    // ligne d'accueil), la liste de la saison, si.
    final showId = widget.episodes.firstOrNull?.showId;
    final canDownload = !tv && showId != null && showId > 0;
    final hasSeasons = widget.seasons.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSeasons || canDownload) ...[
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: hasSeasons ? _buildSeasons() : const SizedBox(),
                ),
                // Emporter la suite sans quitter le lecteur : sur une saison
                // entamée, le bouton ne propose que les épisodes non vus.
                // Pas sur un téléviseur, qui ne télécharge rien.
                if (canDownload && widget.episodes.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  SeasonDownloadButton(
                    episodes: widget.episodes,
                    showTitle: widget.showTitle,
                    showId: showId,
                    seasonNumber: _selectedSeasonNumber,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: _gap),
        ],
        Expanded(child: _buildEpisodes(showId)),
      ],
    );
  }

  Widget _buildSeasons() {
    return OnyxControlsRow(
      preferredFocus: _seasonNode(widget.selectedSeasonId),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: widget.seasons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final season = widget.seasons[index];
          final selected = season.id == widget.selectedSeasonId;
          final number = season.effectiveSeasonNumber;
          return Center(
            child: OnyxCapsuleButton(
              key: ValueKey('player-season-${season.id}'),
              label: number != null && number > 0
                  ? tr('Saison {0}', [number])
                  : season.title,
              selected: selected,
              focusNode: _seasonNode(season.id),
              onPressed: () {
                if (!selected) widget.onSeasonChanged(season.id);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEpisodes(int? showId) {
    if (widget.isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            color: OnyxChromeTheme.title,
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    if (widget.episodes.isEmpty) {
      return Center(
        child: Text(
          tr('Aucun épisode disponible'),
          style: const TextStyle(
            color: OnyxChromeTheme.meta,
            fontSize: AppType.callout,
          ),
        ),
      );
    }

    final seasonNumber = _selectedSeasonNumber;
    return LayoutBuilder(
      builder: (context, constraints) {
        // L'image prend la hauteur que le volet laisse, bornée : la carte d'un
        // téléviseur fait 240 de large, celle d'un téléphone se resserre.
        final thumbHeight =
            (constraints.maxHeight - _captionHeight).clamp(72.0, 135.0);
        _cardWidth = thumbHeight * 16 / 9;
        return OnyxControlsRow(
          preferredFocus: _currentIndex >= 0
              ? _episodeNode(widget.currentEpisodeId)
              : null,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: widget.episodes.length,
            separatorBuilder: (_, __) => const SizedBox(width: _gap),
            itemBuilder: (context, index) {
              final episode = widget.episodes[index];
              final isCurrent = episode.media.id == widget.currentEpisodeId;
              return Align(
                alignment: Alignment.topCenter,
                child: _EpisodeCard(
                  key: ValueKey('player-episode-${episode.media.id}'),
                  episode: episode,
                  isCurrent: isCurrent,
                  width: _cardWidth,
                  thumbHeight: thumbHeight,
                  focusNode: _episodeNode(episode.media.id),
                  showTitle: widget.showTitle,
                  showId: showId,
                  seasonNumber: seasonNumber,
                  onTap: () => widget.onEpisodeSelected(episode),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    super.key,
    required this.episode,
    required this.isCurrent,
    required this.width,
    required this.thumbHeight,
    required this.showTitle,
    required this.showId,
    required this.seasonNumber,
    required this.onTap,
    required this.focusNode,
  });

  final HomeMediaItem episode;
  final bool isCurrent;
  final double width;
  final double thumbHeight;
  final String showTitle;
  final int? showId;
  final int? seasonNumber;
  final VoidCallback onTap;
  final FocusNode focusNode;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    final number = episode.media.effectiveEpisodeNumber ?? 0;
    final duration = episode.effectiveDuration;
    final finished = episode.isFinished;
    final started = episode.currentPositionSeconds > 0 && !finished;
    final title =
        number > 0 ? '$number · ${episode.media.title}' : episode.media.title;
    final status = isCurrent
        ? tr('En cours')
        : finished
            ? tr('Vu')
            : null;
    final meta = [
      if (duration > 0) formatDuration(duration),
      if (status != null) status,
    ].join(' · ');

    return SizedBox(
      width: width,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onTap,
        borderRadius: _radius,
        // La carte voisine est à 14 px : assez pour grandir sans la toucher.
        focusScale: 1.04,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: _radius,
                    border: isCurrent
                        ? Border.all(color: OnyxChromeTheme.title, width: 2)
                        : Border.all(color: OnyxChromeTheme.glassHairline),
                  ),
                  child: ClipRRect(
                    borderRadius: _radius,
                    child: Stack(
                      children: [
                        MediaPoster(
                          media: episode.media,
                          width: width,
                          height: thumbHeight,
                          borderRadius: 0,
                        ),
                        if (started)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: episode.percentWatched,
                              minHeight: 3,
                              backgroundColor: OnyxChromeTheme.progressTrack,
                              valueColor: const AlwaysStoppedAnimation(
                                OnyxChromeTheme.progressPlayed,
                              ),
                            ),
                          ),
                        if (isCurrent)
                          const Positioned(
                            left: 8,
                            bottom: 8,
                            child: _NowPlayingMark(),
                          ),
                        // Pas sur un téléviseur : un second arrêt de focus dans
                        // chaque carte doublerait les pas de télécommande, et
                        // un téléviseur ne télécharge rien.
                        if (!TvMode.isTv)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: OnyxChromeTheme.questionVeil,
                                shape: BoxShape.circle,
                              ),
                              child: MediaDownloadButton(
                                item: episode,
                                showTitle: showTitle,
                                showId: showId,
                                seasonNumber: seasonNumber,
                                compact: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: OnyxChromeTheme.title,
                    fontSize: AppType.subhead,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: OnyxChromeTheme.meta,
                      fontSize: AppType.footnote,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La marque de l'épisode qu'on regarde, sur son image.
class _NowPlayingMark extends StatelessWidget {
  const _NowPlayingMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: FocusFill.fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr('En cours'),
        style: const TextStyle(
          color: FocusFill.ink,
          fontSize: AppType.caption,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
