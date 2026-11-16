import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/download_manager.dart';
import '../../theme/app_icons.dart';
import '../../widgets/global/detail_more_button.dart';
import '../../widgets/global/detail_more_items.dart';
import '../../widgets/global/onyx_menu.dart';
import '../../widgets/global/share_media_dialog.dart';

/// Le menu « Plus » de la fiche d'un film hors TV (ADR-0132) : vu,
/// téléchargement et partage, puis l'administration sous son titre.
class MovieMoreButton extends StatelessWidget {
  const MovieMoreButton({
    super.key,
    required this.item,
    required this.isWatched,
    required this.watchedBusy,
    required this.onToggleWatched,
    required this.onRematch,
    required this.onChangePoster,
  });

  /// La version que Lecture lancerait : c'est elle qui se télécharge et se
  /// partage, comme avec les boutons d'avant.
  final HomeMediaItem item;
  final bool isWatched;
  final bool watchedBusy;
  final VoidCallback onToggleWatched;
  final VoidCallback onRematch;
  final VoidCallback onChangePoster;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final download =
        mediaDownloadMenuItem(context, context.watch<DownloadManager>(), item);
    final shareable = auth.permissions.shareMedia &&
        item.isAvailable &&
        item.media.type == MediaType.movie;

    return DetailMoreButton(
      items: [
        OnyxMenuItem(
          value: onToggleWatched,
          enabled: !watchedBusy,
          icon: isWatched ? AppIcons.watchedFilled : AppIcons.watched,
          label: isWatched
              ? tr('Marquer comme non vu')
              : tr('Marquer comme vu'),
        ),
        if (download != null) download,
        if (shareable)
          OnyxMenuItem(
            value: () => showShareMediaDialog(
              context,
              api: auth.apiClient,
              mediaId: item.media.id,
              title: item.media.title,
            ),
            icon: AppIcons.link,
            label: tr('Partager'),
          ),
        // Le serveur réserve la correction à `manage_library` (ADR-0001) :
        // sans ce droit, la section n'existe pas.
        if (auth.permissions.manageLibrary) ...[
          OnyxMenuItem(
            value: onRematch,
            icon: AppIcons.search,
            label: tr('Corriger la fiche…'),
            subtitle: tr('Choisir sur TMDB'),
            section: tr('Administration'),
          ),
          OnyxMenuItem(
            value: onChangePoster,
            icon: AppIcons.poster,
            label: tr('Changer l’affiche…'),
          ),
        ],
      ],
    );
  }
}
