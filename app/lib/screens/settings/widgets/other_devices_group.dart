import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/store_build.dart';
import '../pages/apps_page.dart';
import '../tv_link_scanner_screen.dart';
import 'settings_ui.dart';

/// Brancher un autre écran sur ce compte, ou y installer Onyx.
///
/// Il est dans « Mon compte », à côté des appareils déjà connectés : tout ce
/// qui touche aux appareils d'un compte se règle au même endroit.
class OtherDevicesGroup extends StatelessWidget {
  const OtherDevicesGroup({super.key});

  // Le lien se fait en scannant le code affiché par l'autre écran
  // (téléviseur, navigateur, ordinateur) : il faut une caméra, donc un
  // téléphone.
  static bool _canLink(BuildContext context) =>
      AppPlatform.isMobile && !TvScope.of(context);

  // Une Apple TV n'ouvre pas de lien et ne choisit pas de fichier : ni
  // installer ailleurs, ni publier un installeur n'y a de sens. Un build
  // store ne propose pas d'installeurs non plus (ADR-0046).
  static bool get _canInstall => !AppPlatform.isTvOS && !StoreBuild.enabled;

  @override
  Widget build(BuildContext context) {
    final canLink = _canLink(context);
    if (!canLink && !_canInstall) return const SizedBox.shrink();

    return SettingsGroup(
      title: tr('Ajouter un appareil'),
      children: [
        if (canLink)
          SettingsTile(
            icon: Icons.qr_code_scanner_rounded,
            iconColor: AppColors.primary,
            title: tr('Connecter un appareil'),
            subtitle: tr('Scannez le code QR affiché par Onyx sur un '
                'téléviseur, un ordinateur ou un navigateur : il se '
                'connecte à votre compte, sans mot de passe.'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TvLinkScannerScreen()),
            ),
          ),
        if (_canInstall)
          SettingsTile(
            icon: Icons.download_for_offline_rounded,
            title: tr('Installer Onyx sur un autre appareil'),
            subtitle: tr('Les installeurs servis par votre serveur.'),
            onTap: () => pushSettingsSubpage(
              context,
              title: tr('Applications'),
              builder: (_) => const AppsPage(),
            ),
          ),
      ],
    );
  }
}
