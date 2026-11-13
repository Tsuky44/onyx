import 'package:flutter/material.dart';

import '../../models/server_account.dart';
import '../../providers/auth_provider.dart';
import 'add_user_screen.dart';

/// Ajoute quelqu'un sur [server], une session déjà ouverte, puis passe sur
/// son compte : c'est pour lui qu'on vient de l'ajouter. Rend vrai quand la
/// session est désormais la sienne.
///
/// Partagé par « Qui regarde ? » et la pastille « Ajouter » du menu du compte.
/// Le lancement, sans session, a son propre chemin (`chooseUser`).
Future<bool> addUserAndSwitch(
  NavigatorState navigator,
  AuthProvider auth,
  ServerAccount server,
) async {
  final before = auth.activeServer?.id;
  final added = await navigator.push<ServerAccount>(
    MaterialPageRoute(builder: (_) => AddUserScreen(server: server)),
  );
  // Le téléphone ouvre la session et la rend active ; le mot de passe
  // l'ajoute sans basculer, pour ne pas déplacer un écran qu'on regarde.
  if (auth.activeServer?.id != before) return true;
  return added != null && await auth.switchServer(added.id);
}
