import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../services/client_log.dart';
import 'retro_share.dart';

/// Partage l'image de récap depuis un écran, avec ce qu'il faut dire : le
/// chemin quand elle a été enregistrée (PC), un message quand elle n'a pas pu
/// être préparée. Le dernier écran de la story et la carte de l'accueil
/// passent par ici.
Future<void> shareRetroImage(
  BuildContext context, {
  required RetroReport report,
  required String name,
  Rect? origin,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final view = View.of(context);
  try {
    final path = await RetroShare.share(
      view,
      report: report,
      name: name,
      origin: origin,
    );
    if (path != null) {
      messenger?.showSnackBar(SnackBar(
        content: Text(tr('Image enregistrée : {0}', [path])),
      ));
    }
  } catch (error) {
    ClientLog.error('Rétro : image de récap impossible — $error');
    messenger?.showSnackBar(SnackBar(
      content: Text(tr(
          'Impossible de préparer l’image du Rétro. Réessaie dans un instant.')),
    ));
  }
}
