import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_client.dart';

/// Où en est la première installation du serveur connecté (ADR-0165).
///
/// Le serveur est la source : `GET /api/setup/state` dit ce qui est fait et si
/// l'assistant est terminé ou ignoré. Ce provider le relit à la demande et
/// tient la seule chose que le serveur ne sait pas : si CET appareil a déjà
/// ouvert l'assistant, pour ne pas le rouvrir à chaque lancement après qu'on l'a
/// quitté (la checklist de l'accueil prend alors le relais).
///
/// Un serveur plus ancien répond 404 : [state] reste null, [needsSetup] faux,
/// et l'app se comporte comme avant.
class SetupProvider extends ChangeNotifier {
  SetupProvider(this.apiClient);

  final ApiClient apiClient;

  SetupState? _state;
  int _request = 0;
  bool _disposed = false;

  /// Null tant qu'on ne sait pas, ou quand le serveur ne connaît pas
  /// l'assistant.
  SetupState? get state => _state;

  /// Vrai quand l'installation reste à finir : l'accueil montre la checklist.
  bool get needsSetup => _state != null && !_state!.completed;

  /// Relit l'état. Un échec garde l'état qu'on avait : une coupure réseau ne
  /// doit ni rouvrir l'assistant ni faire disparaître la checklist.
  Future<void> load() async {
    final request = ++_request;
    try {
      final fresh = await apiClient.getSetupGuide();
      if (_disposed || request != _request) return;
      _state = fresh;
      notifyListeners();
    } catch (e) {
      debugPrint('SetupProvider: état de l’installation indisponible: $e');
    }
  }

  /// Marque l'installation finie ou ignorée, sur le serveur et ici.
  Future<void> complete() async {
    await apiClient.completeSetup();
    if (_disposed) return;
    _state = _state?.copyWith(completed: true);
    notifyListeners();
  }

  String get _offeredKey => 'setup_wizard_offered:${apiClient.baseUrl}';

  /// Vrai tant que cet appareil n'a pas encore ouvert l'assistant pour ce
  /// serveur.
  Future<bool> wizardNotOfferedYet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_offeredKey) ?? false);
    } catch (e) {
      // Sans préférences lisibles on ne rouvre pas l'assistant : mieux vaut la
      // checklist, qui est toujours là, qu'un écran plein à chaque lancement.
      debugPrint('SetupProvider: préférences illisibles: $e');
      return false;
    }
  }

  Future<void> markWizardOffered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_offeredKey, true);
    } catch (e) {
      debugPrint('SetupProvider: préférences illisibles: $e');
    }
  }

  /// Vide l'état du serveur qu'on quitte. Voir `LibraryProvider.reset`.
  void reset() {
    _request++;
    _state = null;
    notifyListeners();
    // L'accueil reste monté d'un serveur à l'autre : c'est ici qu'on relit.
    unawaited(load());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
