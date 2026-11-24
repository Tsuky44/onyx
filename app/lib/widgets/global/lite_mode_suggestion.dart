import 'package:material_ui/material_ui.dart';

import '../../l10n/tr.dart';
import '../../services/player_presence.dart';
import '../../theme/app_icons.dart';
import '../../theme/lite_mode.dart';
import 'onyx_dialog.dart';

/// Propose le mode léger quand les images saccadent, au lieu de l'imposer
/// (ADR-0141).
///
/// Une fenêtre et pas un bandeau : un bandeau en bas de l'écran ne prend pas
/// le focus, et à la télécommande on ne pourrait pas y répondre. Le premier
/// bouton prend le focus, Retour ferme sans rien changer.
abstract final class LiteModeSuggestion {
  static bool _asking = false;

  /// Écoute [LiteMode.suggestion] et pose la question sur le navigateur de
  /// [navigatorKey]. Appelé une fois, au démarrage.
  static void attach(GlobalKey<NavigatorState> navigatorKey) {
    LiteMode.suggestion.addListener(() {
      if (!LiteMode.suggestion.value || _asking) return;
      final context = navigatorKey.currentState?.overlay?.context;
      // La mesure se tait pendant un film ; si un lecteur s'est ouvert entre
      // le verdict et cette image, on ne pose pas une fenêtre sur le film. La
      // question attend le prochain démarrage.
      if (context == null || !context.mounted || PlayerPresence.isOpen()) {
        LiteMode.dismissSuggestion();
        return;
      }
      ask(context);
    });
  }

  /// Pose la question et applique la réponse.
  static Future<void> ask(BuildContext context) async {
    _asking = true;
    try {
      final accepted = await showOnyxDialog<bool>(
        context: context,
        builder: (dialogContext) => OnyxDialog(
          icon: AppIcons.devices,
          title: tr('L’interface saccade sur cet appareil'),
          message: tr(
            'Le mode léger retire le flou, les mouvements et les ombres pour '
            'que l’interface reste fluide. Le fichier reste lu tel quel. Vous '
            'pourrez changer d’avis dans Réglages › Cet appareil.',
          ),
          actions: [
            OnyxDialogAction(
              label: tr('Garder l’interface complète'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            OnyxDialogAction(
              label: tr('Passer en mode léger'),
              primary: true,
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      switch (accepted) {
        case true:
          await LiteMode.acceptSuggestion();
        case false:
          await LiteMode.declineSuggestion();
        case null:
          LiteMode.dismissSuggestion();
      }
    } finally {
      _asking = false;
    }
  }
}
