import 'package:flutter/material.dart';

import '../../../../l10n/tr.dart';
import '../../../../models/models.dart';
import '../../../../theme/app_type.dart';
import '../../../../theme/focus_fill.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../utils/format.dart';
import '../../../../widgets/global/media_poster.dart';
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
    required this.currentEpisodeId,
    required this.seasons,
    required this.selectedSeasonId,
    required this.onSeasonChanged,
    required this.episodes,
    required this.isLoading,
    required this.onEpisodeSelected,
  });

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

  @override
  Widget build(BuildContext context) {
    final hasSeasons = widget.seasons.length > 1;

    // Rien ne se télécharge d'ici : l'onglet sert à changer d'épisode, et
    // l'utilisateur ne voulait pas d'un bouton de téléchargement sous le doigt
    // au milieu d'un film. On télécharge depuis la fiche de la série.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSeasons) ...[
          SizedBox(height: 40, child: _buildSeasons()),
          const SizedBox(height: _gap),
        ],
        Expanded(child: _buildEpisodes()),
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

  Widget _buildEpisodes() {
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
    required this.onTap,
    required this.focusNode,
  });

  final HomeMediaItem episode;
  final bool isCurrent;
  final double width;
  final double thumbHeight;
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
