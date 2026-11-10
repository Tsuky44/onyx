import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../widgets/global/metadata_fix_sheet.dart';
import 'release_folder_hint.dart';

/// Ce qu'on corrige de la fiche d'une série depuis sa page : relancer la
/// détection TMDB, choisir la fiche à la main. Sorti de
/// `show_detail_screen.dart`, qui passait les 800 lignes (ADR-0052).

/// Les fichiers d'une série sur le disque, d'où partent la détection et la
/// recherche TMDB. [details] est la fiche relue au passage, nulle si elle n'a
/// pas pu l'être.
typedef ShowLocalFiles = ({
  String? folder,
  String? episode,
  MediaDetails? details,
});

/// Le dossier et un fichier d'épisode de la série [showId] : ceux que donne
/// sa fiche, à défaut ceux que l'on déduit des chemins de [episodes].
Future<ShowLocalFiles> resolveShowLocalFiles(
  ApiClient api, {
  required int showId,
  required List<HomeMediaItem> episodes,
}) async {
  String? folder = releaseFolderHint([
    for (final ep in episodes) ep.media.filePath,
  ]);
  String? episode;
  for (final ep in episodes) {
    final path = ep.media.filePath;
    if (path == null || path.isEmpty) continue;
    episode ??= path.split(RegExp(r'[\\/]+')).last;
  }
  MediaDetails? details;
  try {
    details = await api.getMediaDetails(showId);
    final f = details.localFolder?.trim();
    final e = details.localEpisodeFile?.trim();
    if (f != null && f.isNotEmpty) folder = f;
    if (e != null && e.isNotEmpty) episode = e;
  } catch (_) {
    // Sans fiche, le dossier et l'épisode déduits du chemin suffisent.
  }
  return (folder: folder, episode: episode, details: details);
}

/// Relance la détection TMDB de [show] depuis son dossier [folder], après
/// confirmation. [onUpdated] reçoit la série corrigée et recharge la page ;
/// le message de réussite attend qu'elle ait fini.
Future<void> redetectShowMetadata(
  BuildContext context, {
  required ApiClient api,
  required Media show,
  required String? folder,
  required Future<void> Function(Media updated) onUpdated,
}) async {
  final folderLine =
      folder?.isNotEmpty == true ? folder! : tr('dossier inconnu');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Relancer la détection')),
      content: Text(
        tr(
            'TMDB sera recherché à partir du dossier local '
            ':\n\n{0}\n\nL’affiche et les métadonnées de cette série '
            'seront remplacées.',
            [folderLine]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Annuler')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Relancer')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final updated = await api.redetectMediaMetadata(show.id);
    if (!context.mounted) return;
    await onUpdated(updated);
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Détection automatique terminée'))),
    );
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content:
            Text(tr('Détection impossible — essayez le choix manuel TMDB')),
      ),
    );
  }
}

/// Fait choisir à la main la fiche TMDB de [show], la recherche partant de
/// ses fichiers [local], puis l'applique. [onUpdated] comme pour
/// [redetectShowMetadata].
Future<void> rematchShowMetadata(
  BuildContext context, {
  required ApiClient api,
  required Media show,
  required ShowLocalFiles local,
  required Future<void> Function(Media updated) onUpdated,
}) async {
  final choice = await MetadataFixSheet.show(
    context,
    api: api,
    initialQuery: local.folder ?? local.episode ?? show.title,
    type: MediaType.show,
    localFolder: local.folder,
    localEpisodeFile: local.episode,
  );
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final updated =
        await api.rematchMediaMetadata(show.id, tmdbId: choice.tmdbId);
    if (!context.mounted) return;
    await onUpdated(updated);
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Fiche série mise à jour'))),
    );
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('Impossible de mettre à jour la fiche')),
      ),
    );
  }
}
