import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../providers/home_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';

/// Ce que l'indexeur du serveur est en train de faire, dans l'en-tête des
/// grands écrans : scan, affiches, rapprochement, sous-titres. Vide au repos.
class ShellIndexerStatus extends StatelessWidget {
  final HomeProvider homeProvider;

  const ShellIndexerStatus({super.key, required this.homeProvider});

  @override
  Widget build(BuildContext context) {
    if (homeProvider.isScanning) {
      return _StatusBadge(label: tr('Scan…'));
    }
    if (homeProvider.isBackfillingMetadata) {
      return _StatusBadge(label: tr('Affiches…'));
    }
    if (homeProvider.isRedetectingAll) {
      final stats = homeProvider.redetectAllProgress;
      final label = stats.total > 0
          ? tr('Match {0}/{1}', [stats.processed, stats.total])
          : tr('Match…');
      return _StatusBadge(label: label);
    }
    if (homeProvider.isExtractingSubtitles) {
      final stats = homeProvider.subtitleStats;
      final label = stats.total > 0
          ? tr('Sous-titres {0}/{1}', [stats.processed, stats.total])
          : tr('Sous-titres…');
      return _StatusBadge(label: label);
    }
    return const SizedBox.shrink();
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;

  const _StatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.95),
                fontSize: AppType.caption,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
