import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/retro.dart';
import '../services/api_client.dart';

/// Le Rétro du compte connecté (ADR 2026-11-26-tsuky-retro-annuel).
///
/// Le serveur décide s'il est visible, si le compte a assez regardé et s'il
/// l'a déjà ouvert ; ce provider le relit et garde le Rétro chargé, pour que
/// la story ne recharge pas une année d'historique à chaque ouverture.
///
/// Un serveur sans la capacité `retro` laisse [status] nul : rien ne
/// s'affiche, et l'app se comporte comme avant.
class RetroProvider extends ChangeNotifier {
  RetroProvider(this.apiClient);

  final ApiClient apiClient;

  RetroStatus? _status;
  RetroReport? _report;
  int _request = 0;
  bool _disposed = false;

  /// « Plus tard » : la diapo de l'accueil est rangée jusqu'au prochain
  /// lancement. Seule l'ouverture de la story pose « vu » sur le serveur.
  bool _later = false;

  RetroStatus? get status => _status;

  /// Le Rétro déjà chargé, s'il l'est.
  RetroReport? get report => _report;

  /// Vrai quand le Rétro peut s'ouvrir : en saison, au-dessus du seuil.
  bool get available => _status?.available ?? false;

  bool get _seen => _status?.seen ?? false;

  /// La première diapo du carrousel de l'accueil : tant que la story n'a pas
  /// été ouverte, et sauf « Plus tard ».
  bool get showsHero => available && !_seen && !_later;

  /// La carte de l'accueil, au-dessus de « Reprendre la lecture » : une fois
  /// la story vue, ou la diapo rangée.
  bool get showsCard => available && (_seen || _later);

  /// L'anneau autour de l'avatar : tant que la story n'a pas été ouverte.
  bool get showsRing => available && !_seen;

  /// Range la diapo pour la session.
  void later() {
    if (_later) return;
    _later = true;
    notifyListeners();
  }

  /// Relit l'état. Un échec garde ce qu'on avait : une coupure réseau ne doit
  /// pas faire apparaître ni disparaître la diapo de l'accueil.
  Future<void> load() async {
    final request = ++_request;
    try {
      final fresh = await apiClient.getRetroStatus();
      if (_disposed || request != _request) return;
      _status = fresh;
      notifyListeners();
    } catch (e) {
      debugPrint('RetroProvider: état du Rétro indisponible: $e');
      return;
    }
    // La diapo et la carte de l'accueil disent les heures, les titres et les
    // affiches de l'année : le Rétro se charge dès qu'il est disponible.
    final status = _status;
    if (status == null || !status.available) return;
    try {
      await loadReport(status.year);
    } catch (e) {
      debugPrint('RetroProvider: Rétro indisponible pour l’accueil: $e');
    }
  }

  /// Le Rétro de [year], depuis la mémoire s'il est déjà là. Une erreur
  /// remonte à l'écran, qui propose de réessayer.
  Future<RetroReport> loadReport(int year) async {
    final cached = _report;
    if (cached != null && cached.year == year) return cached;
    final request = _request;
    final fresh = await apiClient.getRetro(year);
    if (!_disposed && request == _request) {
      _report = fresh;
      notifyListeners();
    }
    return fresh;
  }

  /// Le Rétro a été ouvert. Marqué ici tout de suite, pour que l'accueil
  /// change sans attendre ; un échec réseau se rattrape à la prochaine
  /// ouverture.
  Future<void> markSeen(int year) async {
    final current = _status;
    if (current != null && current.year == year && !current.seen) {
      _status = current.copyWith(seen: true);
      notifyListeners();
    }
    try {
      await apiClient.markRetroSeen(year);
    } catch (e) {
      debugPrint('RetroProvider: « vu » non enregistré: $e');
    }
  }

  /// Vide l'état du serveur qu'on quitte. Voir `LibraryProvider.reset`.
  void reset() {
    _request++;
    _status = null;
    _report = null;
    _later = false;
    notifyListeners();
    unawaited(load());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
