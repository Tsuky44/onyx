import 'package:flutter/material.dart';

import '../../providers/auth_provider.dart';
import '../../screens/auth/user_choice_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/tv_link_scanner_screen.dart';
import '../../models/profile_avatar.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../tv/tv_mode.dart';
import '../../utils/app_platform.dart';
import 'glass_chrome.dart';
import 'interface_tour/tour_anchor.dart';
import 'join_watch_party_dialog.dart';
import 'profile_disc.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

/// Single owner of the account menu — consumed by the desktop header, the
/// compact tab bar and the Home overlay bar so all three stay identical.
class AccountMenu extends StatelessWidget {
  final AuthProvider authProvider;

  const AccountMenu({super.key, required this.authProvider});

  @override
  Widget build(BuildContext context) {
    // The entry point is a QR scanner — for a television, a browser or a
    // desktop app (ADR-0020) — so it belongs on the device that holds a camera,
    // which is the phone and only the phone.
    final canLinkTv = AppPlatform.isMobile && !TvScope.of(context);

    // Un seul serveur n'a pas besoin d'un sélecteur ; à partir de deux, c'est
    // le geste le plus fréquent du menu, donc il est là et pas dans les
    // réglages. Voir ADR-0013.
    //
    // Les autres personnes du même serveur passent par « Changer
    // d'utilisateur » (ADR-0078) : ce menu ne liste que les autres serveurs,
    // une fois chacun, quel que soit le nombre de comptes qu'on y a.
    final otherServers =
        authProvider.apiClient.servers.otherServers(authProvider.activeServer);
    final canSwitch = otherServers.isNotEmpty;

    // Sur téléviseur, le menu grandit avec son texte : des lignes plus
    // hautes et un menu plus large, que le thème ne sait pas porter
    // ([AppTheme.menuScaleOf]).
    final scale = AppTheme.menuScaleOf(context);
    final rowHeight =
        scale > 1 ? 40 * scale : kMinInteractiveDimension.toDouble();

    return TourTarget(
      anchor: TourAnchor.account,
      child: PopupMenuButton<String>(
        tooltip: tr('Menu'),
        offset: const Offset(0, 44),
        padding: EdgeInsets.zero,
        constraints: scale > 1
            ? BoxConstraints(minWidth: 150 * scale, maxWidth: 250 * scale)
            : null,
        itemBuilder: (_) => [
          PopupMenuItem(
            enabled: false,
            height: rowHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  authProvider.currentUser?.username ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (authProvider.activeServer != null)
                  Text(
                    // Le rôle, pour qu'un membre sache d'emblée ce qu'il peut
                    // faire sur ce serveur — et pourquoi il ne voit pas les
                    // actions d'administration.
                    '${authProvider.activeServer!.displayName} · '
                    '${authProvider.permissions.isAdmin ? tr('Administrateur') : tr('Membre')}',
                    style: TextStyle(
                      fontSize: AppType.caption * scale,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          if (canSwitch) ...[
            for (final account in otherServers)
              PopupMenuItem(
                value: 'switch:${account.id}',
                height: rowHeight,
                child: _MenuRow(
                  icon: AppIcons.switchServer,
                  label: tr('Passer sur {0}', [account.displayName]),
                ),
              ),
            const PopupMenuDivider(),
          ],
          PopupMenuItem(
            value: 'users',
            height: rowHeight,
            child: _MenuRow(
              icon: AppIcons.switchUser,
              label: tr('Changer d’utilisateur'),
            ),
          ),
          PopupMenuItem(
            value: 'watch-party',
            height: rowHeight,
            child: _MenuRow(
              icon: AppIcons.watchParty,
              label: tr('Rejoindre une séance'),
            ),
          ),
          const PopupMenuDivider(),
          // « Serveurs » a quitté ce menu : il ouvrait les mêmes Paramètres sur
          // une autre section.
          PopupMenuItem(
            value: 'settings',
            height: rowHeight,
            child: _MenuRow(icon: AppIcons.settings, label: tr('Paramètres')),
          ),
          if (canLinkTv)
            PopupMenuItem(
              value: 'tv',
              height: rowHeight,
              child: _MenuRow(
                icon: AppIcons.scan,
                label: tr('Connecter un appareil'),
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'logout',
            height: rowHeight,
            child:
                _MenuRow(icon: AppIcons.signOut, label: tr('Se déconnecter')),
          ),
        ],
        onSelected: (value) async {
          if (value.startsWith('switch:')) {
            final id = value.substring('switch:'.length);
            // Plusieurs personnes là-bas : on arrive sur « Qui regarde ? »
            // plutôt que dans la session de la première venue.
            if (authProvider.apiClient.servers.usersOf(id).length > 1) {
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                builder: (_) => UserChoiceScreen(serverAccountId: id),
              ));
              return;
            }
            await authProvider.switchServer(id);
            return;
          }
          switch (value) {
            case 'users':
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const UserChoiceScreen()),
              );
            case 'watch-party':
              await showJoinWatchPartyDialog(context,
                  authProvider: authProvider);
            case 'settings':
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            case 'tv':
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const TvLinkScannerScreen()),
              );
            case 'logout':
              authProvider.logout();
          }
        },
        child: GlassIconButton(
          size: 34,
          child: _avatarOrInitial(),
        ),
      ),
    );
  }

  /// L'image de profil quand la personne en a choisi une, sinon son initiale
  /// sur le verre du header, comme avant (ADR-0078).
  Widget _avatarOrInitial() {
    final active = authProvider.activeServer;
    if (active != null &&
        ProfileAvatar.parse(active.avatar) is! InitialAvatar) {
      return ClipOval(child: ProfileDisc(account: active, size: 32));
    }
    return Text(
      (authProvider.currentUser?.username ?? '?')[0].toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: AppType.subhead,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// Une entrée du menu : une icône et son libellé. 16 px d'icône, à l'échelle
/// des menus de l'appareil ([AppTheme.menuScaleOf]) : sur téléviseur, le texte
/// grandissait seul et l'icône restait un point à côté de lui.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.menuScaleOf(context);
    return Row(
      children: [
        Icon(icon, size: 16 * scale),
        SizedBox(width: 8 * scale),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
