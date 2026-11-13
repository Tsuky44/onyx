import 'package:flutter/material.dart';

import '../../providers/auth_provider.dart';
import '../../screens/auth/add_user_flow.dart';
import '../../screens/auth/user_choice_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/tv_link_scanner_screen.dart';
import '../../models/profile_avatar.dart';
import '../../theme/app_colors.dart';
import '../../tv/tv_mode.dart';
import '../../utils/app_platform.dart';
import 'account_menu_panel.dart';
import 'account_menu_route.dart';
import 'glass_chrome.dart';
import 'interface_tour/tour_anchor.dart';
import 'join_watch_party_dialog.dart';
import 'profile_disc.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

/// Single owner of the account menu — consumed by the desktop header, the
/// compact tab bar and the Home overlay bar so all three stay identical.
///
/// Le menu met les personnes du serveur en tête (design « profils en tête »,
/// choisi le 2026-11-13) : changer de personne se fait en un geste, sans
/// passer par « Qui regarde ? ». Voir [AccountMenuPanel].
class AccountMenu extends StatefulWidget {
  final AuthProvider authProvider;

  const AccountMenu({super.key, required this.authProvider});

  @override
  State<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  final GlobalKey _anchorKey = GlobalKey();

  AuthProvider get authProvider => widget.authProvider;

  Future<void> _open() async {
    final auth = authProvider;
    final active = auth.activeServer;
    // The entry point is a QR scanner — for a television, a browser or a
    // desktop app (ADR-0020) — so it belongs on the device that holds a
    // camera, which is the phone and only the phone.
    final canLinkTv = AppPlatform.isMobile && !TvScope.of(context);

    final choice = await showAccountMenu(
      context: context,
      anchorKey: _anchorKey,
      panel: (scale, pick) => AccountMenuPanel(
        profiles: auth.usersOnActiveServer,
        current: active,
        // Le rôle, pour qu'un membre sache d'emblée ce qu'il peut faire sur
        // ce serveur — et pourquoi il ne voit pas les actions
        // d'administration.
        serverLabel: active == null
            ? null
            : '${active.displayName} · '
                '${auth.permissions.isAdmin ? tr('Administrateur') : tr('Membre')}',
        // Les autres personnes du même serveur sont dans la rangée
        // (ADR-0078) : ce menu ne liste que les autres serveurs, une fois
        // chacun, quel que soit le nombre de comptes qu'on y a.
        otherServers: auth.apiClient.servers.otherServers(active),
        canAddProfile: active != null,
        canLinkDevice: canLinkTv,
        scale: scale,
        onChoice: pick,
      ),
    );
    if (choice == null || !mounted) return;
    await _handle(choice);
  }

  Future<void> _handle(AccountMenuChoice choice) async {
    final auth = authProvider;
    final navigator = Navigator.of(context, rootNavigator: true);
    switch (choice) {
      case AccountMenuProfile(:final account):
        if (account.id == auth.activeServer?.id) return;
        final ok = await auth.switchServer(account.id);
        if (ok || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.errorMessage ?? tr('Bascule impossible.')),
          backgroundColor: AppColors.error,
        ));
      case AccountMenuServer(:final account):
        // Plusieurs personnes là-bas : on arrive sur « Qui regarde ? »
        // plutôt que dans la session de la première venue.
        if (auth.apiClient.servers.usersOf(account.id).length > 1) {
          navigator.push(MaterialPageRoute(
            builder: (_) => UserChoiceScreen(serverAccountId: account.id),
          ));
          return;
        }
        await auth.switchServer(account.id);
      case AccountMenuAction.addProfile:
        final server = auth.activeServer;
        if (server != null) await addUserAndSwitch(navigator, auth, server);
      case AccountMenuAction.manageProfiles:
        navigator.push(
          MaterialPageRoute(builder: (_) => const UserChoiceScreen()),
        );
      case AccountMenuAction.watchParty:
        await showJoinWatchPartyDialog(context, authProvider: auth);
      // « Serveurs » a quitté ce menu : il ouvrait les mêmes Paramètres sur
      // une autre section.
      case AccountMenuAction.settings:
        navigator.push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      case AccountMenuAction.linkDevice:
        navigator.push(
          MaterialPageRoute(builder: (_) => const TvLinkScannerScreen()),
        );
      case AccountMenuAction.signOut:
        auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TourTarget(
      anchor: TourAnchor.account,
      child: Tooltip(
        message: tr('Menu'),
        child: GlassIconButton(
          key: _anchorKey,
          size: 34,
          onTap: _open,
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
