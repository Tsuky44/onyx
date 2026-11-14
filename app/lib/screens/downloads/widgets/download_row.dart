import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/offline_download.dart';
import '../../../navigation/search_route_observer.dart';
import '../../../services/download_manager.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/format.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/glass_chrome.dart';
import '../../../widgets/global/local_file_image.dart';
import '../../../widgets/global/media_download_button.dart';
import '../../../widgets/global/onyx_menu.dart';
import '../../player/player_screen.dart';

/// Lance la lecture d'un téléchargement terminé, depuis le fichier local.
void playDownload(BuildContext context, OfflineDownload entry) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: SearchRouteObserver.playerRouteName),
      builder: (_) => PlayerScreen(
        media: entry.toHomeMediaItem(),
        seasonNumber: entry.seasonNumber,
      ),
    ),
  );
}

/// Ce que le menu d'une ligne peut faire, en plus de son action visible.
enum _RowAction { resume, delete }

/// La ligne d'un téléchargement, hors téléviseur (maquette « 6 ·
/// Téléchargements »).
///
/// Une seule action est visible à droite, celle que l'état appelle : la pause
/// pour ce qui descend, « Réessayer » pour un échec, la lecture pour ce qui est
/// sur l'appareil. Le reste passe par le menu, la suppression en dernier.
class DownloadRow extends StatelessWidget {
  final OfflineDownload entry;

  const DownloadRow({super.key, required this.entry});

  static const double thumbWidth = 112;
  static const double thumbHeight = 63;

  @override
  Widget build(BuildContext context) {
    final pad = AppLayout.pagePadding(context);
    final playable = entry.isCompleted;
    return InkWell(
      onTap: playable ? () => playDownload(context, entry) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
        child: Row(
          children: [
            _Thumbnail(entry: entry),
            const SizedBox(width: 14),
            Expanded(child: _Texts(entry: entry)),
            const SizedBox(width: 12),
            _PrimaryAction(entry: entry),
            _RowMenu(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final OfflineDownload entry;

  const _Thumbnail({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Le manifeste ne garde que l'affiche : elle est recadrée en paysage
    // plutôt qu'une image inventée. Le fichier local et rien d'autre, une URL
    // distante ne s'afficherait pas là où cet écran sert le plus.
    final path = context.read<DownloadManager>().localPosterPath(entry.mediaId);
    final downloading =
        !entry.isCompleted && entry.status != DownloadStatus.failed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: DownloadRow.thumbWidth,
        height: DownloadRow.thumbHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null)
              localFileImage(path)
            else
              const ColoredBox(color: AppColors.surfaceElevated),
            if (downloading)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: entry.progress,
                  minHeight: 3,
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.textPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Texts extends StatelessWidget {
  final OfflineDownload entry;

  const _Texts({required this.entry});

  @override
  Widget build(BuildContext context) {
    final failed = entry.status == DownloadStatus.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: AppType.body,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (failed) ...[
              const _FailedPill(),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                downloadSecondaryLine(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: AppType.footnote,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// La ligne secondaire : l'épisode, puis ce que l'état sait dire (taille,
/// avancement du téléchargement, ce qui a déjà été regardé).
String downloadSecondaryLine(OfflineDownload entry) {
  final parts = <String>[
    if (entry.episodeCode != null) entry.episodeCode!,
  ];
  switch (entry.status) {
    case DownloadStatus.completed:
      parts.add(formatBytes(entry.bytesTotal));
      if (entry.isFinished) {
        parts.add(tr('Vu'));
      } else if (entry.positionSeconds > 0) {
        parts.add(tr('{0} % vu', [(entry.watchedFraction * 100).round()]));
      }
    case DownloadStatus.downloading:
      parts.add(entry.bytesTotal > 0
          ? tr('{0} sur {1}', [
              formatBytes(entry.bytesReceived),
              formatBytes(entry.bytesTotal),
            ])
          : formatBytes(entry.bytesReceived));
    case DownloadStatus.queued:
      parts.add(tr('En attente'));
    case DownloadStatus.paused:
      parts.add(tr('En pause'));
      if (entry.bytesTotal > 0) {
        parts.add(tr('{0} sur {1}', [
          formatBytes(entry.bytesReceived),
          formatBytes(entry.bytesTotal),
        ]));
      }
    case DownloadStatus.failed:
      parts.add(entry.error ?? tr('Échec du téléchargement'));
  }
  return parts.join(' · ');
}

class _FailedPill extends StatelessWidget {
  const _FailedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr('Échec'),
        style: const TextStyle(
          color: AppColors.error,
          fontSize: AppType.caption,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final OfflineDownload entry;

  const _PrimaryAction({required this.entry});

  @override
  Widget build(BuildContext context) {
    final manager = context.read<DownloadManager>();
    if (entry.isActive) {
      return Tooltip(
        message: tr('Mettre en pause'),
        child: GlassIconButton(
          size: 36,
          onTap: () => manager.pause(entry.mediaId),
          child: const Icon(AppIcons.pause,
              size: 15, color: AppColors.textPrimary),
        ),
      );
    }
    switch (entry.status) {
      case DownloadStatus.failed:
        return _GlassCapsule(
          label: tr('Réessayer'),
          onTap: () => manager.resume(entry.mediaId),
        );
      case DownloadStatus.completed:
        return _PlayDisc(onTap: () => playDownload(context, entry));
      // Une pause n'a pas d'action visible : la reprendre est un choix, il
      // passe par le menu.
      case DownloadStatus.paused:
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return const SizedBox.shrink();
    }
  }
}

/// La lecture : le seul rond blanc de l'écran, ce qu'on vient y faire.
class _PlayDisc extends StatelessWidget {
  final VoidCallback onTap;

  const _PlayDisc({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final target = AppLayout.minTouchTarget(context);
    return Tooltip(
      message: tr('Lire'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: target,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textPrimary,
                ),
                child: const Icon(AppIcons.play,
                    size: 16, color: AppColors.background),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une capsule de verre, dans la matière de [GlassIconButton].
class _GlassCapsule extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GlassCapsule({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: AppLayout.minTouchTarget(context)),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppType.subhead,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  final OfflineDownload entry;

  const _RowMenu({required this.entry});

  @override
  Widget build(BuildContext context) {
    final manager = context.read<DownloadManager>();
    return OnyxMenuButton<_RowAction>(
      icon: AppIcons.more,
      tooltip: tr('Plus d’actions'),
      items: [
        if (entry.status == DownloadStatus.paused)
          OnyxMenuItem(
            value: _RowAction.resume,
            label: tr('Reprendre'),
            icon: AppIcons.download,
          ),
        OnyxMenuItem(
          value: _RowAction.delete,
          label: tr('Supprimer'),
          icon: AppIcons.delete,
          destructive: true,
        ),
      ],
      onSelected: (action) async {
        switch (action) {
          case _RowAction.resume:
            await manager.resume(entry.mediaId);
          case _RowAction.delete:
            final confirmed = await confirmDeleteDownload(context, entry);
            if (confirmed) await manager.delete(entry.mediaId);
        }
      },
    );
  }
}
