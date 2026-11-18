import 'package:flutter/material.dart';

import '../../../models/watch_party_invite.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/app_platform.dart';
import '../../../widgets/global/watch_party_invite_card.dart';
import '../hooks/use_player_invite.dart';
import 'onyx/onyx_glass_panel.dart';

/// La carte d'une invitation par-dessus le film (ADR-0148) : elle descend
/// d'elle-même au bout de [PlayerInviteWatch.shownFor], le trait sous les
/// boutons dit le temps qu'il reste.
class PlayerInviteOverlay extends StatefulWidget {
  const PlayerInviteOverlay({
    super.key,
    required this.invite,
    required this.serverBaseUrl,
    required this.joining,
    required this.onAccept,
    required this.onDecline,
    required this.onTimeout,
  });

  final WatchPartyInvite invite;
  final String? serverBaseUrl;
  final bool joining;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onTimeout;

  @override
  State<PlayerInviteOverlay> createState() => _PlayerInviteOverlayState();
}

class _PlayerInviteOverlayState extends State<PlayerInviteOverlay>
    with SingleTickerProviderStateMixin {
  final FocusNode _accept = FocusNode(debugLabel: 'player-invite-accept');
  late final AnimationController _left = AnimationController(
    vsync: this,
    duration: PlayerInviteWatch.shownFor,
    value: 1,
  )..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) widget.onTimeout();
    });

  @override
  void initState() {
    super.initState();
    _left.reverse();
    // Demandé, pas `autofocus` : le lecteur tient déjà le focus. Sans cela la
    // télécommande n'aurait rien sous OK pendant ces dix secondes. Pas sur un
    // écran tenu en main, où l'on répond du doigt.
    if (AppPlatform.isMobile && !TvMode.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _accept.requestFocus();
    });
  }

  @override
  void didUpdateWidget(PlayerInviteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le temps de rejoindre, la carte ne s'efface pas sous le doigt.
    if (widget.joining && !oldWidget.joining) _left.stop();
  }

  @override
  void dispose() {
    _left.dispose();
    _accept.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WatchPartyInviteCard(
      invite: widget.invite,
      serverBaseUrl: widget.serverBaseUrl,
      joining: widget.joining,
      countdown: _left,
      acceptFocus: _accept,
      onAccept: widget.onAccept,
      onDecline: widget.onDecline,
      glass: (radius, child) => OnyxGlassPanel(radius: radius, child: child),
    );
  }
}
