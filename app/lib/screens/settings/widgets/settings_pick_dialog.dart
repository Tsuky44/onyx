import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../widgets/global/onyx_dialog.dart';
import 'settings_ui.dart';

/// Un dialogue qui propose quelques lignes et rend celle qu'on touche : le
/// compte à lier, celui à dissocier. [message] se lit sous le titre ; « Annuler »
/// ferme sans rien rendre.
Future<T?> pickSettingsOption<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<(T, String)> options,
}) {
  return showOnyxDialog<T>(
    context: context,
    builder: (ctx) => OnyxDialog(
      title: title,
      message: message,
      content: SettingsGroup(
        dividerIndent: 16,
        children: [
          for (final (value, label) in options)
            SettingsTile(
              title: label,
              onTap: () => Navigator.of(ctx).pop(value),
              showChevron: false,
            ),
        ],
      ),
      actions: [
        OnyxDialogAction(
          label: tr('Annuler'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}
