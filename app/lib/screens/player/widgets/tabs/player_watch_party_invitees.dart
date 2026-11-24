import 'dart:async';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/tr.dart';
import '../../../../models/watch_party_invite.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_type.dart';
import '../onyx/onyx_capsule_button.dart';
import '../onyx/onyx_chrome_theme.dart';

/// « Inviter » dans l'onglet de la séance (ADR-0148) : les personnes qui ont
/// Onyx ouvert en ce moment, chacune avec son bouton. Le code reste à côté
/// pour qui n'a pas l'app ouverte.
///
/// La liste se relit toutes les [refreshEvery] tant que l'onglet est ouvert :
/// quelqu'un ouvre l'app, une autre la ferme, une invitation est refusée.
/// Une minuterie qu'on réarme, pas un `Timer.periodic` : l'onglet fermé, il
/// n'y a plus de widget pour la réarmer.
class PlayerWatchPartyInvitees extends StatefulWidget {
  const PlayerWatchPartyInvitees({
    super.key,
    required this.load,
    required this.invite,
  });

  final Future<List<WatchPartyInvitee>> Function() load;
  final Future<void> Function(int userId) invite;

  static const Duration refreshEvery = Duration(seconds: 6);

  @override
  State<PlayerWatchPartyInvitees> createState() =>
      _PlayerWatchPartyInviteesState();
}

class _PlayerWatchPartyInviteesState extends State<PlayerWatchPartyInvitees> {
  List<WatchPartyInvitee>? _people;

  /// Le serveur ne sait pas inviter : la section ne s'affiche pas.
  bool _unsupported = false;
  final Set<int> _sending = {};
  String? _error;
  Timer? _next;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _next?.cancel();
    try {
      final people = await widget.load();
      if (!mounted) return;
      setState(() => _people = people);
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) {
        // Un serveur d'avant les invitations, ou une séance déjà finie : on
        // n'a plus rien à proposer ici.
        setState(() => _unsupported = true);
        return;
      }
      // Une coupure : la liste d'avant reste, la suivante la remplacera.
    } catch (e) {
      // Une réponse illisible : comme une coupure, la liste d'avant reste.
      debugPrint('PlayerWatchPartyInvitees: $e');
    }
    if (!mounted) return;
    _next = Timer(PlayerWatchPartyInvitees.refreshEvery, _refresh);
  }

  Future<void> _invite(WatchPartyInvitee person) async {
    setState(() {
      _sending.add(person.userId);
      _error = null;
    });
    try {
      await widget.invite(person.userId);
      if (!mounted) return;
      setState(() {
        _sending.remove(person.userId);
        _people = [
          for (final p in _people ?? const <WatchPartyInvitee>[])
            p.userId == person.userId
                ? p.copyWith(status: WatchPartyInviteStatus.pending)
                : p,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      final offline = e is DioException && e.response?.statusCode == 409;
      setState(() {
        _sending.remove(person.userId);
        _error = offline
            ? tr('{0} vient de fermer Onyx.', [person.username])
            : tr('L’invitation n’est pas partie. Réessayez.');
      });
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) return const SizedBox.shrink();
    final people = _people;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text(tr('Inviter').toUpperCase(), style: _eyebrow),
        const SizedBox(height: 4),
        Text(
          _error ?? tr('Les personnes qui ont Onyx ouvert en ce moment.'),
          style: TextStyle(
            color: _error == null ? OnyxChromeTheme.meta : AppColors.error,
            fontSize: AppType.footnote,
          ),
        ),
        const SizedBox(height: 10),
        if (people == null)
          const SizedBox(
            height: 34,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: OnyxChromeTheme.meta,
                ),
              ),
            ),
          )
        else if (people.isEmpty)
          Text(
            tr('Personne d’autre n’a Onyx ouvert. Partagez le code.'),
            style: const TextStyle(
              color: OnyxChromeTheme.time,
              fontSize: AppType.callout,
            ),
          )
        else
          for (final person in people) _row(person),
      ],
    );
  }

  Widget _row(WatchPartyInvitee person) {
    final name = person.username.isEmpty ? tr('Invité') : person.username;
    final sending = _sending.contains(person.userId);
    final (label, onPressed) = switch (person.status) {
      WatchPartyInviteStatus.pending => (tr('Envoyée'), null),
      WatchPartyInviteStatus.declined => (
          tr('Réinviter'),
          () => unawaited(_invite(person))
        ),
      WatchPartyInviteStatus.none => (
          tr('Inviter'),
          () => unawaited(_invite(person))
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: OnyxChromeTheme.glassControl,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: OnyxChromeTheme.title,
                fontSize: AppType.callout,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OnyxChromeTheme.title,
                    fontSize: AppType.callout,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (person.status == WatchPartyInviteStatus.declined)
                  Text(
                    tr('A refusé'),
                    style: const TextStyle(
                      color: OnyxChromeTheme.meta,
                      fontSize: AppType.footnote,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OnyxControlsRow(
            child: OnyxCapsuleButton(
              key: ValueKey('player-party-invite-${person.userId}'),
              label: label,
              busy: sending,
              onPressed: sending ? null : onPressed,
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _eyebrow = TextStyle(
    color: OnyxChromeTheme.meta,
    fontSize: AppType.footnote,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}
