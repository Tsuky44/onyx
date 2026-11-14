import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../models/watch_party.dart';
import '../../../utils/format.dart';
import 'native_tv_spec.dart';

/// Le panneau des épisodes, relevé sur `EpisodesPanelController`.
class NativeTvEpisodes {
  const NativeTvEpisodes({
    required this.seasons,
    required this.selectedSeasonId,
    required this.episodes,
    required this.currentEpisodeId,
    required this.loading,
    this.imageUrl = _noImage,
  });

  final List<Media> seasons;
  final int? selectedSeasonId;
  final List<HomeMediaItem> episodes;
  final int currentEpisodeId;
  final bool loading;

  /// L'image d'un épisode en URL absolue : l'écran seul connaît le serveur.
  final String? Function(HomeMediaItem episode) imageUrl;

  static String? _noImage(HomeMediaItem _) => null;
}

/// Le panneau « Regarder ensemble », relevé sur `PlayerWatchParty`.
class NativeTvWatchParty {
  const NativeTvWatchParty({
    this.code,
    this.members = const [],
    this.starting = false,
    this.error,
  });

  /// Null hors séance : le panneau propose alors d'en démarrer une.
  final String? code;
  final List<WatchPartyMember> members;
  final bool starting;
  final String? error;
}

/// Les onglets du panneau d'infos d'AVKit, dans l'ordre : Épisodes, Regarder
/// ensemble, Stats.
abstract final class NativeTvPanels {
  const NativeTvPanels._();

  /// Les mesures que le natif lit lui-même sur le moteur, chaque seconde tant
  /// que l'onglet est visible : Dart n'en donne que l'ordre et les libellés.
  static const statsRows = [
    'route',
    'videoCodec',
    'videoDecoder',
    'audioDecoder',
    'observedFps',
    'containerFps',
    'droppedFrames',
    'averageBitrateMbps',
    'videoBitrate',
    'videoFormat',
    'audioDelivery',
    'container',
  ];

