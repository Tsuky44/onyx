import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../tv/tv_navigation_sound.dart';
import 'settings_ui.dart';

/// Le réglage des sons de navigation de l'Apple TV (ADR
/// `2026-11-23-fytroz-sons-de-navigation-apple-tv`).
///
/// tvOS a son propre réglage (Vidéo et audio, Clics de navigation), mais une
/// app ne peut pas le lire : Onyx, qui rejoue ces sons lui-même, ne saurait
/// pas qu'on les a coupés. Celui-ci est donc le sien, activé par défaut.
///
/// À ne monter que là où [TvNavigationSound.supported] est vrai.
class NavigationSoundTile extends StatefulWidget {
  const NavigationSoundTile({super.key});

  @override
  State<NavigationSoundTile> createState() => _NavigationSoundTileState();
}

class _NavigationSoundTileState extends State<NavigationSoundTile> {
  @override
  Widget build(BuildContext context) {
    return SettingsSwitchTile(
      icon: Icons.volume_up_rounded,
      title: tr('Sons de navigation'),
      subtitle: tr('Le clic de l’Apple TV quand vous vous déplacez dans les '
          'menus, ouvrez une page ou revenez en arrière. Jamais pendant une '
          'lecture.'),
      value: TvNavigationSound.enabled,
      onChanged: (value) async {
        await TvNavigationSound.setEnabled(value);
        if (mounted) setState(() {});
      },
    );
  }
}
