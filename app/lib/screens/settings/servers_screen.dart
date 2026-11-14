import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/server_account.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../utils/on_screen.dart';
import 'add_server_screen.dart';
import '../../theme/app_icons.dart';
import '../../widgets/global/onyx_dialog.dart';
import 'server_account_tile.dart';
import 'widgets/settings_pick_dialog.dart';
import 'widgets/settings_ui.dart';
import 'servers_support.dart';

export 'add_server_screen.dart' show AddServerScreen;
export 'servers_support.dart' show linkAndReport;
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

/// Les serveurs de cet appareil : celui qui est actif, ceux sur lesquels on
/// peut basculer, et les demandes d'accès encore sans réponse.
///
/// Basculer ne renégocie rien — chaque compte garde son jeton — donc l'écran
/// n'a pas de formulaire de connexion : ce sont des comptes déjà ouverts. Voir
/// ADR-0013.
///
/// Les liens entre comptes, eux, sont tenus par les serveurs (ADR-0017) : un
/// serveur lié depuis un autre appareil apparaît ici, et il suffit d'y entrer
/// son mot de passe une fois pour l'ajouter à cet appareil.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, this.embedded = false});

  /// Sans barre ni défilement propre, pour vivre dans une page des paramètres.
  final bool embedded;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> with OnScreenState {
  /// Le sondage des demandes en attente pendant que l'écran est ouvert. C'est
  /// exactement le moment où quelqu'un regarde si on lui a répondu.
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshLinks();
  }

  /// Recouvert par une autre page ou fenêtre réduite, personne ne lit la
  /// réponse : le sondage attend le retour, et reprend par une vérification.
  @override
  void didChangeOnScreen(bool onScreen) {
    _poll?.cancel();
    _poll = null;
    if (!onScreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPending());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _checkPending());
  }

  Future<void> _refreshLinks() async {
    await context.read<ApiClient>().refreshAccountLinks();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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

  Future<void> _switchTo(ServerAccount account) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.switchServer(account.id);
    if (!mounted) return;
    if (ok) {
      _toast(tr('Vous êtes sur {0}.', [account.displayName]));
      Navigator.of(context).pop();
    } else {
      _toast(auth.errorMessage ?? tr('Bascule impossible.'), error: true);
    }
  }

  /// Désigne — ou libère — le serveur sur lequel l'app se remettra à chaque
  /// lancement. Un seul à la fois : c'est une place, pas une étiquette.
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

  Future<void> _signInToLinked(AccountLink link) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddServerScreen(
          initialUrl: link.url,
          initialUsername: link.remoteUsername,
          signIn: true,
        ),
      ),
    );
    if (added == true && mounted) setState(() {});
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

  Future<void> _addServer() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddServerScreen()),
    );
    if (added == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final accounts = auth.servers;
    final activeId = auth.activeServer?.id;
    final pending = auth.pendingAccessRequests;
    final api = context.read<ApiClient>();
    final elsewhere = serversNotOnThisDevice(api);

    final children = <Widget>[
      if (!widget.embedded) ...[
        Text(
          tr('Liez vos comptes, même avec des noms différents : les '
              'serveurs se transmettent votre progression, vos serveurs vous '
              'suivent sur tous vos appareils, et la lecture reprend sur un '
              'serveur disponible.'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: AppType.subhead),
        ),
        const SizedBox(height: 10),
        Text(
          tr('Désignez un serveur principal pour que l’app y revienne à '
              'chaque lancement. S’il ne répond pas, elle vous proposera les '
              'autres au lieu de basculer toute seule.'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: AppType.subhead),
        ),
        const SizedBox(height: 20),
      ],
      SettingsGroup(
        children: [
          for (final account in accounts)
            ServerAccountTile(
              account: account,
              isActive: account.id == activeId,
              isPrimary: auth.isPrimaryServer(account.id),
              busy: auth.isLoading,
              onSelect: () => _switchTo(account),
              onTogglePrimary: () => _togglePrimary(account),
              onRename: () => _rename(account),
              links: api.servers.serverLinksFor(account.id),
              onLink: linkCandidates(api, account).isNotEmpty
                  ? () => _link(account)
                  : null,
              onUnlink: () => _unlink(account),
              onForget: accounts.length == 1 ? null : () => _forget(account),
            ),
        ],
      ),
      if (elsewhere.isNotEmpty)
        SettingsGroup(
          title: tr('Vos autres serveurs'),
          footer: tr('Liés à votre compte, mais pas encore ouverts sur cet '
              'appareil. Entrez votre mot de passe une fois pour pouvoir y '
              'basculer.'),
          children: [
            for (final link in elsewhere)
              SettingsTile(
                icon: AppIcons.switchServer,
                title: link.displayName,
                subtitle: link.remoteUsername,
                trailing: TextButton(
                  onPressed: () => _signInToLinked(link),
                  child: Text(tr('Se connecter')),
                ),
              ),
          ],
        ),
      if (pending.isNotEmpty)
        SettingsGroup(
          title: tr('Demandes en attente'),
          footer: tr('Un administrateur du serveur doit accepter. La réponse est '
              'récupérée toute seule, y compris après un redémarrage de '
              'l’app.'),
          children: [
            for (final request in pending)
              SettingsTile(
                leading: const SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                title: request.prettyHost,
                subtitle: tr('En attente · {0}', [request.username]),
                trailing: IconButton(
                  tooltip: tr('Abandonner'),
                  icon: const Icon(AppIcons.close),
                  onPressed: () async {
                    await context
                        .read<AuthProvider>()
                        .abandonAccessRequest(request);
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: _addServer,
          icon: const Icon(AppIcons.add),
          label: Text(tr('Ajouter un serveur')),
        ),
      ),
    ];

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(tr('Serveurs'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: children,
      ),
    );
  }
}
