import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../services/device_library/device_library.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import 'device_library_screen.dart';

/// La porte vers les vidéos de l'appareil, sur l'écran des téléchargements :
/// c'est là qu'on cherche ce qui se lit sans serveur. Rien sur une plateforme
/// qui n'a pas de dossiers à montrer.
class DeviceLibraryEntryTile extends StatelessWidget {
  const DeviceLibraryEntryTile({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DeviceLibrary.instance.isSupported) return const SizedBox.shrink();
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => openDeviceLibrary(context),
        leading: const Icon(AppIcons.folder, color: AppColors.textPrimary),
        title: Text(tr('Vidéos de cet appareil')),
        subtitle: Text(
          tr('Vos fichiers personnels, lus sans serveur'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.footnote,
          ),
        ),
        trailing: const Icon(AppIcons.chevronRight),
      ),
    );
  }
}

/// La même porte, en lien discret sous le formulaire de connexion : l'app
/// sert dès l'installation, avant qu'un serveur existe.
class DeviceLibraryLoginLink extends StatelessWidget {
  const DeviceLibraryLoginLink({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!DeviceLibrary.instance.isSupported) return const SizedBox.shrink();
    return TextButton(
      onPressed: enabled ? () => openDeviceLibrary(context) : null,
      child: Text(tr('Lire les vidéos de cet appareil')),
    );
  }
}
