import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../tv/tv_deferred_keyboard.dart';
import '../../../widgets/global/onyx_dialog.dart';
import '../../../theme/app_icons.dart';

/// Demande le motif d'un refus. Null : l'administrateur a renoncé ; une
/// chaîne vide : refus sans motif.
Future<String?> askDeclineReason(BuildContext context, String title) {
  return showOnyxDialog<String>(
    context: context,
    builder: (_) => _DeclineDialog(title: title),
  );
}

class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog({required this.title});

  final String title;

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  // MediaHub garde le motif dans les notes de la demande ; le serveur d'Onyx
  // en refuse au-delà de 500 caractères.
  static const _maxReason = 300;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnyxDialog(
      title: tr('Refuser « {0} » ?', [widget.title]),
      destructive: true,
      icon: AppIcons.blocked,
      content: TvDeferredKeyboard(
        builder: (context, focusNode, canRequestFocus) => TextField(
          controller: _reason,
          focusNode: focusNode,
          canRequestFocus: canRequestFocus,
          maxLength: _maxReason,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: tr('Motif (facultatif)'),
            hintText: tr('Déjà disponible ailleurs, doublon…'),
            counterText: '',
          ),
        ),
      ),
      actions: [
        OnyxDialogAction(
          label: tr('Annuler'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        OnyxDialogAction(
          label: tr('Refuser'),
          primary: true,
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
        ),
      ],
    );
  }
}

/// Confirme la suppression d'une demande dans MediaHub.
Future<bool> confirmDeleteRequest(BuildContext context, String title) async {
  return showOnyxConfirm(
    context,
    title: tr('Supprimer la demande « {0} » ?', [title]),
    message: tr(
      'La demande disparaît de MediaHub. Ce que Radarr ou '
      'Sonarr ont déjà téléchargé reste en place.',
    ),
    confirmLabel: tr('Supprimer'),
    destructive: true,
    icon: AppIcons.delete,
  );
}