  /// Comme `PlayerEpisodesTab` : les saisons en onglets, l'épisode qui joue
  /// marqué, l'avancement d'un épisode commencé.
  static OnyxAppleNativePanel episodes(NativeTvEpisodes state) {
    final selectedSeason = state.selectedSeasonId;
    return OnyxAppleNativePanel(
      id: NativeTvIds.episodesPanel,
      title: tr('Épisodes'),
      message: !state.loading && state.episodes.isEmpty
          ? tr('Aucun épisode disponible')
          : null,
      tabs: [
        for (final season in state.seasons)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.seasonTabPrefix}${season.id}',
            label: (season.effectiveSeasonNumber ?? 0) > 0
                ? tr('Saison {0}', [season.effectiveSeasonNumber])
                : season.title,
            selected: season.id == selectedSeason,
          ),
      ],
      rows: [
        for (final episode in state.episodes)
          () {
            final number = episode.media.effectiveEpisodeNumber;
            final duration = episode.effectiveDuration;
            final started =
                episode.currentPositionSeconds > 0 && !episode.isFinished;
            return OnyxAppleNativePanelRow(
              id: '${NativeTvIds.episodeRowPrefix}${episode.media.id}',
              title: episode.media.title,
              subtitle: number == null ? null : tr('Épisode {0}', [number]),
              detail: duration > 0 ? formatDuration(duration) : null,
              imageUrl: state.imageUrl(episode),
              progress: started ? episode.percentWatched : null,
              selected: episode.media.id == state.currentEpisodeId,
              selectable: true,
            );
          }(),
      ],
      actions: const [],
      loading: state.loading,
    );
  }

  /// Comme `PlayerWatchPartyTab`. « Copier » n'a pas de sens à la télécommande.
  ///
  /// Une colonne de présentation à gauche (`headline`), les lignes à droite :
  /// hors séance, le titre, l'explication, le bouton, et à côté les trois
  /// étapes ; en séance, le code en grand et les participants. Le premier
  /// dessin n'avait qu'un paragraphe et un bouton au bout de la ligne, sur
  /// un panneau de toute la largeur de l'écran : « un peu vide ».
  static OnyxAppleNativePanel watchParty(NativeTvWatchParty state) {
    final code = state.code;
    if (code == null) {
      return OnyxAppleNativePanel(
        id: NativeTvIds.watchPartyPanel,
        title: tr('Regarder ensemble'),
        headline: tr('Regardez à plusieurs'),
        message: [
          tr('Lecture, pauses et déplacements sont partagés entre tous, '
              'chacun sur son appareil.'),
          if (state.error != null) state.error!,
        ].join('\n\n'),
        tabs: const [],
        rowsTitle: tr('Comment ça marche'),
        rows: [
          _step(1, tr('Démarrez la séance'),
              tr('Depuis ce panneau, pendant la lecture.')),
          _step(2, tr('Partagez le code'),
              tr('Il s’affiche ici une fois la séance ouverte.')),
          _step(3, tr('Chacun la rejoint'),
              tr('Menu du compte › Rejoindre une séance.')),
        ],
        actions: [
          OnyxAppleNativeAction(
            id: NativeTvIds.watchPartyStart,
            label: tr('Démarrer une séance'),
            icon: 'play.fill',
          ),
        ],
        loading: state.starting,
      );
    }
    final members = state.members;
    return OnyxAppleNativePanel(
      id: NativeTvIds.watchPartyPanel,
      title: tr('Regarder ensemble'),
      eyebrow: tr('Code de la séance'),
      headline: code,
      message: tr('Pour rejoindre : menu du compte › Rejoindre une séance.'),
      tabs: const [],
      rowsTitle: members.length > 1
          ? tr('{0} participants', [members.length])
          : tr('En attente des autres participants…'),
      rows: [
        for (var i = 0; i < members.length; i++)
          () {
            final member = members[i];
            final name =
                member.username.isEmpty ? tr('Invité') : member.username;
            return OnyxAppleNativePanelRow(
              id: '${NativeTvIds.memberRowPrefix}$i',
              title: member.isYou ? tr('{0} (vous)', [name]) : name,
              subtitle: member.device,
              detail: member.isHost ? tr('Hôte') : null,
              badge: name.characters.first.toUpperCase(),
              selected: false,
              selectable: false,
            );
          }(),
      ],
      actions: [
        OnyxAppleNativeAction(
          id: NativeTvIds.watchPartyLeave,
          label: tr('Quitter la séance'),
        ),
      ],
      loading: false,
    );
  }

  static OnyxAppleNativePanelRow _step(int number, String title, String how) =>
      OnyxAppleNativePanelRow(
        id: '${NativeTvIds.stepRowPrefix}$number',
        title: title,
        subtitle: how,
        badge: '$number',
        selected: false,
        selectable: false,
      );

  static OnyxAppleNativePanel stats() => OnyxAppleNativePanel(
        id: NativeTvIds.statsPanel,
        title: tr('Statistiques'),
        tabs: const [],
        rows: [
          for (final id in statsRows)
            OnyxAppleNativePanelRow(
              id: id,
              title: _statLabel(id),
              selected: false,
              selectable: false,
            ),
        ],
        actions: const [],
        loading: false,
      );

  /// Les libellés du journal de lecture (`playback_logs_screen.dart`) quand
  /// la mesure y figure déjà.
  static String _statLabel(String id) => switch (id) {
        'route' => tr('Chemin de lecture'),
        'videoCodec' => tr('Codec vidéo'),
        'videoDecoder' => tr('Décodeur vidéo'),
        'audioDecoder' => tr('Décodeur audio'),
        'observedFps' => tr('Images par seconde'),
        'containerFps' => tr('Cadence du fichier'),
        'droppedFrames' => tr('Images perdues'),
        'averageBitrateMbps' => tr('Débit moyen'),
        'videoBitrate' => tr('Débit vidéo'),
        'videoFormat' => tr('Format vidéo'),
        'audioDelivery' => tr('Sortie audio'),
        'container' => tr('Conteneur'),
        _ => id,
      };
}
