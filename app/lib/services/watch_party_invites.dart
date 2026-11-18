import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../models/watch_party_invite.dart';
import '../providers/auth_provider.dart';
import 'api_client.dart';
import 'watch_party.dart';

/// La boîte d'invitations « Regarder ensemble » de l'app (ADR-0148).
///
/// Tant que l'app est au premier plan et connectée, elle attend en
/// long-polling les invitations du compte sur le serveur actif. Cette attente
/// est aussi ce qui la rend invitable : le serveur ne liste que les comptes
/// dont un appareil attend sa boîte. En arrière-plan, l'attente s'arrête, et
/// le compte sort de la liste des autres en moins d'une minute.
///
/// L'accueil montre l'invitation en cours ([current]) jusqu'à ce qu'on y
/// réponde ; le lecteur la montre dix secondes, puis la tient pour vue
/// ([markSeen]).
class WatchPartyInviteInbox extends ChangeNotifier {
  WatchPartyInviteInbox(
      {required ApiClient? Function() api, String? Function()? accountKey})
      : _api = api,
        _accountKey = accountKey ?? (() => null);

  /// L'instance de l'app, posée au démarrage. Nulle dans un test qui n'en
  /// monte pas : les écrans n'affichent alors aucune invitation.
  static WatchPartyInviteInbox? instance;

  /// Monte la boîte de l'app : elle suit le compte connecté et s'arrête en
  /// arrière-plan.
  static WatchPartyInviteInbox install(AuthProvider auth) {
    final inbox = WatchPartyInviteInbox(
      api: () => auth.isAuthenticated ? auth.apiClient : null,
      accountKey: () {
        final user = auth.currentUser;
        if (!auth.isAuthenticated || user == null) return null;
        return '${auth.apiClient.baseUrl}|${user.id}';
      },
    );
    instance = inbox;
    auth.addListener(inbox.refresh);
    WatchPartyInviteLifecycle(inbox);
    inbox.refresh();
    return inbox;
  }

  final ApiClient? Function() _api;

  /// Qui est connecté, et où : un changement relance l'attente sur le
  /// nouveau compte.
  final String? Function() _accountKey;

  static final Stopwatch _clock = Stopwatch()..start();

  List<_Received> _invites = const [];
  final Set<String> _seen = {};
  int _version = 0;
  bool _running = false;
  int _generation = 0;
  CancelToken? _cancel;
  Timer? _expiry;
  String? _runningFor;

  /// L'invitation à montrer : la plus ancienne encore valable, à laquelle on
  /// n'a pas répondu et que le lecteur n'a pas déjà montrée.
  WatchPartyInvite? get current {
    final now = _clock.elapsed;
    for (final r in _invites) {
      if (!_seen.contains(r.invite.id) && r.expiresAt > now) return r.invite;
    }
    return null;
  }

  /// Le temps qu'il reste à [invite], d'après l'horloge de l'appareil depuis
  /// la réponse du serveur.
  Duration remaining(WatchPartyInvite invite) {
    for (final r in _invites) {
      if (r.invite.id == invite.id) {
        final left = r.expiresAt - _clock.elapsed;
        return left.isNegative ? Duration.zero : left;
      }
    }
    return Duration.zero;
  }

  // --- Cycle de vie ----------------------------------------------------------

  /// Relance l'attente si le compte a changé, la démarre sinon. À appeler à
  /// chaque changement de connexion et au retour au premier plan.
  void refresh() {
    final key = _accountKey();
    if (key == null || _api() == null) {
      stop();
      return;
    }
    if (_running && key == _runningFor) return;
    stop();
    _clearInvites();
    _runningFor = key;
    _running = true;
    unawaited(_loop(++_generation));
  }

  /// Coupe l'attente : l'app passe en arrière-plan, ou n'est plus connectée.
  void stop() {
    if (!_running) return;
    _running = false;
    _generation++;
    _cancel?.cancel();
    _cancel = null;
  }

  void _clearInvites() {
    _version = 0;
    if (_invites.isEmpty) return;
    _invites = const [];
    _scheduleExpiry();
    notifyListeners();
  }

