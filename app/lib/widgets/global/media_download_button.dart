import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../models/offline_download.dart';
import '../../services/download_manager.dart';
import '../../theme/app_colors.dart';
import 'metered_download_dialog.dart';
import '../../theme/app_icons.dart';
import '../../l10n/tr.dart';
import 'onyx_dialog.dart';

/// Le bouton « garder sur l'appareil », partout où un média se télécharge.
///
/// Un seul contrôle porte tout le cycle de vie — lancer, mettre en pause,
/// reprendre, supprimer — parce que c'est un seul état que l'utilisateur suit :
/// « est-ce que cet épisode est chez moi ? ». Un bouton par transition aurait
/// demandé de la place que la tuile d'épisode n'a pas, et aurait fait clignoter
/// la ligne à chaque changement.
class MediaDownloadButton extends StatelessWidget {
  final HomeMediaItem item;

  /// Contexte que l'épisode ne porte pas lui-même et que l'écran hors ligne ne
  /// pourra plus aller chercher : sans nom de série, un téléchargement se
  /// retrouve seul dans la liste sous son seul titre d'épisode.
  final String? showTitle;
  final int? showId;
  final int? seasonNumber;
  final String? showPosterUrl;

  /// Version réduite pour une ligne de liste.
  final bool compact;

  /// L'état seul : rien tant que rien n'est lancé. Sur la fiche d'un film hors
  /// TV, le geste de départ vit dans le menu « Plus » (ADR-0132) ; l'anneau
  /// d'avancement, lui, reste dans la rangée tant qu'il a quelque chose à dire.
  final bool statusOnly;

  const MediaDownloadButton({
    super.key,
    required this.item,
    this.showTitle,
    this.showId,
    this.seasonNumber,
    this.showPosterUrl,
    this.compact = false,
    this.statusOnly = false,
  });

  bool get _isDownloadable =>
      item.isAvailable &&
      (item.media.type == MediaType.movie ||
          item.media.type == MediaType.episode);

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    if (!manager.isSupported || !_isDownloadable) {
      return const SizedBox.shrink();
    }

    final entry = manager.entryFor(item.media.id);
    if (statusOnly && entry == null) return const SizedBox.shrink();
    final size = compact ? 20.0 : 22.0;

    return IconButton(
      tooltip: _tooltip(entry),
      onPressed: () => runMediaDownloadAction(
        context,
        manager,
        item,
        showTitle: showTitle,
        showId: showId,
        seasonNumber: seasonNumber,
        showPosterUrl: showPosterUrl,
      ),
      iconSize: size,
      visualDensity: compact ? VisualDensity.compact : null,
      icon: _icon(entry, size),
    );
  }

  Widget _icon(OfflineDownload? entry, double size) {
    switch (entry?.status) {
      case null:
        return const Icon(AppIcons.download, color: AppColors.textSecondary);
      case DownloadStatus.completed:
        return const Icon(AppIcons.downloaded, color: AppColors.success);
      case DownloadStatus.failed:
        return const Icon(AppIcons.error, color: AppColors.textSecondary);
      case DownloadStatus.paused:
        return const Icon(AppIcons.pauseCircle, color: AppColors.textSecondary);
      case DownloadStatus.queued:
      case DownloadStatus.downloading:
        // L'anneau porte l'avancement et l'icône porte l'action : un carré
        // d'arrêt au centre, pour qu'un appui pendant le transfert ne soit
        // jamais ambigu.
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: entry!.progress,
                strokeWidth: 2,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.textPrimary),
              ),
              Icon(
                AppIcons.stop,
                size: size * 0.5,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        );
    }
  }

  String _tooltip(OfflineDownload? entry) {
    switch (entry?.status) {
      case null:
        return tr('Télécharger');
      case DownloadStatus.completed:
        return tr('Téléchargé');
      case DownloadStatus.failed:
        return entry!.error ?? tr('Échec du téléchargement');
      case DownloadStatus.paused:
        return tr('Reprendre le téléchargement');
      case DownloadStatus.queued:
        return tr('En attente');
      case DownloadStatus.downloading:
        return tr('Téléchargement en cours');
    }
  }
}

/// Le geste du bouton de téléchargement selon l'état de [item] : lancer,
/// mettre en pause, reprendre ou supprimer. Partagé avec le menu « Plus » de
/// la fiche d'un film, qui appelle le même cycle (ADR-0132).
Future<void> runMediaDownloadAction(
  BuildContext context,
  DownloadManager manager,
  HomeMediaItem item, {
  String? showTitle,
  int? showId,
  int? seasonNumber,
  String? showPosterUrl,
}) async {
  final entry = manager.entryFor(item.media.id);
  switch (entry?.status) {
    case null:
    case DownloadStatus.failed:
      // Sur un forfait, un épisode se compte en gigaoctets : la question est
      // posée avant la mise en file, jamais après.
      final proceed = await confirmDownloadOnThisNetwork(
        context,
        what: item.media.type == MediaType.movie
            ? tr('ce film')
            : tr('cet épisode'),
      );
      if (!proceed) return;
      await manager.download(
        item,
        showTitle: showTitle,
        showId: showId,
        seasonNumber: seasonNumber,
        showPosterUrl: showPosterUrl,
      );
    case DownloadStatus.queued:
    case DownloadStatus.downloading:
      await manager.pause(item.media.id);
    case DownloadStatus.paused:
      await manager.resume(item.media.id);
    case DownloadStatus.completed:
      // Effacer un fichier de plusieurs gigaoctets sur un appui qui visait
      // peut-être la ligne d'à côté : la confirmation n'est pas négociable.
      final confirmed = await confirmDeleteDownload(context, entry!);
      if (confirmed) await manager.delete(item.media.id);
  }
}

/// Demande confirmation avant d'effacer un média du disque.
///
/// Partagée par le bouton et l'écran des téléchargements pour que la question
/// soit posée dans les mêmes termes des deux côtés.
Future<bool> confirmDeleteDownload(
  BuildContext context,
  OfflineDownload entry,
) async {
  final unsynced = entry.needsSync;
  return showOnyxConfirm(
    context,
    title: tr('Supprimer le téléchargement ?'),
    message: unsynced
        ? tr(
            '« {0} » libérera de la place sur cet appareil. Son '
            'avancement sera envoyé au serveur dès que possible.',
            [entry.title],
          )
        : tr(
            '« {0} » libérera de la place sur cet appareil. Le média '
            'reste disponible sur le serveur.',
            [entry.title],
          ),
    confirmLabel: tr('Supprimer'),
    destructive: true,
    icon: AppIcons.delete,
  );
}
