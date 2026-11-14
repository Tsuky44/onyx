import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/media_request.dart';
import '../utils/search_match.dart';
import 'api_client.dart';

/// Ce que le catalogue de demandes (TMDB, lu par le serveur) connaît pour la
/// recherche en cours : de quoi montrer aussi les titres que le serveur n'a
/// pas (ADR-0129).
///
/// La bibliothèque répond à chaque frappe, sans réseau. Le catalogue, lui, est
/// une requête : elle part quand la frappe marque une pause ([debounce]), et
/// la réponse à une recherche que l'on a déjà quittée est jetée.
class UnavailableTitlesSearch extends ChangeNotifier {
  UnavailableTitlesSearch(
    this._api, {
    this.debounce = const Duration(milliseconds: 350),
  });

  final ApiClient _api;

  /// La pause dans la frappe qui déclenche la requête.
  final Duration debounce;

  /// En dessous, le catalogue répond les titres du moment, sans rapport avec
  /// ce qu'on tape : une lettre seule ne l'interroge pas.
  static const int minLength = 2;

  String _query = '';
  String _answered = '';
  List<RequestMediaItem> _answer = const [];
  Timer? _pause;
  int _generation = 0;
  bool _disposed = false;

  /// Cherche [query] dans le catalogue, ou rien si le compte ne peut pas
  /// demander de titre ([enabled] faux) : lui montrer un titre absent ne
  /// mènerait nulle part.
  ///
  /// Ne prévient personne sur le coup, et peut donc s'appeler pendant une
  /// construction : les écouteurs le sont à l'arrivée de la réponse.
  void search(String query, {required bool enabled}) {
    final wanted = enabled ? query.trim() : '';
    if (wanted == _query) return;
    _query = wanted;
    _generation++;
    _pause?.cancel();
    _pause = null;
    if (wanted.length < minLength || wanted == _answered) return;
    final generation = _generation;
    _pause = Timer(debounce, () => _ask(wanted, generation));
  }

  /// Ce que le catalogue connaît pour [query], la recherche en cours.
  ///
  /// Entre deux réponses, la dernière reçue reste, réduite aux titres qui
  /// correspondent encore : le rayon ne clignote pas à chaque lettre.
  List<RequestMediaItem> resultsFor(String query) {
    final shown = query.trim();
    if (_query.isEmpty || shown.length < minLength) return const [];
    if (shown == _answered) return _answer;
    return [
      for (final item in _answer)
        if (searchMatchRank(item.title, shown) != null) item,
    ];
  }

  /// Redemande la recherche en cours, sans attendre de pause : au retour
  /// d'une fiche de demande, le statut d'un titre a pu changer.
  void refresh() {
    if (_query.length < minLength) return;
    _pause?.cancel();
    _pause = null;
    _ask(_query, ++_generation);
  }

  Future<void> _ask(String query, int generation) async {
    final List<RequestMediaItem> results;
    try {
      final page = await _api.getRequestCatalog(
        page: 1,
        type: 'all',
        query: query,
      );
      results = page.results;
    } catch (_) {
      // Sans catalogue (clé TMDB absente, serveur injoignable), la recherche
      // reste celle de la bibliothèque : rien à dire à l'écran.
      return;
    }
    if (_disposed || generation != _generation) return;
    _answered = query;
    _answer = results;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pause?.cancel();
    super.dispose();
  }
}