  Future<void> _loop(int generation) async {
    final api = _api();
    if (api == null) return;
    try {
      if (!await api.supportsWatchPartyInvites()) {
        // Un serveur d'avant les invitations : rien à attendre, ni à montrer.
        if (generation == _generation) _running = false;
        return;
      }
    } catch (e) {
      // Le serveur ne répond pas : la boucle ci-dessous réessaie avec son
      // délai, et dira la même chose s'il ne connaît pas les invitations.
      debugPrint('WatchPartyInvites: ping: $e');
    }
    var backoff = const Duration(seconds: 2);
    while (generation == _generation) {
      final cancel = CancelToken();
      _cancel = cancel;
      try {
        final box = await api.pollWatchPartyInvites(
            since: _version, cancelToken: cancel);
        if (generation != _generation) return;
        backoff = const Duration(seconds: 2);
        _apply(box);
      } on DioException catch (e) {
        if (generation != _generation || CancelToken.isCancel(e)) return;
        final status = e.response?.statusCode;
        if (status == 404 || status == 405 || status == 401) {
          // Pas de boîte sur ce serveur, ou plus de session : on s'arrête
          // jusqu'au prochain changement de compte.
          _running = false;
          return;
        }
        await Future<void>.delayed(backoff);
        backoff = backoff * 2 > const Duration(seconds: 30)
            ? const Duration(seconds: 30)
            : backoff * 2;
      } catch (e) {
        if (generation != _generation) return;
        // Une réponse illisible ne doit pas faire tourner la boucle à vide :
        // elle attend comme après une coupure.
        debugPrint('WatchPartyInvites: poll: $e');
        await Future<void>.delayed(backoff);
      }
    }
  }

  void _apply(WatchPartyInvites box) {
    // Un numéro plus petit que le nôtre : le serveur a redémarré. On repart du
    // sien, sinon on attendrait un numéro qui ne viendra jamais.
    _version = box.version;
    final now = _clock.elapsed;
    final previous = {for (final r in _invites) r.invite.id: r};
    _invites = [
      for (final invite in box.invites)
        previous[invite.id]?.withInvite(invite) ??
            _Received(invite, now + invite.expiresIn),
    ];
    final alive = {for (final r in _invites) r.invite.id};
    _seen.removeWhere((id) => !alive.contains(id));
    _scheduleExpiry();
    notifyListeners();
  }

  /// Réveille les écrans quand l'invitation montrée expire, sans attendre la
  /// prochaine réponse du serveur.
  void _scheduleExpiry() {
    _expiry?.cancel();
    final shown = current;
    if (shown == null) return;
    _expiry = Timer(remaining(shown) + const Duration(milliseconds: 50), () {
      notifyListeners();
      _scheduleExpiry();
    });
  }

  // --- Réponses --------------------------------------------------------------

  /// Le lecteur l'a montrée ses dix secondes : elle ne revient pas, ni ici ni
  /// sur l'accueil. Le serveur la garde jusqu'à son expiration, et l'hôte la
  /// voit toujours « invitée ».
  void markSeen(WatchPartyInvite invite) {
    if (!_seen.add(invite.id)) return;
    _scheduleExpiry();
    notifyListeners();
  }

  /// Refuser : elle disparaît de tous les appareils du compte, et l'hôte le
  /// voit dans sa liste.
  void decline(WatchPartyInvite invite) {
    markSeen(invite);
    final api = _api();
    if (api == null) return;
    unawaited(api.declineWatchPartyInvite(invite.id).catchError((Object e) {
      // Le refus n'a pas atteint le serveur : l'invitation expirera d'elle-
      // même, et elle reste écartée ici.
      debugPrint('WatchPartyInvites: decline: $e');
    }));
  }

  /// Rejoindre la séance de [invite], sur le compte [accountId] de [api] —
  /// celui sur lequel le lecteur s'ouvrira. Lève si le serveur refuse : la
  /// séance est finie, ou complète.
  Future<WatchPartySession> accept(
    WatchPartyInvite invite, {
    required ApiClient api,
    required String accountId,
  }) async {
    markSeen(invite);
    return WatchPartySession.join(
      api: api,
      accountId: accountId,
      code: invite.code,
    );
  }

  @override
  void dispose() {
    stop();
    _expiry?.cancel();
    super.dispose();
  }
}

class _Received {
  const _Received(this.invite, this.expiresAt);

  final WatchPartyInvite invite;

  /// Sur l'horloge monotone de l'app.
  final Duration expiresAt;

  /// La même invitation relue : elle garde son échéance, et prend le média
  /// que la séance lit maintenant.
  _Received withInvite(WatchPartyInvite next) => _Received(next, expiresAt);
}

/// Arrête la boîte quand l'app n'est plus vue et la relance au retour : une
/// app en arrière-plan, une fenêtre réduite ou un onglet caché ne doit plus
/// être invitable, puisque personne n'y verrait l'invitation. Le même signal
/// que celui des sondages des écrans (`AppForeground`).
class WatchPartyInviteLifecycle {
  WatchPartyInviteLifecycle(this.inbox) {
    _listener = AppLifecycleListener(
      onShow: inbox.refresh,
      onResume: inbox.refresh,
      onHide: inbox.stop,
      onDetach: inbox.stop,
    );
  }

  final WatchPartyInviteInbox inbox;
  late final AppLifecycleListener _listener;

  void dispose() => _listener.dispose();
}
