import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/server_account.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/server_registry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/nav/tv_region.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../utils/on_screen.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/onyx_dialog.dart';
import '../../widgets/global/overlay_back_button.dart';
import '../settings/add_server_screen.dart';
import '../settings/servers_support.dart';
import '../settings/widgets/settings_pick_dialog.dart';
import 'user_choice_screen.dart';
import 'widgets/server_choice_card.dart';

enum _ManageAction { primary, rename, link, unlink, forget }

/// « Quel serveur ? » depuis le menu du compte : choisit un serveur, en ajoute
/// un ou gère ceux de cet appareil sur la même grille, au dessin de
/// [UserChoiceScreen].
class ServerSwitcherScreen extends StatefulWidget {
  const ServerSwitcherScreen({super.key});

  @override
  State<ServerSwitcherScreen> createState() => _ServerSwitcherScreenState();
}

class _ServerSwitcherScreenState extends State<ServerSwitcherScreen>
    with OnScreenState {
  bool _editing = false;
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshLinks();
  }

  @override
  void didChangeOnScreen(bool onScreen) {
    _poll?.cancel();
    _poll = null;
    if (!onScreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPending());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _checkPending());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshLinks() async {
    await context.read<ApiClient>().refreshAccountLinks();
    if (mounted) setState(() {});
  }

  Future<void> _checkPending() async {
    if (_checking || !mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.pendingAccessRequests.isEmpty) return;
    _checking = true;
    final before = auth.pendingAccessRequests.length;
    await auth.refreshAccessRequests();
    _checking = false;
    if (!mounted || auth.pendingAccessRequests.length == before) return;
    _toast(tr('Une demande d’accès a reçu une réponse.'));
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : null,
    ));
  }

  /// Un compte représentatif par serveur : celui qui est actif sur le serveur
  /// actif pour refléter son libellé, sinon le premier du carnet.
  List<ServerAccount> _distinctServers(AuthProvider auth) {
    final active = auth.activeServer;
    final result = <ServerAccount>[];
    if (active != null) result.add(active);
    for (final account in auth.servers) {
      if (result.any((kept) => ServerRegistry.sameServer(kept, account))) {
        continue;
      }
      result.add(account);
    }
    return result;
  }

  String _statusOf(
    AuthProvider auth,
    ServerRegistry registry,
    ServerAccount account, {
    required bool isActive,
  }) {
    if (isActive) return tr('Serveur actif');
    if (auth.isPrimaryServer(account.id)) return tr('Serveur principal');
    final count = registry.usersOf(account.id).length;
    return count <= 1 ? tr('1 profil') : tr('{0} profils', [count]);
  }

  Future<void> _selectServer(
    AuthProvider auth,
    ServerAccount account, {
    required bool isActive,
  }) async {
    if (isActive) {
      Navigator.of(context).pop();
      return;
    }
    final navigator = Navigator.of(context);
    final registry = auth.apiClient.servers;
    if (registry.usersOf(account.id).length > 1) {
      await navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => UserChoiceScreen(serverAccountId: account.id),
        ),
      );
      return;
    }
    final ok = await auth.switchServer(account.id);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      return;
    }
    _toast(auth.errorMessage ?? tr('Bascule impossible.'), error: true);
  }

  Future<void> _addServer() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddServerScreen()),
    );
    if (added == true && mounted) setState(() {});
  }

  Future<void> _togglePrimary(ServerAccount account) async {
    final auth = context.read<AuthProvider>();
    final wasPrimary = auth.isPrimaryServer(account.id);
    await auth.setPrimaryServer(wasPrimary ? null : account.id);
    if (!mounted) return;
    _toast(wasPrimary
        ? tr('{0} n’est plus le serveur principal.', [account.displayName])
        : tr('L’app démarrera sur {0}.', [account.displayName]));
    setState(() {});
  }

  Future<void> _rename(ServerAccount account) async {
    final controller = TextEditingController(text: account.label ?? '');
    final label = await showOnyxDialog<String>(
      context: context,
      builder: (ctx) => OnyxDialog(
        title: tr('Nom du serveur'),
        content: TvDeferredKeyboard(
          builder: (context, focusNode, canRequestFocus) => TextField(
            focusNode: focusNode,
            canRequestFocus: canRequestFocus,
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Nom affiché'),
              hintText: account.prettyHost,
            ),
          ),
        ),
        actions: [
          OnyxDialogAction(
            label: tr('Annuler'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          OnyxDialogAction(
            label: tr('Enregistrer'),
            primary: true,
            onPressed: () => Navigator.of(ctx).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || !mounted) return;
    await context.read<ApiClient>().servers.rename(account.id, label);
    if (mounted) setState(() {});
  }

  Future<void> _link(ServerAccount account) async {
    final api = context.read<ApiClient>();
    final candidates = linkCandidates(api, account);
    final chosen = await pickSettingsOption<String>(
      context,
      title: tr('Lier {0} à un compte', [account.username]),
      message: tr('Choisissez un autre de vos comptes. Les deux serveurs '
          'se transmettront votre progression, et chacun '
          'apparaîtra sur vos autres appareils. Les '
          'administrateurs des deux serveurs doivent accepter le '
          'lien une première fois.'),
      options: [
        for (final other in candidates)
          (other.id, '${other.username} · ${other.displayName}'),
      ],
    );
    if (chosen == null || !mounted) return;
    await linkAndReport(context, account.id, chosen);
    if (mounted) setState(() {});
  }

  Future<void> _unlink(ServerAccount account) async {
    final api = context.read<ApiClient>();
    final links = api.servers.serverLinksFor(account.id);
    if (links.isEmpty) return;
    final link = links.length == 1
        ? links.single
        : await pickSettingsOption<AccountLink>(
            context,
            title: tr('Dissocier quel compte ?'),
            options: [
              for (final link in links)
                (link, '${link.remoteUsername} · ${link.displayName}'),
            ],
          );
    if (link == null || !mounted) return;
    try {
      await api.unlinkAccount(account.id, link);
      _toast(tr('Compte dissocié. L’historique déjà partagé est conservé.'));
    } catch (e) {
      _toast(serverErrorText(e), error: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _forget(ServerAccount account) async {
    final confirmed = await showOnyxConfirm(
      context,
      title: tr('Retirer {0} ?', [account.displayName]),
      message: tr('Ce serveur disparaît de cet appareil et il faudra retaper un '
          'mot de passe pour y revenir. Le compte lui-même n’est pas '
          'supprimé.'),
      confirmLabel: tr('Retirer'),
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirmed || !mounted) return;
    await context.read<AuthProvider>().forgetServer(account.id);
    if (mounted) setState(() {});
  }

  Future<void> _manageServer(ServerAccount account) async {
    final auth = context.read<AuthProvider>();
    final api = context.read<ApiClient>();
    final isPrimary = auth.isPrimaryServer(account.id);
    final links = api.servers.serverLinksFor(account.id);
    final canLink = linkCandidates(api, account).isNotEmpty;
    final canForget = auth.servers.length > 1;
    final action = await pickSettingsOption<_ManageAction>(
      context,
      title: account.displayName,
      message: account.prettyHost,
      options: [
        (
          _ManageAction.primary,
          isPrimary
              ? tr('Ne plus démarrer ici')
              : tr('Démarrer sur ce serveur'),
        ),
        (_ManageAction.rename, tr('Renommer')),
        if (canLink) (_ManageAction.link, tr('Lier un compte')),
        if (links.isNotEmpty) (_ManageAction.unlink, tr('Dissocier ce compte')),
        if (canForget) (_ManageAction.forget, tr('Retirer de cet appareil')),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ManageAction.primary:
        await _togglePrimary(account);
      case _ManageAction.rename:
        await _rename(account);
      case _ManageAction.link:
        await _link(account);
      case _ManageAction.unlink:
        await _unlink(account);
      case _ManageAction.forget:
        await _forget(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final api = context.read<ApiClient>();
    final registry = api.servers;
    final active = auth.activeServer;
    final servers = _distinctServers(auth);
    final pending = auth.pendingAccessRequests;
    final compact = AppLayout.isCompact(context);
    final busy = auth.isLoading;
    final size = compact ? 92.0 : 120.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _editing
                          ? tr('Gérer les serveurs')
                          : tr('Quel serveur ?'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: compact ? AppType.title1 : AppType.largeTitle,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (active != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        tr('Connecté à {0}', [active.displayName]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: AppType.body,
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 32 : 48),
                    TvRegion.rail(
                      entersAtStart: false,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        spacing: compact ? 16 : 32,
                        runSpacing: compact ? 20 : 32,
                        children: [
                          for (final (index, account) in servers.indexed)
                            Builder(builder: (context) {
                              final isActive = active != null &&
                                  ServerRegistry.sameServer(account, active);
                              return ServerChoiceCard(
                                account: account,
                                size: size,
                                selected: isActive,
                                enabled: !busy,
                                editing: _editing,
                                isPrimary: auth.isPrimaryServer(account.id),
                                autofocus:
                                    active != null ? isActive : index == 0,
                                status: _statusOf(
                                  auth,
                                  registry,
                                  account,
                                  isActive: isActive,
                                ),
                                onSelect: () => _selectServer(
                                  auth,
                                  account,
                                  isActive: isActive,
                                ),
                                onEdit: () => _manageServer(account),
                                onTogglePrimary: () => _togglePrimary(account),
                              );
                            }),
                          if (!_editing)
                            AddServerCard(
                              size: size,
                              enabled: !busy,
                              onSelect: _addServer,
                            ),
                        ],
                      ),
                    ),
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          children: [
                            for (final request in pending)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.glassBorder),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            request.prettyHost,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: AppType.subhead,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            tr('En attente · {0}',
                                                [request.username]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: AppType.footnote,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: tr('Abandonner'),
                                      icon: const Icon(AppIcons.close, size: 18),
                                      onPressed: () async {
                                        await auth
                                            .abandonAccessRequest(request);
                                        if (mounted) setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 36 : 56),
                    _editing
                        ? FilledButton(
                            onPressed: () => setState(() => _editing = false),
                            child: Text(tr('Terminé')),
                          )
                        : OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => _editing = true),
                            child: Text(tr('Gérer les serveurs')),
                          ),
                  ],
                ),
              ),
            ),
            const Positioned(top: 0, left: 0, child: OverlayBackButton()),
          ],
        ),
      ),
    );
  }
}
