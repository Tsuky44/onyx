import 'package:flutter/widgets.dart';

import '../../models/remote_playback.dart';

/// La place que la barre du haut d'un téléviseur garde à « Reprendre ici »
/// (ADR-0136).
///
/// La notification de l'accueil (`RemotePlaybackBanner`) est posée par-dessus
/// le bandeau, sur le chemin d'aucune rangée : hors Apple TV, on ne savait pas
/// y revenir une fois le focus parti. Le bouton de la barre, lui, est au même
/// niveau que les onglets. La coquille possède la place, le bandeau la
/// remplit (ce qui se lit ailleurs, et de quoi le reprendre), et la barre la
/// dessine ([RemotePlaybackSlotScope]).
class RemotePlaybackSlot extends ChangeNotifier {
  RemotePlayback? _play;
  VoidCallback? _onResume;
  bool _disposed = false;

  /// Le focus du bouton de la barre : le bandeau l'y met quand la
  /// notification arrive, ou sur un appui court de lecture/pause.
  final FocusNode focus = FocusNode(debugLabel: 'Reprendre ici');

  /// Ce qui se lit sur un autre appareil ; nul quand il n'y a rien à
  /// reprendre, et le bouton disparaît.
  RemotePlayback? get play => _play;

  /// Reprend ici ; nul pendant que la reprise est déjà lancée.
  VoidCallback? get onResume => _onResume;

  void offer(RemotePlayback? play, VoidCallback? onResume) {
    if (_disposed) return;
    if (identical(play, _play) && onResume == _onResume) return;
    _play = play;
    _onResume = play == null ? null : onResume;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    focus.dispose();
    super.dispose();
  }
}

/// Rend la [RemotePlaybackSlot] de la coquille à ses descendants.
class RemotePlaybackSlotScope extends InheritedNotifier<RemotePlaybackSlot> {
  const RemotePlaybackSlotScope({
    super.key,
    required RemotePlaybackSlot slot,
    required super.child,
  }) : super(notifier: slot);

  /// La place, ou nul hors d'une coquille de téléviseur. Sans [listen], le
  /// widget n'est pas reconstruit à chaque changement.
  static RemotePlaybackSlot? maybeOf(BuildContext context,
      {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<RemotePlaybackSlotScope>()
        : context.getInheritedWidgetOfExactType<RemotePlaybackSlotScope>();
    return scope?.notifier;
  }
}
