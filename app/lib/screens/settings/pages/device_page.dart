import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/new_episodes/new_episode_alerts.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/app_platform.dart';
import 'logs_page.dart';
import '../widgets/about_group.dart';
import '../widgets/lite_mode_tile.dart';
import '../widgets/new_episode_alerts_group.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/global/interface_tour/interface_tour.dart';
import '../../../widgets/global/resume_preview/hover_preview_preference.dart';
import '../widgets/settings_ui.dart';
import '../../../l10n/app_language.dart';
import '../../../l10n/tr.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context);
    final detected = TvMode.detected ? tr('un téléviseur') : tr('un appareil tactile');
    return SettingsPage(
      title: tr('Cet appareil'),
      description:
          tr('La langue, l’affichage et les notifications de cet appareil, '
              'et de l’aide si quelque chose ne va pas. Ces réglages ne '
              'suivent pas votre compte.'),
      children: [
        SettingsGroup(
          title: tr('Affichage'),
          children: [
            // Sur une Apple TV le mode télécommande est le seul possible :
            // rien à régler (voir [TvMode]).
            if (!AppPlatform.isTvOS)
              SettingsChoiceTile<TvModePreference>(
                icon: Icons.settings_remote_rounded,
                title: tr('Mode télécommande'),
                subtitle:
                    tr('Interface pensée pour un téléviseur et une '
                        'télécommande. Cet appareil est détecté comme {0}.', [detected]),
                value: TvMode.preference,
                options: [
                  (TvModePreference.auto, tr('Auto')),
                  (TvModePreference.on, tr('Activé')),
                  (TvModePreference.off, tr('Désactivé')),
                ],
                onChanged: (value) async {
                  await TvMode.setPreference(value);
                  if (mounted) setState(() {});
                },
              ),
            const LiteModeTile(),
          ],
        ),
        SettingsGroup(
          title: tr('Langue'),
          children: [
            SettingsChoiceTile<AppLanguage?>(
              icon: Icons.translate_rounded,
              title: tr('Langue de l’interface'),
              subtitle: tr('« Auto » suit la langue de cet appareil.'),
              value: AppLanguage.chosen,
              options: [
                (null, tr('Auto')),
                for (final language in AppLanguage.values)
                  (language, language.nativeName),
              ],
              onChanged: AppLanguage.choose,
            ),
          ],
        ),
        if (NewEpisodeAlerts.supported) const NewEpisodeAlertsGroup(),
        // Hors ligne il n'y a que les téléchargements à l'écran : la
        // présentation n'aurait rien de ce qu'elle décrit à montrer.
        if (!context.watch<AuthProvider>().isOfflineSession)
          SettingsGroup(
            title: tr('Interface'),
            children: [
              SettingsTile(
                icon: Icons.explore_outlined,
                title: tr('Revoir la présentation'),
                subtitle: tr('Rejoue le tour de l’accueil et de la '
                    'navigation.'),
                onTap: () {
                  Navigator.of(context, rootNavigator: true)
                      .popUntil((route) => route.isFirst);
                  InterfaceTourReplay.request();
                },
              ),
              if (HoverPreviewPreference.supported && !isTv)
                SettingsSwitchTile(
                  icon: Icons.slideshow_rounded,
                  title: tr('Aperçu au survol'),
                  subtitle: tr('Laisser la souris sur une carte de « Reprendre » '
                      'l’agrandit avec des images de là où vous vous êtes '
                      'arrêté et le résumé.'),
                  value: HoverPreviewPreference.enabled,
                  onChanged: (value) async {
                    await HoverPreviewPreference.setEnabled(value);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        SettingsGroup(
          title: tr('Aide'),
          children: [
            SettingsTile(
              icon: Icons.receipt_long_rounded,
              title: tr('Journal'),
              subtitle: tr('Journaux de l’app et des lectures, pour comprendre '
                  'une erreur'),
              onTap: () => pushSettingsSubpage(
                context,
                title: tr('Journal'),
                builder: (_) => const LogsPage(),
              ),
            ),
          ],
        ),
        const AboutGroup(),
      ],
    );
  }
}
