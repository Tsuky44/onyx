import 'package:material_ui/material_ui.dart';

import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/retro_provider.dart';
import '../../screens/retro/home/retro_ring.dart';
import '../../screens/retro/retro_screen.dart';
import '../../screens/auth/add_user_flow.dart';
import '../../screens/auth/server_switcher_screen.dart';
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
import 'onyx_dialog.dart';
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

  /// Le compte de la barre du haut du téléphone (ADR-0144) : un disque
  /// plein, sans verre, posé sur le noir où l'affiche se fond.
  final bool plain;

  /// La cible du disque [plain] : les 44 points qu'Apple demande.
  static const double plainTarget = 44;

  /// Le diamètre du disque [plain].
  static const double plainSize = 36;

  const AccountMenu({
    super.key,
    required this.authProvider,
    this.plain = false,
  });

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
    // Nul hors saison, sous le seuil, ou sans le provider (un test qui monte
    // le menu seul).
    final retro = Provider.of<RetroProvider?>(context, listen: false);
    final retroYear =
        retro != null && retro.available ? retro.status?.year : null;

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
        canAddProfile: active != null,
        canLinkDevice: canLinkTv,
        retroYear: retroYear,
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
      case AccountMenuAction.addProfile:
        final server = auth.activeServer;
        if (server != null) await addUserAndSwitch(navigator, auth, server);
      case AccountMenuAction.retro:
        final year = context.read<RetroProvider>().status?.year;
        if (year != null) await RetroScreen.open(navigator.context, year);
      case AccountMenuAction.manageProfiles:
        navigator.push(
          MaterialPageRoute(builder: (_) => const UserChoiceScreen()),
        );
      case AccountMenuAction.manageServers:
        navigator.push(
          MaterialPageRoute(builder: (_) => const ServerSwitcherScreen()),
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
        if (!await confirmSignOut(context) || !mounted) return;
        await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tant que le Rétro n'a pas été ouvert, un anneau autour de l'avatar dit
    // qu'il attend (ADR 2026-11-26-tsuky-retro-annuel).
    final ringed = Provider.of<RetroProvider?>(context)?.showsRing ?? false;
    return TourTarget(
      anchor: TourAnchor.account,
      child: Tooltip(
        message: ringed ? tr('Menu · ton Rétro est prêt') : tr('Menu'),
        child: RetroRing(
          active: ringed,
          diameter: (widget.plain ? AccountMenu.plainSize : 34) + 7,
          child: widget.plain
              ? _buildPlain()
              : GlassIconButton(
                  key: _anchorKey,
                  size: 34,
                  onTap: _open,
                  child: _avatarOrInitial(32),
                ),
        ),
      ),
    );
  }

  Widget _buildPlain() {
    return SizedBox.square(
      key: _anchorKey,
      dimension: AccountMenu.plainTarget,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _open,
          child: Center(
            child: Container(
              key: const ValueKey('account-plain-disc'),
              width: AccountMenu.plainSize,
              height: AccountMenu.plainSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.border,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: _avatarOrInitial(AccountMenu.plainSize),
            ),
          ),
        ),
      ),
    );
  }

  /// L'image de profil quand la personne en a choisi une, sinon son initiale
  /// sur le verre du header, comme avant (ADR-0078).
  Widget _avatarOrInitial(double size) {
    final active = authProvider.activeServer;
    if (active != null &&
        ProfileAvatar.parse(active.avatar) is! InitialAvatar) {
      return ClipOval(child: ProfileDisc(account: active, size: size));
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
