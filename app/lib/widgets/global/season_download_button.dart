import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/download_manager.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import 'season_download_plan.dart';
import 'season_download_target.dart';
import '../../theme/app_icons.dart';
import '../../l10n/tr.dart';

/// « Garder toute la saison sur l'appareil », en un geste.
///
/// Vingt appuis sur vingt lignes faisaient exactement la même chose, et
/// c'est précisément le geste qu'on fait avant de partir — donc au moment où
/// l'on a le moins envie de compter les épisodes. Le bouton ne rapatrie que ce
/// qui manque : relancé au milieu d'une saison, il complète.
class SeasonDownloadButton extends StatelessWidget {
  final List<HomeMediaItem> episodes;
  final String showTitle;
  final int showId;
  final String? showPosterUrl;
  final int? seasonNumber;

  /// L'état seul : la progression d'une saison en cours ou « Saison
  /// téléchargée », rien tant que rien n'est lancé. Hors TV, le geste de
  /// départ vit dans le menu « Plus » de la fiche (ADR-0132) ; ce qui se
  /// passe ensuite reste lisible ici, au-dessus des épisodes concernés.
  final bool statusOnly;

  const SeasonDownloadButton({
    super.key,
    required this.episodes,
    required this.showTitle,
    required this.showId,
    this.showPosterUrl,
    this.seasonNumber,
    this.statusOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    if (!manager.isSupported) return const SizedBox.shrink();

    // Sur un téléphone, le libellé partage sa ligne avec « Épisodes » et le
    // compte de disponibles : il se dit en un mot ou il déborde.
    final compact = AppLayout.isCompact(context);

    final plan = SeasonDownloadPlan.of(episodes, manager.entryFor);
    if (plan.isEmpty) return const SizedBox.shrink();
    final target = SeasonDownloadTarget(
      episodes: episodes,
      showTitle: showTitle,
      showId: showId,
      showPosterUrl: showPosterUrl,
      seasonNumber: seasonNumber,
    );
    final nextBatch = plan.nextBatch;
    final VoidCallback? addNext = nextBatch == null
        ? null
        : () => target.download(
            context,
            manager,
            nextBatch,
            unwatchedOnly: plan.nextBatchIsUnwatched,
          );

    // Tout est là : le bouton devient la sortie — c'est le seul endroit d'où
    // une saison entière se libère d'un coup.
    if (plan.isComplete) {
      return TextButton.icon(
        onPressed: () =>
            target.deleteSeason(context, manager, plan.downloadable),
        icon: const Icon(AppIcons.downloaded, size: 18),
        label: Text(
          compact
              ? tr('Téléchargée')
              : tr('Saison téléchargée · {0}', [
                  SeasonDownloadTarget.episodeCount(plan.done),
                ]),
        ),
        style: TextButton.styleFrom(foregroundColor: AppColors.success),
      );
    }

    if (plan.running > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: addNext,
            icon: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text('${plan.done}/${plan.requested}'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
          // Une saison lancée par erreur, ou sur le mauvais réseau, se
          // défaisait épisode par épisode depuis l'écran des téléchargements.
          // L'arrêt porte sur toute la série : la réserve automatique a pu
          // mettre en file la saison suivante, et elle fait partie du même
          // geste.
          IconButton(
            onPressed: () => target.cancelShow(context, manager),
            tooltip: tr('Annuler les téléchargements de la série'),
            icon: const Icon(AppIcons.close, size: 18),
            visualDensity: VisualDensity.compact,
            color: AppColors.textSecondary,
          ),
        ],
      );
    }

    if (statusOnly) return const SizedBox.shrink();

    final String label;
    if (plan.nextBatchIsUnwatched) {
      label = compact
          ? tr('Non vus ({0})', [plan.unwatchedMissing])
          : tr('Télécharger les non vus · {0}', [
              SeasonDownloadTarget.episodeCount(plan.unwatchedMissing),
            ]);
    } else if (plan.done > 0) {
      label = compact
          ? tr('Compléter ({0})', [plan.missing])
          : tr('Compléter · {0}', [
              SeasonDownloadTarget.episodeCount(plan.missing),
            ]);
    } else {
      label = compact ? tr('La saison') : tr('Télécharger la saison');
    }
    return TextButton.icon(
      onPressed: addNext,
      icon: const Icon(AppIcons.download, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    );
  }
}
