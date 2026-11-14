import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../navigation/search_route_observer.dart';
import '../../providers/auth_provider.dart';
import '../../screens/player/player_screen.dart';
import '../../services/watch_party.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';
import 'onyx_dialog.dart';
import '../../theme/app_icons.dart';

/// Demande le code d'une séance « Regarder ensemble », la rejoint sur le
/// serveur actif et ouvre le lecteur là où en sont les autres.
Future<void> showJoinWatchPartyDialog(
  BuildContext context, {
  required AuthProvider authProvider,
}) async {
  final session = await showOnyxDialog<WatchPartySession>(
    context: context,
    builder: (_) => _JoinWatchPartyDialog(authProvider: authProvider),
  );
  if (session == null || !context.mounted) return;

  final snapshot = session.snapshot;
  final media = snapshot.media;
  if (media == null) {
    // Le média de la séance n'est pas lisible sur ce compte : inutile d'y
    // rester, on ne pourrait rien y voir.
    await session.leave();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Ce média n’est pas disponible sur votre compte.')),
      ),
    );
    return;
  }
  // Le lecteur se recale à sa première image : partir d'ici suffit.
  final position = snapshot.position;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: SearchRouteObserver.playerRouteName),
      builder: (_) => PlayerScreen(
        media: media,
        resumeAtSeconds: position.inSeconds,
        startPaused: !snapshot.playing,
      ),
    ),
  );
}

class _JoinWatchPartyDialog extends StatefulWidget {
  const _JoinWatchPartyDialog({required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<_JoinWatchPartyDialog> createState() => _JoinWatchPartyDialogState();
}

class _JoinWatchPartyDialogState extends State<_JoinWatchPartyDialog> {
  final TextEditingController _code = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = WatchPartySession.normalizeCode(_code.text);
    if (code.isEmpty) {
      setState(() => _error = tr('Entrez le code affiché chez l’hôte.'));
      return;
    }
    // Le même compte que celui sur lequel le lecteur s'ouvrira.
    final shared = widget.authProvider.apiClient;
    final accountId = shared.accountId;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final api = accountId == null
          ? shared
          : await shared.pinToAccount(accountId);
      final session = await WatchPartySession.join(
        api: api,
        accountId: accountId ?? WatchPartySession.defaultAccountKey,
        code: code,
      );
      if (!mounted) {
        await session.leave();
        return;
      }
      Navigator.of(context).pop(session);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = switch (e.response?.statusCode) {
          404 => tr('Aucune séance avec ce code sur ce serveur.'),
          409 => tr('Cette séance est complète.'),
          _ => tr('Impossible de rejoindre la séance. Réessayez.'),
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = tr('Impossible de rejoindre la séance. Réessayez.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.authProvider.activeServer?.displayName;
    return OnyxDialog(
      title: tr('Rejoindre une séance'),
      icon: AppIcons.play,
      width: 380,
      message: server == null
          ? tr('Entrez le code affiché dans le lecteur de l’hôte.')
          : tr('Entrez le code affiché dans le lecteur de l’hôte, sur {0}.', [
              server,
            ]),
      content: TvDeferredKeyboard(
        builder: (context, focusNode, canRequestFocus) => TextField(
          controller: _code,
          focusNode: focusNode,
          canRequestFocus: canRequestFocus,
          autofocus: true,
          enabled: !_joining,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: AppType.title1,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
          decoration: InputDecoration(
            hintText: tr('ABC123'),
            errorText: _error,
          ),
          onSubmitted: (_) => _join(),
        ),
      ),
      actions: [
        OnyxDialogAction(
          label: tr('Annuler'),
          onPressed: _joining ? null : () => Navigator.of(context).pop(),
        ),
        OnyxDialogAction(
          label: tr('Rejoindre'),
          primary: true,
          onPressed: _joining ? null : _join,
          child: _joining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ],
    );
  }
}
