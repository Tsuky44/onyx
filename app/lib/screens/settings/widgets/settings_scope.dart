import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';

/// À qui un réglage s'applique : la question qu'on se pose avant de chercher
/// où il est (ADR-0100).
enum SettingsScope {
  /// Suit le compte sur tous ses appareils.
  account(Icons.person_outline_rounded),

  /// Reste sur cet appareil : son matériel, son réseau, son disque.
  device(Icons.devices_rounded),

  /// Vaut pour tous les comptes du serveur.
  server(Icons.dns_outlined);

  const SettingsScope(this.icon);

  final IconData icon;

  String get label => switch (this) {
        account => tr('Suit votre compte'),
        device => tr('Propre à cet appareil'),
        server => tr('Pour tout le serveur'),
      };
}

/// L'intertitre qui dit la portée des groupes qui le suivent. Utilisé là où une
/// même page mélange des portées (Lecture) ; une page d'une seule portée la
/// dit dans sa description.
class SettingsScopeHeading extends StatelessWidget {
  const SettingsScopeHeading(this.scope, {super.key});

  final SettingsScope scope;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
      child: Row(
        children: [
          Icon(scope.icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            scope.label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
