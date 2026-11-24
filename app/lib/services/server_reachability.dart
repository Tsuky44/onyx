import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../utils/on_screen.dart';
import 'api_client.dart';

/// Est-ce que le serveur répond ?
///
/// Une seule question, posée à un seul endroit, parce que toute l'app en
/// dépend : c'est elle qui décide si on affiche la bibliothèque ou seulement
/// les téléchargements, si un battement de coeur part sur le réseau ou dans le
/// manifeste local, et quand rejouer ce qui a été regardé hors ligne.
///
/// La réponse vient d'un `GET /api/ping` — route publique, réponse minuscule —
/// et non d'un état de connectivité système : un téléphone peut être
/// parfaitement connecté au Wi-Fi d'un hôtel sans que le NAS de la maison soit
/// à portée. Ce qui compte n'est pas d'avoir du réseau, c'est d'avoir *ce*
/// serveur.
class ServerReachability extends ChangeNotifier with WidgetsBindingObserver {
  /// [probe] remplace le client du sondage, pour les tests.
  ServerReachability(this._api, {Dio? probe})
      : _dio = probe ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
            ));

  final ApiClient _api;

  /// Client à part : les délais de l'app (10 s de connexion) sont taillés pour
  /// des appels qui doivent aboutir, pas pour un sondage qui doit conclure vite.
  final Dio _dio;

  /// Optimiste au démarrage : l'app affiche sa bibliothèque et le premier
  /// sondage corrige en une poignée de secondes. L'inverse ferait clignoter
  /// tout le monde en mode hors ligne à chaque lancement.
  bool _online = true;
  bool _started = false;
  bool _checking = false;
  Timer? _timer;

  final List<VoidCallback> _onRestored = [];

  bool get isOnline => _online;
  bool get isOffline => !_online;

  /// Rappelé à chaque retour du serveur — c'est là que la resynchronisation
  /// s'accroche.
  void addRestoredListener(VoidCallback listener) => _onRestored.add(listener);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // Un appel qui échoue en dit plus long, et plus tôt, que le prochain
    // sondage : une erreur de connexion déclenche une vérification immédiate.
    ApiClient.onConnectionError = _onApiConnectionError;
    ApiClient.onConnectionSuccess = _onApiSuccess;
    AppForeground.visible.addListener(_visibilityChanged);
    unawaited(check());
    _arm();
  }

  /// Une app cachée (réduite, en arrière-plan) ne sonde plus : elle se
  /// réveillait toutes les 45 s pour une réponse que personne ne lisait. Un
  /// appel qui échoue pendant ce temps (battement d'un film qui joue, fenêtre
  /// réduite) déclenche quand même sa vérification, et le retour au premier
  /// plan sonde aussitôt (ADR-0166).
  void _visibilityChanged() {
    if (AppForeground.isVisible) unawaited(check());
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!AppForeground.isVisible) return;
    // Hors ligne on guette le retour, en ligne on se contente de vérifier que
    // rien n'est tombé. Deux rythmes, une seule horloge.
    _timer = Timer.periodic(
      _online ? const Duration(seconds: 45) : const Duration(seconds: 10),
      (_) => check(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revenir dans l'app depuis l'arrière-plan est le moment où la réponse a
    // le plus de chances d'avoir changé : on a pu changer de réseau entre-temps.
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  void _onApiConnectionError() {
    if (!_online) return;
    unawaited(check());
  }

  void _onApiSuccess() {
    if (_online) return;
    _set(true);
  }

  /// Sonde le serveur maintenant. Renvoie l'état constaté.
  Future<bool> check() async {
    if (_checking) return _online;
    _checking = true;
    try {
      final response = await _dio.get<dynamic>('${_api.baseUrl}/api/ping');
      _set((response.statusCode ?? 0) < 500);
    } catch (_) {
      _set(false);
    } finally {
      _checking = false;
    }
    return _online;
  }

  void _set(bool online) {
    if (_online == online) return;
    _online = online;
    _arm();
    notifyListeners();
    if (online) {
      for (final listener in List<VoidCallback>.from(_onRestored)) {
        listener();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) {
      AppForeground.visible.removeListener(_visibilityChanged);
      WidgetsBinding.instance.removeObserver(this);
      ApiClient.onConnectionError = null;
      ApiClient.onConnectionSuccess = null;
    }
    super.dispose();
  }
}
