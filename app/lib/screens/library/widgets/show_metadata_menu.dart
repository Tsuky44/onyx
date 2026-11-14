import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../theme/app_icons.dart';
import '../../../l10n/tr.dart';
import '../../../widgets/global/onyx_menu.dart';

/// Le menu « Métadonnées série » de la fiche d'une série.
///
/// Ses entrées appellent des routes que le serveur réserve à
/// `manage_library` (ADR-0001) : un compte sans ce droit n'a pas de menu du
/// tout, plutôt qu'un crayon qui mène à un refus.
class ShowMetadataMenu extends StatelessWidget {
  /// Relancer l'identification à partir du dossier local.
  final VoidCallback onRedetect;

  /// Choisir soi-même la fiche TMDB.
  final VoidCallback onPickOnTmdb;

  /// Choisir l'affiche parmi celles de TMDB et Fanart.tv (ADR-0068).
  final VoidCallback onChangePoster;

  const ShowMetadataMenu({
    super.key,
    required this.onRedetect,
    required this.onPickOnTmdb,
    required this.onChangePoster,
  });

  @override
  Widget build(BuildContext context) {
    final canFixMetadata =
        context.select<AuthProvider, bool>((a) => a.permissions.manageLibrary);
    if (!canFixMetadata) return const SizedBox.shrink();

    return OnyxMenuButton<VoidCallback>(
      tooltip: tr('Métadonnées série'),
      icon: AppIcons.edit,
      onSelected: (action) => action(),
      items: [
        OnyxMenuItem(
          value: onRedetect,
          icon: AppIcons.identify,
          label: tr('Relancer la détection auto'),
          subtitle: tr('À partir du dossier / fichiers locaux'),
        ),
        OnyxMenuItem(
          value: onPickOnTmdb,
          icon: AppIcons.search,
          label: tr('Choisir sur TMDB'),
          subtitle: tr('Correction manuelle de la fiche'),
        ),
        OnyxMenuItem(
          value: onChangePoster,
          icon: AppIcons.poster,
          label: tr('Changer l’affiche'),
          subtitle: tr('Parmi celles de TMDB et Fanart.tv'),
        ),
      ],
    );
  }
}
