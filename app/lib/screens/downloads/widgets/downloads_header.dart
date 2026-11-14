import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../services/download_manager.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/format.dart';
import '../../../widgets/global/metered_download_dialog.dart';
import '../../../widgets/global/onyx_dialog.dart';

/// Le haut de l'écran des téléchargements : titre, place occupée, et les
/// bandeaux qui disent pourquoi rien ne descend ou ne se synchronise.
class DownloadsHeader extends StatelessWidget {
  final bool compact;
  final int itemCount;
  final int bytes;
  final int watchedCount;
  final bool offline;
  final int pendingSync;

  /// La file est pleine, mais le réseau du moment se paie à l'octet.
  final bool heldForNetwork;
  final int queuedCount;

  const DownloadsHeader({
    super.key,
    required this.compact,
    required this.itemCount,
    required this.bytes,
    required this.watchedCount,
    required this.offline,
    required this.pendingSync,
    required this.heldForNetwork,
    required this.queuedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Téléchargements'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 26 : 32,
                      color: AppColors.textPrimary,
                    ),
              ),
            ),
            if (watchedCount > 0)
              TextButton.icon(
                onPressed: () => _deleteWatched(context, watchedCount),
                icon: const Icon(AppIcons.clearAll, size: 18),
                label: Text(compact
                    ? tr('Vus ({0})', [watchedCount])
                    : tr('Supprimer les vus ({0})', [watchedCount])),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        if (itemCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            '$itemCount ${itemCount > 1 ? 'éléments' : 'élément'} · ${formatBytes(bytes)}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: AppType.subhead,
            ),
          ),
        ],
        if (heldForNetwork) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: AppIcons.wifiOff,
            color: AppColors.warning,
            text: queuedCount > 1
                ? tr(
                    '{0} téléchargements attendent le Wi-Fi : le réseau '
                    'actuel se paie à l’octet.',
                    [queuedCount])
                : tr('Un téléchargement attend le Wi-Fi : le réseau actuel se '
                    'paie à l’octet.'),
            action: TextButton(
              onPressed: () => allowMeteredDownloadsNow(context),
              child: Text(tr('Quand même')),
            ),
          ),
        ],
        if (offline) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: AppIcons.cloudOff,
            color: AppColors.warning,
            text: pendingSync > 0
                ? tr(
                    'Serveur injoignable. {0} {1} au retour de la connexion.', [
                    pendingSync,
                    pendingSync > 1
                        ? tr('lectures seront synchronisées')
                        : tr('lecture sera synchronisée')
                  ])
                : tr('Serveur injoignable. Vous pouvez regarder ce qui est '
                    'sur cet appareil.'),
          ),
        ] else if (pendingSync > 0) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: AppIcons.sync,
            color: AppColors.accent,
            text: tr('Synchronisation de {0} {1} avec le serveur…', [
              pendingSync,
              pendingSync > 1 ? tr('lectures') : tr('lecture')
            ]),
          ),
        ],
      ],
    );
  }

  Future<void> _deleteWatched(BuildContext context, int count) async {
    final manager = context.read<DownloadManager>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Supprimer les médias vus ?'),
      message: tr(
          '{0} {1} de cet appareil. Ils restent disponibles sur le serveur.', [
        count,
        count > 1 ? tr('éléments seront effacés') : tr('élément sera effacé')
      ]),
      confirmLabel: tr('Supprimer'),
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirmed) return;
    final deleted = await manager.deleteWatched();
    messenger.showSnackBar(SnackBar(
      content: Text(
          '$deleted ${deleted > 1 ? 'éléments supprimés' : 'élément supprimé'}'),
    ));
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  /// La sortie du bandeau, quand il y en a une — « télécharger quand même »
  /// n'a de sens qu'à côté de la phrase qui explique pourquoi rien ne descend.
  final Widget? action;

  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.subhead,
                height: 1.35,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}
