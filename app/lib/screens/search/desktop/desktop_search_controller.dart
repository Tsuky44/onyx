import 'package:flutter/widgets.dart';

import '../search_layout.dart';
import 'desktop_search_hits.dart';

/// Ce que partagent le champ de l'en-tête et la feuille de résultats du
/// bureau : le titre sélectionné, la pastille, et ce qu'Entrée en fait.
///
/// Le champ garde le focus du début à la fin : les flèches et Entrée y sont
/// tapées, et c'est ce contrôleur qui les porte jusqu'à la grille. Ainsi on
/// corrige sa frappe à tout moment sans avoir à « revenir » dans le champ.
///
/// Notifie à chaque changement de sélection, et seulement là : les cartes et
/// l'aperçu l'écoutent un par un, la grille ne se reconstruit pas pour une
/// flèche (ADR-0025).
class DesktopSearchController extends ChangeNotifier {
  /// La pastille choisie. À part : changer de pastille reconstruit la grille.
  final ValueNotifier<SearchFilter> filter = ValueNotifier(SearchFilter.all);

  int _selected = 0;
  bool _browsing = false;
  List<int> _sections = const [];
  int _columns = 1;
  List<SearchHit> _hits = const [];

  /// Le rang du titre sélectionné dans [hits].
  int get selected => _selected;

  /// Vrai quand Bas a fait entrer les flèches dans la grille : Gauche et
  /// Droite y déplacent alors la sélection au lieu du curseur du champ.
  /// Avant, le premier titre est sélectionné sans anneau : c'est ce
  /// qu'Entrée ouvrirait.
  bool get browsing => _browsing;

  /// Les titres que la feuille affiche, dans l'ordre de la sélection.
  List<SearchHit> get hits => _hits;

  /// Le titre sélectionné, ou null quand la grille est vide.
  SearchHit? get current => _selected < _hits.length ? _hits[_selected] : null;

  /// La feuille dit ce qu'elle affiche, à chaque construction. Silencieux :
  /// appelé pendant une construction, il ne peut prévenir personne.
  void show(SearchLayout layout) {
    _hits = layout.hits;
    _sections = layout.sections;
    if (_selected >= _hits.length) {
      _selected = _hits.isEmpty ? 0 : _hits.length - 1;
    }
    if (_hits.isEmpty) _browsing = false;
  }

  /// La largeur de la grille a changé. Silencieux, pour la même raison.
  void layoutColumns(int columns) => _columns = columns < 1 ? 1 : columns;

  /// Une nouvelle frappe : la sélection repart du premier titre, et la
  /// pastille de « Tout » — une pastille gardée d'une recherche à l'autre
  /// cachait des résultats qu'on n'avait pas choisi de cacher.
  void restart() {
    _selected = 0;
    _browsing = false;
    filter.value = SearchFilter.all;
    notifyListeners();
  }

  void setFilter(SearchFilter value) {
    if (filter.value == value) return;
    _selected = 0;
    _browsing = false;
    filter.value = value;
    notifyListeners();
  }

  /// Le pointeur s'est posé sur une carte : elle devient la sélection, sans
  /// changer le sens des flèches.
  void point(int index) {
    if (index == _selected || index >= _hits.length) return;
    _selected = index;
    notifyListeners();
  }

  /// Une flèche tapée dans le champ. Vrai quand elle est prise par la
  /// grille ; fausse, le champ lui garde son sens (déplacer le curseur).
  bool arrow(TraversalDirection direction) {
    if (_hits.isEmpty) return false;
    if (!_browsing) {
      if (direction != TraversalDirection.down) return false;
      _browsing = true;
      notifyListeners();
      return true;
    }
    final next = stepSelection(
      sections: _sections,
      columns: _columns,
      index: _selected,
      direction: direction,
    );
    if (next == null) {
      _browsing = false;
    } else {
      _selected = next;
    }
    notifyListeners();
    return true;
  }

  ActivateHit? _onActivate;

  /// La feuille ouverte reçoit Entrée : elle seule sait ouvrir une fiche
  /// depuis la carte, pour que l'affiche s'envole de là.
  void attach(ActivateHit onActivate) => _onActivate = onActivate;

  void detach(ActivateHit onActivate) {
    if (identical(_onActivate, onActivate)) _onActivate = null;
  }

  /// Entrée (ouvrir la fiche) ou Ctrl + Entrée ([play] : lancer le film).
  void activate({required bool play}) => _onActivate?.call(play: play);

  @override
  void dispose() {
    filter.dispose();
    super.dispose();
  }
}

/// Ce qu'Entrée fait du titre sélectionné.
typedef ActivateHit = void Function({required bool play});
