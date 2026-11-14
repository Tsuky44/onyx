import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../models/server_account.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../l10n/tr.dart';
import '../../widgets/global/onyx_dialog.dart';
import 'widgets/admin_prompts.dart';
import 'widgets/permissions_sheet.dart';
import 'widgets/settings_ui.dart';
import 'widgets/user_rights.dart';

/// Les gens qui ont sonné à la porte de ce serveur.
///
/// C'est l'autre bout du mouvement décrit par ADR-0013 : l'invitation part
/// d'ici, la demande d'accès arrive ici. Accepter crée le compte et ouvre la
/// session du demandeur d'un seul geste — il n'a rien de plus à taper.
class AccessRequestsSection extends StatefulWidget {
  const AccessRequestsSection({super.key});

  @override
  State<AccessRequestsSection> createState() => _AccessRequestsSectionState();
}

class _AccessRequestsSectionState extends State<AccessRequestsSection> {
  List<AccessRequest> _requests = const [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await context.read<ApiClient>().getAccessRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = adminErrorText(e);
      });
      // Les droits ont pu être retirés pendant que l'écran était ouvert.
      context.read<AuthProvider>().refreshProfile();
    }
  }

  Future<void> _approve(AccessRequest request, {Permissions? grants}) async {
    setState(() => _busyId = request.id);
    try {
      final user = await context
          .read<ApiClient>()
          .approveAccessRequest(request.id, permissions: grants);
      if (!mounted) return;
      _toast(tr('{0} a maintenant un compte sur ce serveur.', [user.username]));
      setState(() => _busyId = null);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      _toast(adminErrorText(e), error: true);
    }
  }

  /// Le choix fin des droits n'est proposé qu'aux titulaires de `manage_users`.
  /// Un simple inviteur accorde son gabarit quoi qu'il arrive — le serveur
  /// ignore ce qu'il enverrait —, donc lui montrer des cases serait mentir.
  Future<void> _approveWithGrants(AccessRequest request) async {
    final grants = await showModalBottomSheet<Permissions>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => _GrantsSheet(username: request.username),
    );
    if (grants == null || !mounted) return;
    await _approve(request, grants: grants);
  }

  Future<void> _deny(AccessRequest request) async {
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Refuser {0} ?', [request.username]),
      message: tr('La personne en sera informée à sa prochaine tentative. Aucun '
          'compte n’est créé.'),
      confirmLabel: tr('Refuser'),
      destructive: true,
      icon: AppIcons.close,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = request.id);
    try {
      await context.read<ApiClient>().denyAccessRequest(request.id);
      if (!mounted) return;
      setState(() => _busyId = null);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      _toast(adminErrorText(e), error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showSettingsSnack(context, message, error: error);
  }

  String _waitingFor(AccessRequest request) {
    final since = request.createdAt;
    if (since == null) return tr('En attente');
    final elapsed = DateTime.now().difference(since);
    if (elapsed.inMinutes < 1) return tr('À l’instant');
    if (elapsed.inHours < 1) return tr('Il y a {0} min', [elapsed.inMinutes]);
    if (elapsed.inDays < 1) return tr('Il y a {0} h', [elapsed.inHours]);
    return tr('Il y a {0} j', [elapsed.inDays]);
  }

  @override
  Widget build(BuildContext context) {
    final title = tr('Demandes d’accès');
    final footer = tr('Accepter crée le compte et connecte aussitôt l’appareil '
        'qui a fait la demande.');
    if (_loading) {
      return SettingsGroup(
        title: title,
        footer: footer,
        padded: true,
        children: const [SettingsLoading()],
      );
    }

    final canChooseGrants =
        context.watch<AuthProvider>().permissions.manageUsers;

    return SettingsGroup(
      title: title,
      footer: footer,
      trailing: IconButton(
        tooltip: tr('Actualiser'),
        icon: const Icon(AppIcons.refresh, size: 18),
        onPressed: _load,
      ),
      children: [
        if (_error != null)
          SettingsBanner(_error!, tone: BannerTone.error)
        else if (_requests.isEmpty)
          SettingsEmptyNote(tr('Aucune demande en attente.'),
              icon: AppIcons.person),
        for (final request in _requests)
          SettingsTile(
            leading: UserAvatar(request.username, size: 34, rounded: true),
            title: request.username,
            subtitle: [
              _waitingFor(request),
              if (request.deviceName.isNotEmpty) request.deviceName,
              if (request.message.isNotEmpty) '« ${request.message} »',
            ].join(' · '),
            trailing: _busyId == request.id
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('Refuser'),
                        icon: const Icon(AppIcons.close),
                        onPressed: () => _deny(request),
                      ),
                      IconButton(
                        tooltip: tr('Accepter'),
                        icon: const Icon(AppIcons.check),
                        onPressed: () => _approve(request),
                      ),
                      if (canChooseGrants)
                        IconButton(
                          tooltip: tr('Accepter avec des droits précis'),
                          icon: const Icon(AppIcons.filters),
                          onPressed: () => _approveWithGrants(request),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Les droits accordés à la personne acceptée. Par défaut ceux d'un compte
/// ordinaire : demander des médias, rien d'autre.
class _GrantsSheet extends StatefulWidget {
  const _GrantsSheet({required this.username});

  final String username;

  @override
  State<_GrantsSheet> createState() => _GrantsSheetState();
}

class _GrantsSheetState extends State<_GrantsSheet> {
  Permissions _grants = const Permissions(requestMedia: true);

  @override
  Widget build(BuildContext context) {
    return SettingsSheetFrame(
      title: tr('Droits de {0}', [widget.username]),
      children: [
        PermissionSwitches(
          value: _grants,
          onChanged: (key, granted) => setState(() {
            _grants = writePermission(_grants, key, granted);
          }),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_grants),
          child: Text(tr('Accepter')),
        ),
      ],
    );
  }
}
