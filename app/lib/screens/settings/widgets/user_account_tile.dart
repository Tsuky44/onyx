import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../widgets/global/onyx_menu.dart';
import 'settings_ui.dart';
import 'user_rights.dart';

/// Ce qu'on peut faire d'un compte depuis la liste.
enum UserAction { permissions, password, otp, transfer, delete }

/// Une ligne de la liste des comptes : l'avatar carré, le nom, ses droits en
/// clair, une pastille de rôle et le menu de ses actions.
///
/// Les règles de droits vivent ici, au même endroit que le menu qu'elles
/// filtrent : seul le propriétaire touche au propriétaire, et personne ne se
/// supprime soi-même.
class UserAccountTile extends StatelessWidget {
  const UserAccountTile({
    super.key,
    required this.user,
    required this.isMe,
    required this.viewerIsOwner,
    required this.onAction,
  });

  final User user;
  final bool isMe;
  final bool viewerIsOwner;
  final ValueChanged<UserAction> onAction;

  /// Les actions que le spectateur a le droit d'engager sur ce compte, dans
  /// l'ordre du menu. Vide : le compte est celui du propriétaire et on ne l'est
  /// pas.
  static List<UserAction> actionsFor(
    User user, {
    required bool isMe,
    required bool viewerIsOwner,
  }) {
    final mayTouch = !user.isOwner || viewerIsOwner;
    return [
      if (mayTouch) UserAction.permissions,
      if (mayTouch) UserAction.password,
      if (user.otpEnabled && mayTouch) UserAction.otp,
      if (viewerIsOwner && !user.isOwner) UserAction.transfer,
      if (!user.isOwner && !isMe) UserAction.delete,
    ];
  }

  String _label(UserAction action) => switch (action) {
        UserAction.permissions => tr('Modifier les droits'),
        UserAction.password => tr('Réinitialiser le mot de passe'),
        UserAction.otp => tr('Réinitialiser la validation en deux étapes'),
        UserAction.transfer => tr('Transférer la propriété'),
        UserAction.delete => tr('Supprimer le compte'),
      };

  IconData _icon(UserAction action) => switch (action) {
        UserAction.permissions => AppIcons.settings,
        UserAction.password => AppIcons.edit,
        UserAction.otp => AppIcons.reset,
        UserAction.transfer => AppIcons.switchUser,
        UserAction.delete => AppIcons.delete,
      };

  @override
  Widget build(BuildContext context) {
    final actions =
        actionsFor(user, isMe: isMe, viewerIsOwner: viewerIsOwner);
    return SettingsTile(
      leading: UserAvatar(user.username, size: 34, rounded: true),
      title: user.username,
      subtitle: [
        permissionsSummary(user.permissions),
        if (user.otpEnabled) tr('Validation en deux étapes'),
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user.isOwner)
            SettingsPill(tr('Propriétaire'), color: AppColors.primary),
          if (isMe) ...[
            if (user.isOwner) const SizedBox(width: 6),
            SettingsPill(tr('Vous')),
          ],
          if (actions.isNotEmpty)
            OnyxMenuButton<UserAction>(
              tooltip: tr('Actions pour {0}', [user.username]),
              icon: AppIcons.moreVertical,
              items: [
                for (final action in actions)
                  OnyxMenuItem(
                    value: action,
                    label: _label(action),
                    icon: _icon(action),
                    destructive: action == UserAction.delete,
                  ),
              ],
              onSelected: onAction,
            ),
        ],
      ),
    );
  }
}
