import 'package:flutter/material.dart';

/// La recherche tapée dans la barre de navigation.
///
/// Sur grand écran la barre reste au-dessus de la page de résultats, qui lit
/// [query] ici pour suivre la frappe (`SearchResultsScreen.followingHeader`).
class SearchProvider extends ChangeNotifier {
  String _query = '';
  bool _expanded = false;

  String get query => _query;
  bool get isExpanded => _expanded;
  bool get isActive => _query.trim().isNotEmpty;

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  void clear() {
    _query = '';
    _expanded = false;
    notifyListeners();
  }
}
