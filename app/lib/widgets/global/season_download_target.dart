import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../services/download_manager.dart';
import '../../theme/app_icons.dart';
import 'bulk_download_delete.dart';
import 'metered_download_dialog.dart';
import 'onyx_dialog.dart';

/// Les trois gestes sur une saison entière (télécharger ce qui manque,
/// annuler la série en cours, libérer la saison), sortis de
/// `SeasonDownloadButton` pour que le menu « Plus » de la fiche appelle
/// exactement les mêmes (ADR-0132).
class SeasonDownloadTarget {
  const SeasonDownloadTarget({
    required this.episodes,
    required this.showTitle,
    required this.showId,
    this.showPosterUrl,
    this.seasonNumber,
  });

  final List<HomeMediaItem> episodes;
  final String showTitle;
  final int showId;
  final String? showPosterUrl;
  final int? seasonNumber;

  static String episodeCount(int count) =>
      tr('{0} épisode{1}', [count, count > 1 ? 's' : '']);

  Future<void> download(
    BuildContext context,
    DownloadManager manager,
    List<HomeMediaItem> candidates, {
    bool unwatchedOnly = false,
  }) async {
    final pending = [
      for (final episode in candidates)
        if (!(manager.entryFor(episode.media.id)?.isCompleted ?? false))
          episode,
    ];
    if (pending.isEmpty) return;

    final proceed = await confirmDownloadOnThisNetwork(
      context,
      what: unwatchedOnly
          ? tr('les {0} non vus de cette saison', [
              episodeCount(pending.length),
            ])
          : tr('les {0} de cette saison', [episodeCount(pending.length)]),
    );
    if (!proceed) return;

    await manager.downloadAll(
      pending,
      showTitle: showTitle,
      showId: showId,
      seasonNumber: seasonNumber,
      showPosterUrl: showPosterUrl,
    );
  }

  Future<void> cancelShow(BuildContext context, DownloadManager manager) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Annuler les téléchargements ?'),
      message: tr(
        'Les épisodes de {0} pas encore sur l’appareil sont retirés de '
        'la file. Ceux déjà téléchargés restent.',
        [showTitle],
      ),
      confirmLabel: tr('Tout annuler'),
      cancelLabel: tr('Continuer'),
      destructive: true,
      icon: AppIcons.close,
    );
    if (!confirmed) return;

    final cancelled = await manager.cancelShow(showId);
    if (cancelled == 0) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr('{0} téléchargement{1} annulé{2}', [
            cancelled,
            cancelled > 1 ? 's' : '',
            cancelled > 1 ? 's' : '',
          ]),
        ),
      ),
    );
  }

  Future<void> deleteSeason(
    BuildContext context,
    DownloadManager manager,
    List<HomeMediaItem> downloadable,
  ) => confirmDeleteDownloads(
    context,
    what: seasonNumber == null
        ? tr('la saison')
        : tr('la saison {0}', [seasonNumber]),
    entries: [
      for (final episode in downloadable)
        if (manager.entryFor(episode.media.id) case final entry?) entry,
    ],
  );
}
