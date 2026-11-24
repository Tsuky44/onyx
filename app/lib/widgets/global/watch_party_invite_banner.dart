import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/watch_party_invite.dart';
import '../../providers/auth_provider.dart';
import '../../services/watch_party.dart';
import '../../services/watch_party_invites.dart';
import '../../theme/app_motion.dart';
import '../../tv/tv_mode.dart';
import '../../utils/on_screen.dart';
import 'join_watch_party_dialog.dart';
import 'watch_party_invite_card.dart';

/// L'invitation « Regarder ensemble » sur l'accueil (ADR-0148), là où se pose
/// la lecture d'un autre appareil : en haut à droite, ou en bas sur un
/// téléphone ([compact]).
///
/// Elle reste jusqu'à ce qu'on y réponde, ou que l'invitation expire. Sous la
/// télécommande, « Rejoindre » prend le focus à l'arrivée de l'invitation :
/// c'est elle qu'on vient voir, et un appui sur OK y répond.
class WatchPartyInviteBanner extends StatefulWidget {
  const WatchPartyInviteBanner({super.key, this.compact = false});

  final bool compact;

  /// L'écart avec la lecture d'un autre appareil, quand les deux s'empilent.
  static const double gap = 10;

  @override
  State<WatchPartyInviteBanner> createState() => _WatchPartyInviteBannerState();
}

class _WatchPartyInviteBannerState extends State<WatchPartyInviteBanner>
    with OnScreenState {
  final FocusNode _accept = FocusNode(debugLabel: 'watch-party-invite-accept');
  WatchPartyInviteInbox? _inbox;
  String? _focusedFor;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _inbox = WatchPartyInviteInbox.instance?..addListener(_onInbox);
  }

  @override
  void dispose() {
    _inbox?.removeListener(_onInbox);
    _accept.dispose();
    super.dispose();
  }

  @override
  void didChangeOnScreen(bool onScreen) {
    // Revenir sur l'accueil (du lecteur, d'une fiche) montre l'invitation en
    // attente : sous la télécommande, elle reprend le focus.
    if (onScreen) {
      _focusedFor = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onInbox());
    }
  }

  void _onInbox() {
    if (!mounted) return;
    setState(() {});
    final invite = _inbox?.current;
    if (invite == null || !TvMode.isTv || !isOnScreen) return;
    if (_focusedFor == invite.id) return;
    _focusedFor = invite.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (_inbox?.current?.id == invite.id) _accept.requestFocus();
    });
  }

  Future<void> _join(WatchPartyInvite invite) async {
    final inbox = _inbox;
    if (inbox == null || _joining) return;
    final shared = Provider.of<AuthProvider>(context, listen: false).apiClient;
    final accountId = shared.accountId;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _joining = true);
    try {
      // Le même compte que celui sur lequel le lecteur s'ouvrira.
      final api =
          accountId == null ? shared : await shared.pinToAccount(accountId);
      final session = await inbox.accept(
        invite,
        api: api,
        accountId: accountId ?? WatchPartySession.defaultAccountKey,
      );
      if (!mounted) {
        await session.leave();
        return;
      }
      setState(() => _joining = false);
      await openJoinedWatchParty(context, session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      messenger
          ?.showSnackBar(SnackBar(content: Text(watchPartyInviteFailure(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _inbox?.current;
    final baseUrl =
        Provider.of<AuthProvider>(context, listen: false).apiClient.baseUrl;
    final shown = invite == null
        ? const SizedBox.shrink()
        : Padding(
            key: ValueKey(invite.id),
            padding: widget.compact
                ? const EdgeInsets.only(bottom: WatchPartyInviteBanner.gap)
                : const EdgeInsets.only(top: WatchPartyInviteBanner.gap),
            child: WatchPartyInviteCard(
              invite: invite,
              serverBaseUrl: baseUrl,
              compact: widget.compact,
              joining: _joining,
              acceptFocus: _accept,
              onAccept: () => _join(invite),
              onDecline: () => _inbox?.decline(invite),
            ),
          );
    // Elle entre comme la lecture d'un autre appareil : par la droite en
    // haut, par le bas sur un téléphone.
    return AnimatedSwitcher(
      duration: AppMotion.move(context, AppMotion.emphasis),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: widget.compact ? Alignment.bottomCenter : Alignment.topRight,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin:
                widget.compact ? const Offset(0, 0.25) : const Offset(0.12, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: shown,
    );
  }
}

/// Ce qu'on dit quand une invitation ne mène nulle part : la séance a fini,
/// ou elle est complète.
String watchPartyInviteFailure(Object error) {
  if (error is DioException) {
    return switch (error.response?.statusCode) {
      404 => tr('Cette séance est terminée.'),
      409 => tr('Cette séance est complète.'),
      _ => tr('Impossible de rejoindre la séance. Réessayez.'),
    };
  }
  return tr('Impossible de rejoindre la séance. Réessayez.');
}
