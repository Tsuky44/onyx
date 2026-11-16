import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/server_account.dart';
import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../l10n/tr.dart';
import '../../widgets/global/onyx_dialog.dart';
import '../../widgets/global/onyx_menu.dart';
import 'widgets/settings_ui.dart';

/// Les serveurs liés à celui-ci (ADR-0017).
///
/// Une paire de serveurs n'a cours qu'une fois acceptée par un administrateur
/// de chaque côté, et une seule fois : les comptes liés ensuite entre ces deux
/// mêmes serveurs n'ont plus à attendre personne. Accepter, c'est permettre aux
/// deux serveurs de se transmettre la progression des comptes que leurs
/// propriétaires ont liés.
class LinkedServersSection extends StatefulWidget {
  const LinkedServersSection({super.key});

  @override
  State<LinkedServersSection> createState() => _LinkedServersSectionState();
}

class _LinkedServersSectionState extends State<LinkedServersSection> {
  List<PeerServer> _peers = const [];
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
      final peers = await context.read<ApiClient>().getPeerServers();
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e);
      });
    }
  }

  Future<void> _run(PeerServer peer, Future<void> Function() action) async {
    setState(() => _busyId = peer.id);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showSettingsSnack(context, _errorText(e), error: true);
      }
    }
    if (!mounted) return;
    setState(() => _busyId = null);
    await _load();
  }

  Future<void> _remove(PeerServer peer) async {
    final confirmed = await showOnyxConfirm(
      context,
      title: peer.isActive || peer.localApproved
          ? tr('Retirer {0} ?', [_name(peer)])
          : tr('Refuser {0} ?', [_name(peer)]),
      message: tr('Les deux serveurs cessent de se transmettre la progression et '
          'les comptes liés entre eux sont dissociés. L’historique déjà '
          'partagé reste sur chaque serveur.'),
      confirmLabel: tr('Confirmer'),
      destructive: true,
      icon: AppIcons.link,
    );
    if (!confirmed || !mounted) return;
    await _run(peer, () => context.read<ApiClient>().removePeerServer(peer.id));
  }

  Future<void> _editUrl(PeerServer peer) async {
    final controller = TextEditingController(text: peer.url);
    final url = await showOnyxDialog<String>(
      context: context,
      builder: (ctx) => OnyxDialog(
        title: tr('Adresse du serveur lié'),
        content: TvDeferredKeyboard(
          builder: (context, focusNode, canRequestFocus) => TextField(
            focusNode: focusNode,
            canRequestFocus: canRequestFocus,
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr('Adresse joignable depuis ce serveur'),
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
    if (url == null || url.trim().isEmpty || !mounted) return;
    await _run(peer,
        () => context.read<ApiClient>().updatePeerServerUrl(peer.id, url));
  }

  String _name(PeerServer peer) =>
      peer.name.trim().isEmpty ? peer.url : peer.name.trim();

  String _status(PeerServer peer) {
    final accounts =
        tr('{0} compte{1} lié{2}', [peer.accounts, peer.accounts > 1 ? 's' : '', peer.accounts > 1 ? 's' : '']);
    if (peer.isActive) return tr('Lié · {0}', [accounts]);
    if (!peer.localApproved) return tr('Demande de lien · {0}', [accounts]);
    return tr('En attente de l’administrateur de l’autre serveur · {0}', [accounts]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SettingsGroup(
        title: tr('Serveurs'),
        padded: true,
        children: const [SettingsLoading()],
      );
    }
    return SettingsGroup(
      title: tr('Serveurs'),
      trailing: IconButton(
        tooltip: tr('Actualiser'),
        icon: const Icon(AppIcons.refresh, size: 18),
        onPressed: _load,
      ),
      children: [
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (_peers.isEmpty)
          SettingsEmptyNote(
            tr('Aucun serveur lié. Une demande apparaît ici quand un '
                'utilisateur lie son compte à un compte d’un autre serveur.'),
            icon: AppIcons.link,
          ),
        for (final peer in _peers)
          SettingsTile(
            icon: AppIcons.link,
            iconColor: peer.isActive ? AppColors.primary : null,
            title: _name(peer),
            subtitle: [
              peer.url,
              _status(peer),
              if (peer.lastError.isNotEmpty) peer.lastError,
            ].join('\n'),
            trailing: _busyId == peer.id
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!peer.localApproved) ...[
                        IconButton(
                          tooltip: tr('Refuser le lien'),
                          icon: const Icon(AppIcons.close),
                          onPressed: () => _remove(peer),
                        ),
                        IconButton(
                          tooltip: tr('Autoriser le lien'),
                          icon: const Icon(AppIcons.check),
                          onPressed: () => _run(
                              peer,
                              () => context
                                  .read<ApiClient>()
                                  .approvePeerServer(peer.id)),
                        ),
                      ],
                      OnyxMenuButton<String>(
                        tooltip: tr('Options de {0}', [_name(peer)]),
                        icon: AppIcons.moreVertical,
                        items: [
                          OnyxMenuItem(
                            value: 'url',
                            label: tr('Modifier l’adresse'),
                            icon: AppIcons.edit,
                          ),
                          OnyxMenuItem(
                            value: 'remove',
                            label: tr('Retirer le lien'),
                            icon: AppIcons.delete,
                            destructive: true,
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'url') _editUrl(peer);
                          if (value == 'remove') _remove(peer);
                        },
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

String _errorText(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
  }
  return tr('Une erreur est survenue : {0}', [error]);
}
