import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/device_video.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/format.dart';
import '../../utils/responsive.dart';

/// Une vidéo de l'appareil dans la liste : son nom, sa taille, où on en est.
///
/// Pas de vignette : il faudrait décoder une image de chaque fichier, et une
/// vidéo de vacances n'a pas d'affiche à aller chercher.
class DeviceVideoRow extends StatelessWidget {
  const DeviceVideoRow({
    super.key,
    required this.video,
    required this.onPlay,
    this.onDelete,
  });

  final DeviceVideo video;
  final VoidCallback onPlay;

  /// Seulement pour une vidéo du dossier de l'app : ailleurs, le fichier
  /// appartient à l'utilisateur.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final pad = AppLayout.pagePadding(context);
    final progress = video.progress;
    final watching = progress != null &&
        !progress.isFinished &&
        progress.positionSeconds > 0;

    return InkWell(
      onTap: onPlay,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(AppIcons.play, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: AppType.body,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusLine(),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: AppType.footnote,
                    ),
                  ),
                  if (watching) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
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
            if (onDelete != null)
              IconButton(
                tooltip: tr('Supprimer'),
                icon: const Icon(AppIcons.delete, size: 20),
                color: AppColors.textMuted,
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  String _statusLine() {
    final size = formatBytes(video.sizeBytes);
    final progress = video.progress;
    if (progress == null) return size;
    if (progress.isFinished) return tr('Vu · {0}', [size]);
    if (progress.positionSeconds > 0 && progress.durationSeconds > 0) {
      return tr('{0}% visionné · {1}', [(progress.fraction * 100).round(), size]);
    }
    return size;
  }
}
