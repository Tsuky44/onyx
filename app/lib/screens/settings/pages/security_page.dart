import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../otp_policy_group.dart';
import '../widgets/settings_ui.dart';

/// Les règles de connexion que le serveur impose à tous ses comptes.
///
/// La politique de validation en deux étapes était dans « Utilisateurs », à
/// côté de la liste des comptes ; c'est un réglage du serveur, elle rejoint
/// les autres (ADR-0100). Le code de chaque compte reste dans « Mon compte ».
class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: tr('Sécurité'),
      description: tr('Ce que le serveur exige de chaque compte pour se '
          'connecter.'),
      children: const [OtpPolicyGroup()],
    );
  }
}
