import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../models/offline_download.dart';
import '../../services/download_manager.dart';
import '../../theme/app_icons.dart';
import 'media_download_button.dart';
import 'onyx_menu.dart';
import 'season_download_plan.dart';
import 'season_download_target.dart';

/// Les lignes du menu « Plus » d'une fiche qui ont un état (ADR-0132).
///
/// Chacune dit ce que l'appui va faire dans l'état présent (« Télécharger la
/// saison 2 », « Reprendre le téléchargement »), et appelle le même geste que
/// le bouton qu'elle remplace. Nulle quand ce bouton ne serait pas dessiné.

/// « Télécharger la saison N » et ses suites : compléter, annuler, retirer.
OnyxMenuItem<VoidCallback>? seasonDownloadMenuItem(
  BuildContext context,
  DownloadManager manager,
  SeasonDownloadTarget target,
) {
  if (!manager.isSupported) return null;
  final plan = SeasonDownloadPlan.of(target.episodes, manager.entryFor);
  if (plan.isEmpty) return null;
  final season = target.seasonNumber;

  if (plan.isComplete) {
    return OnyxMenuItem(
      value: () => target.deleteSeason(context, manager, plan.downloadable),
      icon: AppIcons.delete,
      label: season == null
          ? tr('Retirer la saison de l’appareil')
          : tr('Retirer la saison {0} de l’appareil', [season]),
      subtitle: tr('Téléchargée · {0}',
          [SeasonDownloadTarget.episodeCount(plan.done)]),
    );
  }
  if (plan.running > 0) {
    return OnyxMenuItem(
      value: () => target.cancelShow(context, manager),
      icon: AppIcons.close,
      label: tr('Annuler les téléchargements de la série'),
      subtitle: tr('{0}/{1} épisodes téléchargés', [plan.done, plan.requested]),
    );
  }

  final batch = plan.nextBatch;
  final unwatched = plan.nextBatchIsUnwatched;
  final String label;
  final int count;
  if (unwatched) {
    label = season == null
        ? tr('Télécharger les non vus de la saison')
        : tr('Télécharger les non vus de la saison {0}', [season]);
    count = plan.unwatchedMissing;
  } else if (plan.done > 0) {
    label = season == null
        ? tr('Compléter la saison')
        : tr('Compléter la saison {0}', [season]);
    count = plan.missing;
  } else {
    label = season == null
        ? tr('Télécharger la saison')
        : tr('Télécharger la saison {0}', [season]);
    count = plan.missing;
  }
  return OnyxMenuItem(
    value: () {
      if (batch != null) {
        target.download(context, manager, batch, unwatchedOnly: unwatched);
      }
    },
    enabled: batch != null,
    icon: AppIcons.download,
    label: label,
    subtitle: SeasonDownloadTarget.episodeCount(count),
  );
}

/// Le cycle de `MediaDownloadButton` pour un film, en mots.
OnyxMenuItem<VoidCallback>? mediaDownloadMenuItem(
  BuildContext context,
  DownloadManager manager,
  HomeMediaItem item,
) {
  final downloadable = item.isAvailable &&
      (item.media.type == MediaType.movie ||
          item.media.type == MediaType.episode);
  if (!manager.isSupported || !downloadable) return null;
  final entry = manager.entryFor(item.media.id);
  final percent = entry?.progress == null
      ? null
      : tr('{0} % téléchargés', [(entry!.progress! * 100).round()]);
  final (label, icon, subtitle) = switch (entry?.status) {
    null => (
        item.media.type == MediaType.movie
            ? tr('Télécharger le film')
            : tr('Télécharger l’épisode'),
        AppIcons.download,
        null,
      ),
    DownloadStatus.failed => (
        tr('Réessayer le téléchargement'),
        AppIcons.download,
        entry!.error ?? tr('Échec du téléchargement'),
      ),
    DownloadStatus.queued => (
        tr('Mettre en pause le téléchargement'),
        AppIcons.pauseCircle,
        tr('En attente'),
      ),
    DownloadStatus.downloading => (
        tr('Mettre en pause le téléchargement'),
        AppIcons.pauseCircle,
        percent,
      ),
    DownloadStatus.paused => (
        tr('Reprendre le téléchargement'),
        AppIcons.download,
        percent,
      ),
    DownloadStatus.completed => (
        tr('Supprimer le téléchargement'),
        AppIcons.delete,
        tr('Sur cet appareil'),
      ),
  };
  return OnyxMenuItem(
    value: () => runMediaDownloadAction(context, manager, item),
    icon: icon,
    label: label,
    subtitle: subtitle,
  );
}
