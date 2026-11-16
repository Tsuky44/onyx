import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../widgets/global/onyx_dialog.dart';
import 'widgets/admin_prompts.dart';
import 'widgets/permissions_sheet.dart';
import 'widgets/settings_ui.dart';
import 'widgets/user_account_tile.dart';

export 'widgets/admin_prompts.dart' show promptPassword;
export 'widgets/user_rights.dart';

/// Accounts list with their rights. Only rendered for holders of manage_users.
///
/// Rend son propre groupe : le compte du titre (« Comptes · 4 ») vient de la
/// liste chargée.
class UsersSection extends StatefulWidget {
  const UsersSection({super.key});

  @override
  State<UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<UsersSection> {
  List<User> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await context.read<ApiClient>().getUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = adminErrorText(e);
      });
      // Rights may have been taken away while this screen was open.
      context.read<AuthProvider>().refreshProfile();
    }
  }

  Future<void> _editPermissions(User user) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => PermissionsSheet(user: user),
    );
    if (saved == true) _load();
  }

  Future<void> _resetPassword(User user) async {
    final password = await promptNewPassword(
      context,
      title: tr('Réinitialiser le mot de passe de {0}', [user.username]),
      // Reset is a recovery, so it logs that account out everywhere.
      hint: tr('Les sessions ouvertes de ce compte seront fermées.'),
    );
    if (password == null || !mounted) return;
    try {
      await context.read<ApiClient>().resetUserPassword(user.id, password);
      if (!mounted) return;
      _toast(tr('Mot de passe réinitialisé.'));
    } catch (e) {
      _toast(adminErrorText(e), error: true);
    }
  }

  /// Retire le code d'un compte qui a perdu son téléphone et ses codes de
  /// secours (ADR-0041).
  Future<void> _resetOtp(User user) async {
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Réinitialiser la validation en deux étapes de {0} ?',
          [user.username]),
      message: tr('Son mot de passe suffira à sa prochaine connexion. Si la '
          'politique du serveur l’impose, il devra alors configurer un '
          'nouveau code.'),
      confirmLabel: tr('Réinitialiser'),
      icon: AppIcons.reset,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<ApiClient>().resetUserOtp(user.id);
      if (!mounted) return;
      _toast(tr('Validation en deux étapes réinitialisée.'));
      _load();
    } catch (e) {
      _toast(adminErrorText(e), error: true);
    }
  }

  Future<void> _delete(User user) async {
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Supprimer {0} ?', [user.username]),
      message: tr('Le compte et toutes ses données (progressions, sessions) '
          'seront supprimés définitivement.'),
      confirmLabel: tr('Supprimer'),
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<ApiClient>().deleteUser(user.id);
      _load();
    } catch (e) {
      _toast(adminErrorText(e), error: true);
    }
  }

  Future<void> _transferOwnership(User user) async {
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Transférer la propriété à {0} ?', [user.username]),
      message: tr('Vous ne serez plus propriétaire : ce compte pourra alors '
          'modifier vos droits, et vous ne pourrez plus modifier les '
          'siens.'),
      confirmLabel: tr('Transférer'),
      icon: AppIcons.switchUser,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<ApiClient>().transferOwnership(user.id);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshProfile();
      _load();
    } catch (e) {
      _toast(adminErrorText(e), error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showSettingsSnack(context, message, error: error);
  }

  void _run(User user, UserAction action) => switch (action) {
        UserAction.permissions => _editPermissions(user),
        UserAction.password => _resetPassword(user),
        UserAction.otp => _resetOtp(user),
        UserAction.transfer => _transferOwnership(user),
        UserAction.delete => _delete(user),
      };

  @override
  Widget build(BuildContext context) {
    final footer = tr('Le propriétaire ne peut pas être rétrogradé. '
        'Réinitialiser un mot de passe déconnecte tous les '
        'appareils du compte.');
    if (_loading) {
      return SettingsGroup(
        title: tr('Comptes'),
        footer: footer,
        padded: true,
        children: const [SettingsLoading()],
      );
    }
    if (_error != null) {
      return SettingsGroup(
        title: tr('Comptes'),
        padded: true,
        children: [SettingsBanner(_error!, tone: BannerTone.error)],
      );
    }

    final auth = context.watch<AuthProvider>();
    final meId = auth.currentUser?.id;

    return SettingsGroup(
      title: tr('Comptes · {0}', [_users.length]),
      footer: footer,
      children: [
        for (final user in _users)
          UserAccountTile(
            user: user,
            isMe: user.id == meId,
            viewerIsOwner: auth.isOwner,
            onAction: (action) => _run(user, action),
          ),
      ],
    );
  }
}

