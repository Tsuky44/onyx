import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/offline_download.dart';
import '../../../services/download_manager.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_focus.dart';
import '../../../utils/format.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/local_file_image.dart';
import '../../../widgets/global/media_download_button.dart';
import 'download_row.dart' show playDownload;

/// La ligne d'un téléchargement sur un téléviseur : le rendu d'avant la
/// refonte du PC, gardé tel quel tant que la TV n'a pas la sienne. Sa
/// navigation (la ligne jouable, son menu à droite) est épinglée par
/// `test/downloads_navigation_map_test.dart`.
class DownloadTvRow extends StatelessWidget {
  final OfflineDownload entry;
  final bool compact;

  const DownloadTvRow({super.key, required this.entry, required this.compact});

  @override
  Widget build(BuildContext context) {
    final manager = context.read<DownloadManager>();
    final pad = AppLayout.pagePadding(context);
    final thumbW = compact ? 104.0 : 140.0;
    final thumbH = thumbW * 9 / 16;
    final playable = entry.isCompleted;

    return TvFocusable(
      enabled: playable,
      onSelect: () => _play(context),
      focusScale: 1.0,
      scrollAlignment: 0.3,
      showRing: false,
      // Le menu de la ligne (suspendre, supprimer) reste une cible : droite
      // y entre, gauche en ressort.
      childFocus: true,
      child: InkWell(
        onTap: playable ? () => _play(context) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(
                entry: entry,
                width: thumbW,
                height: thumbH,
                manager: manager,
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (entry.episodeCode != null) entry.episodeCode!,
                        entry.title,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 14 : 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusLine(entry),
                      style: TextStyle(
                        color: entry.status == DownloadStatus.failed
                            ? AppColors.error
                            : AppColors.textMuted,
                        fontSize: AppType.footnote,
                      ),
                    ),
                    if (entry.isActive) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: entry.progress,
                          minHeight: 3,
                          backgroundColor: AppColors.border,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.progress),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _RowActions(entry: entry),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine(OfflineDownload entry) {
    switch (entry.status) {
      case DownloadStatus.completed:
        final size = formatBytes(entry.bytesTotal);
        if (entry.isFinished) return tr('Vu · {0}', [size]);
        if (entry.positionSeconds > 0) {
          return tr('{0}% visionné · {1}',
              [(entry.watchedFraction * 100).round(), size]);
        }
        return size;
      case DownloadStatus.downloading:
        final total =
            entry.bytesTotal > 0 ? ' sur ${formatBytes(entry.bytesTotal)}' : '';
        return tr(
            '{0}{1} téléchargés', [formatBytes(entry.bytesReceived), total]);
      case DownloadStatus.queued:
        return tr('En attente');
      case DownloadStatus.paused:
        return tr(
            'En pause · {0} téléchargés', [formatBytes(entry.bytesReceived)]);
      case DownloadStatus.failed:
        return entry.error ?? tr('Échec du téléchargement');
    }
  }

  void _play(BuildContext context) => playDownload(context, entry);
}

class _Thumbnail extends StatelessWidget {
  final OfflineDownload entry;
  final double width;
  final double height;
  final DownloadManager manager;

  const _Thumbnail({
    required this.entry,
    required this.width,
    required this.height,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    // Le fichier local et rien d'autre : une URL distante ne s'afficherait pas
    // là où cet écran sert le plus.
    final path = manager.localPosterPath(entry.mediaId);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null)
              localFileImage(path)
            else
              const ColoredBox(color: AppColors.surfaceElevated),
            if (entry.isCompleted && entry.isFinished)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(AppIcons.check,
                      size: 13, color: AppColors.success),
                ),
              ),
            if (entry.isCompleted &&
                !entry.isFinished &&
                entry.watchedFraction > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: entry.watchedFraction,
                  minHeight: 3,
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  valueColor: const AlwaysStoppedAnimation(AppColors.progress),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  final OfflineDownload entry;

  const _RowActions({required this.entry});

  @override
  Widget build(BuildContext context) {
    final manager = context.read<DownloadManager>();
    return PopupMenuButton<String>(
      icon: const Icon(AppIcons.moreVertical,
          color: AppColors.textSecondary, size: 20),
      color: AppColors.surfaceElevated,
      onSelected: (value) async {
        switch (value) {
          case 'pause':
            await manager.pause(entry.mediaId);
          case 'resume':
            await manager.resume(entry.mediaId);
          case 'retry':
            await manager.resume(entry.mediaId);
          case 'delete':
            final confirmed = await confirmDeleteDownload(context, entry);
            if (confirmed) await manager.delete(entry.mediaId);
        }
      },
      itemBuilder: (context) => [
        if (entry.isActive)
          PopupMenuItem(value: 'pause', child: Text(tr('Mettre en pause'))),
        if (entry.status == DownloadStatus.paused)
          PopupMenuItem(value: 'resume', child: Text(tr('Reprendre'))),
        if (entry.status == DownloadStatus.failed)
          PopupMenuItem(value: 'retry', child: Text(tr('Réessayer'))),
        PopupMenuItem(value: 'delete', child: Text(tr('Supprimer'))),
      ],
    );
  }
}
