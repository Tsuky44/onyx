import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../models/watch_list.dart';
import '../../providers/auth_provider.dart';
import '../../services/download_manager.dart';
import '../../theme/app_icons.dart';
import '../../tv/tv_mode.dart';
import '../../widgets/global/add_to_list_button.dart';
import '../../widgets/global/detail_actions.dart';
import '../../widgets/global/detail_more_button.dart';
import '../../widgets/global/detail_more_items.dart';
import '../../widgets/global/onyx_menu.dart';
import '../../widgets/global/season_download_target.dart';
import '../../widgets/global/share_media_dialog.dart';
import '../../widgets/global/share_media_button.dart';
import 'widgets/show_metadata_menu.dart';

/// La rangée d'actions de la fiche d'une série, sortie de
/// `show_detail_screen.dart` qui frôlait les 800 lignes (ADR-0052).
///
/// Hors TV : Lecture, « Ma liste », puis « Plus » qui range le reste, groupé
/// par usage, l'administration à part (ADR-0132). Sur un téléviseur, la
/// rangée de ronds d'avant, intacte : la TV a sa propre refonte (ADR-0112).
class ShowHeroActions extends StatelessWidget {
  const ShowHeroActions({
    super.key,
    required this.show,
    required this.playLabel,
    required this.onPlay,
    required this.progress,
    required this.progressLabel,
    required this.episodes,
    required this.hasPlayableEpisode,
    required this.seasonNumber,
    required this.seasonBusy,
    required this.onSetSeasonWatched,
    required this.onRedetect,
    required this.onPickOnTmdb,
    required this.onChangePoster,
  });

  final Media show;
  final String playLabel;
  final VoidCallback? onPlay;
  final double? progress;
  final String? progressLabel;

  /// Les épisodes de la saison affichée.
  final List<HomeMediaItem> episodes;

  /// Une saison au moins se lit : sans ça, le serveur refuserait le lien.
  final bool hasPlayableEpisode;
  final int? seasonNumber;
  final bool seasonBusy;
  final Future<void> Function(List<HomeMediaItem> episodes, bool watched)
      onSetSeasonWatched;
  final VoidCallback onRedetect;
  final VoidCallback onPickOnTmdb;
  final VoidCallback onChangePoster;

  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context);
    return DetailActions(
      playLabel: playLabel,
      onPlay: onPlay,
      // Même chose que sur un film : la télécommande part de Lecture.
      autofocusPlay: TvMode.isTv,
      progress: progress,
      progressLabel: progressLabel,
      secondary: isTv
          ? [
              AddToListButton(title: ListableTitle.server(show)),
              ShareCollectionButton(
                mediaId: show.id,
                title: show.title,
                tooltip: tr('Partager la série par lien'),
                hasPlayableEpisode: hasPlayableEpisode,
              ),
              ShowMetadataMenu(
                onRedetect: onRedetect,
                onPickOnTmdb: onPickOnTmdb,
                onChangePoster: onChangePoster,
              ),
            ]
          : [
              AddToListButton(title: ListableTitle.server(show), named: true),
              _ShowMoreButton(actions: this),
            ],
    );
  }
}

class _ShowMoreButton extends StatefulWidget {
  const _ShowMoreButton({required this.actions});

  final ShowHeroActions actions;

  @override
  State<_ShowMoreButton> createState() => _ShowMoreButtonState();
}

class _ShowMoreButtonState extends State<_ShowMoreButton> {
  final GlobalKey _anchor = GlobalKey();

  /// « Corriger la fiche… » a deux voies : le second menu s'ouvre à la place
  /// du premier, au même endroit, plutôt que d'aligner trois lignes
  /// d'administration dans un menu de tous les jours.
  Future<void> _fixMetadata() async {
    final a = widget.actions;
    final pick = await showOnyxMenu<VoidCallback>(
      context: context,
      anchorKey: _anchor,
      items: [
        OnyxMenuItem(
          value: a.onRedetect,
          icon: AppIcons.identify,
          label: tr('Relancer la détection auto'),
          subtitle: tr('À partir du dossier / fichiers locaux'),
        ),
        OnyxMenuItem(
          value: a.onPickOnTmdb,
          icon: AppIcons.search,
          label: tr('Choisir sur TMDB'),
          subtitle: tr('Correction manuelle de la fiche'),
        ),
      ],
    );
    if (pick != null && mounted) pick.value();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.actions;
    final auth = context.watch<AuthProvider>();
    final manager = context.watch<DownloadManager>();
    final season = a.seasonNumber;

    final available = [
      for (final episode in a.episodes)
        if (episode.isAvailable && episode.media.type == MediaType.episode)
          episode,
    ];
    final unwatched = [
      for (final episode in available)
        if (!episode.isFinished) episode,
    ];
    final allWatched = unwatched.isEmpty;
    final download = seasonDownloadMenuItem(
      context,
      manager,
      SeasonDownloadTarget(
        episodes: a.episodes,
        showTitle: a.show.title,
        showId: a.show.id,
        showPosterUrl: a.show.posterUrl,
        seasonNumber: season,
      ),
    );

    return DetailMoreButton(
      anchorKey: _anchor,
      items: [
        if (available.isNotEmpty)
          OnyxMenuItem(
            value: () => a.onSetSeasonWatched(
                allWatched ? available : unwatched, !allWatched),
            enabled: !a.seasonBusy,
            icon: allWatched ? AppIcons.watchedFilled : AppIcons.watched,
            label: switch ((allWatched, season)) {
              (false, null) => tr('Marquer la saison comme vue'),
              (false, final n?) => tr('Marquer la saison {0} comme vue', [n]),
              (true, null) => tr('Marquer la saison comme non vue'),
              (true, final n?) =>
                tr('Marquer la saison {0} comme non vue', [n]),
            },
          ),
        if (download != null) download,
        if (auth.permissions.shareMedia &&
            a.hasPlayableEpisode &&
            a.show.id > 0)
          OnyxMenuItem(
            value: () => showShareMediaDialog(
              context,
              api: auth.apiClient,
              mediaId: a.show.id,
              title: a.show.title,
              collection: true,
            ),
            icon: AppIcons.link,
            label: tr('Partager la série'),
          ),
        // Le serveur réserve ces routes à `manage_library` (ADR-0001) : sans
        // ce droit, la section n'existe pas.
        if (auth.permissions.manageLibrary) ...[
          OnyxMenuItem(
            value: _fixMetadata,
            icon: AppIcons.identify,
            label: tr('Corriger la fiche…'),
            section: tr('Administration'),
          ),
          OnyxMenuItem(
            value: a.onChangePoster,
            icon: AppIcons.poster,
            label: tr('Changer l’affiche…'),
          ),
        ],
      ],
    );
  }
}
