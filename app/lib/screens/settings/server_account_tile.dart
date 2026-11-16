import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/server_account.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../widgets/global/onyx_menu.dart';
import 'server_account_subtitle.dart';
import 'widgets/settings_ui.dart';

enum _AccountAction { primary, link, unlink, rename, forget }

/// Un compte de la liste « Mes serveurs » : son serveur, son état (actif,
/// principal, lié) et le menu de ses options.
///
/// Une ligne de réglages comme les autres : la liste est un [SettingsGroup],
/// qui apporte la carte et les filets. Le serveur actif se reconnaît à sa coche
/// et à son avatar teinté.
class ServerAccountTile extends StatelessWidget {
  const ServerAccountTile({
    super.key,
    required this.account,
    required this.isActive,
    required this.isPrimary,
    required this.busy,
    required this.onSelect,
    required this.onTogglePrimary,
    required this.onRename,
    required this.links,
    required this.onLink,
    required this.onUnlink,
    required this.onForget,
  });

  final ServerAccount account;
  final bool isActive;

  /// Celui sur lequel l'app redémarre, marqué d'une étoile.
  final bool isPrimary;

  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onTogglePrimary;
  final VoidCallback onRename;
  final List<AccountLink> links;
  final VoidCallback? onLink;
  final VoidCallback onUnlink;
  final VoidCallback? onForget;

  void _run(_AccountAction action) {
    switch (action) {
      case _AccountAction.primary:
        onTogglePrimary();
      case _AccountAction.link:
        onLink?.call();
      case _AccountAction.unlink:
        onUnlink();
      case _AccountAction.rename:
        onRename();
      case _AccountAction.forget:
        onForget?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      onTap: isActive || busy ? null : onSelect,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: isActive ? 0.28 : 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isActive ? AppIcons.check : AppIcons.switchServer,
          size: 18,
          color: AppColors.textPrimary,
        ),
      ),
      title: account.displayName,
      subtitle: serverAccountSubtitle(account,
          isActive: isActive, isPrimary: isPrimary, links: links),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPrimary)
            const Icon(AppIcons.rating, size: 16, color: AppColors.warning),
          OnyxMenuButton<_AccountAction>(
            tooltip: tr('Options du compte {0}', [account.username]),
            icon: AppIcons.moreVertical,
            enabled: !busy,
            items: [
              OnyxMenuItem(
                value: _AccountAction.primary,
                label: isPrimary
                    ? tr('Ne plus démarrer ici')
                    : tr('Démarrer sur ce serveur'),
                icon: isPrimary ? AppIcons.ratingOutline : AppIcons.rating,
              ),
              if (onLink != null)
                OnyxMenuItem(
                  value: _AccountAction.link,
                  label: tr('Lier un compte'),
                  icon: AppIcons.link,
                ),
              if (links.isNotEmpty)
                OnyxMenuItem(
                  value: _AccountAction.unlink,
                  label: tr('Dissocier ce compte'),
                  icon: AppIcons.blocked,
                ),
              OnyxMenuItem(
                value: _AccountAction.rename,
                label: tr('Renommer'),
                icon: AppIcons.edit,
              ),
              if (onForget != null)
                OnyxMenuItem(
                  value: _AccountAction.forget,
                  label: tr('Retirer de cet appareil'),
                  icon: AppIcons.delete,
                  destructive: true,
                ),
            ],
            onSelected: _run,
          ),
        ],
      ),
    );
  }
}
