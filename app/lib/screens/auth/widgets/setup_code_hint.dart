import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';

/// Sous le champ « Code d'installation » : où lire ce code. Le serveur l'écrit
/// dans son journal, que `docker logs` affiche (ADR-0165).
class SetupCodeHint extends StatelessWidget {
  const SetupCodeHint({super.key});

  /// Le nom du conteneur du docker-compose du dépôt.
  static const String command = 'docker logs onyx-server';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          tr('Pour lire le code, tapez cette commande sur la machine du '
              'serveur :'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.footnote,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SelectableText(
            command,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: AppType.footnote,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
