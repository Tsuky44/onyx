import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../access_requests_section.dart';
import '../user_admin_sections.dart';
import '../widgets/settings_ui.dart';
import '../../../l10n/tr.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final perms = context.watch<AuthProvider>().permissions;

    return SettingsPage(
      title: tr('Utilisateurs'),
      description: perms.manageUsers
          ? tr('Les comptes du serveur et leurs droits, les personnes qui '
              'demandent un accès et les liens d’invitation.')
          : tr('Les personnes qui demandent un accès et vos liens d’invitation.'),
      children: [
        if (perms.manageUsers) const UsersSection(),
        // Un inviteur sans manage_users voit aussi cette section — et seulement
        // ses propres liens.
        const AccessRequestsSection(),
        const InvitationsSection(),
      ],
    );
  }
}
