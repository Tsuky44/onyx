import '../../../l10n/tr.dart';
import '../../../models/models.dart';

/// Les droits d'administration, dans l'ordre où on les montre.
const permissionLabels = <(String, String)>[
  ('manage_settings', 'Gérer les paramètres du serveur'),
  ('manage_library', 'Gérer la bibliothèque (scans, métadonnées)'),
  ('manage_users', 'Gérer les utilisateurs'),
  ('delete_media', 'Supprimer des médias'),
  ('invite_users', 'Créer des invitations'),
  ('request_media', 'Demander des médias'),
  ('share_media', 'Partager des médias par lien public'),
];

bool readPermission(Permissions p, String key) => p.toJson()[key] == true;

Permissions writePermission(Permissions p, String key, bool value) {
  switch (key) {
    case 'manage_settings':
      return p.copyWith(manageSettings: value);
    case 'manage_library':
      return p.copyWith(manageLibrary: value);
    case 'manage_users':
      return p.copyWith(manageUsers: value);
    case 'delete_media':
      return p.copyWith(deleteMedia: value);
    case 'invite_users':
      return p.copyWith(inviteUsers: value);
    case 'request_media':
      return p.copyWith(requestMedia: value);
    case 'share_media':
      return p.copyWith(shareMedia: value);
  }
  return p;
}

/// Les droits d'un compte en une ligne : « Administrateur », deux droits au
/// plus en toutes lettres, sinon leur nombre.
String permissionsSummary(Permissions p) {
  if (p.isAdmin) return tr('Administrateur');
  final granted = permissionLabels
      .where((entry) => readPermission(p, entry.$1))
      .map((entry) => tr(entry.$2))
      .toList();
  if (granted.isEmpty) return tr('Aucun droit');
  if (granted.length <= 2) return granted.join(' · ');
  return '${granted.length} droits';
}