/// Invitation links. Visible to anyone holding invite_users; an administrator
/// sees every link, an inviter sees only their own.
class InvitationsSection extends StatefulWidget {
  const InvitationsSection({super.key});

  @override
  State<InvitationsSection> createState() => _InvitationsSectionState();
}

class _InvitationsSectionState extends State<InvitationsSection> {
  List<Invitation> _invitations = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invitations = await context.read<ApiClient>().getInvitations();
      if (!mounted) return;
      setState(() {
        _invitations = invitations;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = adminErrorText(e);
      });
      context.read<AuthProvider>().refreshProfile();
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final invitation = await context.read<ApiClient>().createInvitation();
      if (!mounted) return;
      setState(() => _creating = false);
      _showLink(invitation);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      _toast(adminErrorText(e), error: true);
    }
  }

  /// Shows the link and the raw code together. The link is built from the
  /// address this client uses, which may be LAN-only; the code always works,
  /// and on the native apps it is the only way in.
  void _showLink(Invitation invitation) {
    final link = context.read<ApiClient>().invitationLink(invitation);
    showOnyxDialog<void>(
      context: context,
      builder: (ctx) => OnyxDialog(
        title: tr('Invitation créée'),
        icon: AppIcons.link,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Lien (navigateur, même réseau que cette adresse) :')),
            const SizedBox(height: 4),
            SelectableText(link,
                style: const TextStyle(fontSize: AppType.footnote)),
            const SizedBox(height: 16),
            Text(tr('Code (à saisir dans l’app) :')),
            const SizedBox(height: 4),
            SelectableText(invitation.token,
                style: const TextStyle(fontSize: AppType.footnote)),
            const SizedBox(height: 16),
            Text(
              tr('Valable 7 jours, utilisable une seule fois.'),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: AppType.footnote),
            ),
          ],
        ),
        actions: [
          OnyxDialogAction(
            label: tr('Copier le code'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invitation.token));
              Navigator.of(ctx).pop();
              _toast(tr('Code copié.'));
            },
          ),
          OnyxDialogAction(
            label: tr('Copier le lien'),
            primary: true,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.of(ctx).pop();
              _toast(tr('Lien copié.'));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(Invitation invitation) async {
    try {
      await context.read<ApiClient>().revokeInvitation(invitation.token);
      _load();
    } catch (e) {
      _toast(adminErrorText(e), error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showSettingsSnack(context, message, error: error);
  }

  String _statusLabel(Invitation invitation) {
    switch (invitation.status) {
      case 'used':
        return invitation.usedBy.isEmpty
            ? tr('Utilisée')
            : tr('Utilisée par {0}', [invitation.usedBy]);
      case 'revoked':
        return tr('Révoquée');
      case 'expired':
        return tr('Expirée');
      default:
        final expires = invitation.expiresAt;
        if (expires == null) return tr('En attente');
        final days = expires.difference(DateTime.now()).inDays;
        return days <= 0
            ? tr('Expire aujourd’hui')
            : tr('Expire dans {0} j', [days]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = tr('Invitations');
    final footer = tr('Liens à usage unique, valables 7 jours. Les droits '
        'accordés sont fixés par un administrateur.');
    if (_loading) {
      return SettingsGroup(
        title: title,
        footer: footer,
        padded: true,
        children: const [SettingsLoading()],
      );
    }

    final isAdmin = context.watch<AuthProvider>().permissions.manageUsers;

    return SettingsGroup(
      title: title,
      footer: footer,
      trailing: TextButton(
        onPressed: _creating ? null : _create,
        child: Text(_creating ? tr('Création…') : tr('Générer une invitation')),
      ),
      children: [
        if (_error != null)
          SettingsBanner(_error!, tone: BannerTone.error)
        else if (_invitations.isEmpty)
          SettingsEmptyNote(tr('Aucune invitation pour le moment.'),
              icon: AppIcons.link),
        for (final invitation in _invitations)
          SettingsTile(
            icon: AppIcons.link,
            title: invitation.token.length >= 8
                ? invitation.token.substring(0, 8).toUpperCase()
                : invitation.token.toUpperCase(),
            subtitle: isAdmin
                ? tr('{0} · créée par {1}',
                    [_statusLabel(invitation), invitation.inviter])
                : _statusLabel(invitation),
            trailing: invitation.isPending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('Revoir le lien'),
                        icon: const Icon(AppIcons.link),
                        onPressed: () => _showLink(invitation),
                      ),
                      IconButton(
                        tooltip: tr('Révoquer'),
                        icon: const Icon(AppIcons.blocked),
                        onPressed: () => _revoke(invitation),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}
