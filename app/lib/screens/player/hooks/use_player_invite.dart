import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/watch_party_invite.dart';
import '../../../services/watch_party_invites.dart';

/// Une invitation « Regarder ensemble » qui arrive pendant un film
/// (ADR-0148).
///
/// Elle ne s'affiche que dix secondes ([shownFor]) : le film continue
/// dessous, et la carte s'efface d'elle-même si personne n'y répond. Elle est
/// alors tenue pour vue, et ne revient pas sur l'accueil.
///
/// Rejoindre ne ferme pas le lecteur : la séance rejointe devient la séance
/// active, le lecteur s'y accroche ([PlayerWatchParty]) et ouvre son média
/// comme lorsqu'une séance passe à l'épisode suivant.
class PlayerInviteWatch extends ChangeNotifier {
  PlayerInviteWatch({
    required this.join,
    required this.isGone,
    required this.restoreFocus,
    required this.showFailure,
    WatchPartyInviteInbox? inbox,
  }) : _inbox = inbox ?? WatchPartyInviteInbox.instance;

  static const Duration shownFor = Duration(seconds: 10);

  /// Rejoint la séance de l'invitation sur le compte du lecteur. Lève si le
  /// serveur refuse.
  final Future<void> Function(WatchPartyInvite invite) join;

  /// Le lecteur s'en va : plus rien ne s'y affiche.
  final bool Function() isGone;

  /// Rend la télécommande au lecteur quand la carte qui l'avait s'en va.
  final VoidCallback restoreFocus;

  final void Function(Object error) showFailure;

  final WatchPartyInviteInbox? _inbox;

  /// L'invitation affichée, s'il y en a une.
  WatchPartyInvite? shown;
  bool joining = false;
  bool _disposed = false;

  void listen() {
    _inbox?.addListener(_onInbox);
    _onInbox();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onInbox() {
    final inbox = _inbox;
    if (inbox == null || isGone() || joining) return;
    final current = shown;
    if (current != null) {
      // Refusée depuis un autre appareil, ou expirée : la carte s'en va.
      if (inbox.current?.id != current.id) _hide();
      return;
    }
    final next = inbox.current;
    if (next == null) return;
    shown = next;
    _notify();
  }

  void _hide() {
    shown = null;
    joining = false;
    _notify();
    restoreFocus();
    // Une seconde invitation attendait peut-être derrière la première.
    scheduleMicrotask(_onInbox);
  }

  /// Les dix secondes sont passées sans réponse.
  void timeout() {
    final invite = shown;
    if (invite == null || joining) return;
    // La carte s'en va d'abord : la boîte prévient de ce changement, et la
    // trouverait encore là.
    _hide();
    _inbox?.markSeen(invite);
  }

  void decline() {
    final invite = shown;
    if (invite == null || joining) return;
    _hide();
    _inbox?.decline(invite);
  }

  Future<void> accept() async {
    final invite = shown;
    if (invite == null || joining) return;
    joining = true;
    _notify();
    try {
      await join(invite);
    } catch (e) {
      if (!_disposed && !isGone()) showFailure(e);
    }
    if (_disposed) return;
    _hide();
  }

  /// Retour, devant la carte : c'est « Ignorer ». Dit s'il y avait une carte.
  bool back() {
    if (shown == null) return false;
    decline();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _inbox?.removeListener(_onInbox);
    super.dispose();
  }
}
