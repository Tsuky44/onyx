import 'package:flutter/material.dart';

/// La recherche tapée dans l'en-tête du bureau.
///
/// L'en-tête reste au-dessus de la feuille de résultats, qui lit [query] ici
/// pour suivre la frappe (`DesktopSearchSheet`, ADR-0139).
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
