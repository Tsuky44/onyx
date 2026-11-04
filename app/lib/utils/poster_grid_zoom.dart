import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Combien d'affiches par ligne dans les grilles du catalogue : l'un des
/// quatre modes d'affichage de [presets], ou le choix automatique de
/// `AppLayout.posterGridCount` tant que rien n'a été choisi.
///
/// Un réglage de l'appareil, partagé par tous les écrans en grille (demandes,
/// bibliothèques, collections, listes, recherche) : on règle l'affichage une
/// fois, par le menu de `PosterGridDisplayMenu` ou par Ctrl + molette, et il
/// vaut partout.
///
/// Le choix est commun à toute l'application ; le choix automatique d'où il
/// part ne l'est pas. Chaque `PosterGridZoomRegion` a donc sa propre instance,
/// qui retient la base de sa grille : sans cela, deux pages empilées de
/// largeurs différentes se la disputeraient à chaque image.
class PosterGridZoom extends ChangeNotifier {
  PosterGridZoom() {
    _shared.addListener(notifyListeners);
  }

  /// Le zoom d'une grille hors de toute région : le choix enregistré vaut
  /// quand même.
  static final PosterGridZoom instance = PosterGridZoom();

  static const String _key = 'poster_grid_columns';

  /// Les quatre modes d'affichage, en nombre d'affiches par ligne.
  static const List<int> presets = [4, 6, 8, 10];

  /// Le nombre de colonnes choisi, ou null tant que la grille choisit seule.
  static final ValueNotifier<int?> _shared = ValueNotifier<int?>(null);
  static bool _loaded = false;

  int _base = 2;
  bool _baseNotifyQueued = false;
  bool _disposed = false;

  /// Nombre de colonnes affichées pour la dernière base reçue de la grille.
  int get columns => _shared.value ?? _base;

  /// Le mode d'affichage en vigueur, ou null quand le choix automatique tombe
  /// entre deux modes : le menu n'en coche alors aucun.
  int? get selected => presets.contains(columns) ? columns : null;

  /// Nombre de colonnes à afficher pour un choix automatique de [base].
  int apply(int base) {
    // Mémorisée pour que [step] parte de la grille réellement affichée. L'appel
    // a lieu en pleine mise en page : ceux qui lisent [columns] (le menu) sont
    // prévenus à l'image suivante.
    if (base != _base) {
      _base = base;
      _notifyAfterLayout();
    }
    return columns;
  }

  void _notifyAfterLayout() {
    if (_baseNotifyQueued) return;
    _baseNotifyQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _baseNotifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Lit le choix enregistré. Idempotent : chaque région de zoom l'appelle.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_key);
      _shared.value = presets.contains(saved) ? saved : null;
    } catch (_) {
      // Faute de disque, le choix vaut pour la séance.
    }
  }

  /// Un cran de molette : [columnsDelta] > 0 passe au mode suivant (plus
  /// d'affiches par ligne, donc plus petites), < 0 au précédent. À la butée,
  /// rien ne bouge.
  void step(int columnsDelta) {
    final current = columns;
    final next = columnsDelta > 0
        ? presets.where((p) => p > current)
        : presets.where((p) => p < current).toList().reversed;
    if (next.isNotEmpty) select(next.first);
  }

  /// Choisit l'un des modes de [presets].
  void select(int preset) {
    assert(presets.contains(preset), 'Mode d\'affichage inconnu : $preset');
    if (_shared.value == preset) return;
    _shared.value = preset;
    _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = _shared.value;
      if (value == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setInt(_key, value);
      }
    } catch (_) {
      // Faute de disque, le choix vaut pour la séance.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _shared.removeListener(notifyListeners);
    super.dispose();
  }

  @visibleForTesting
  void resetForTest() {
    _shared.value = null;
    _base = 2;
    _loaded = false;
  }
}

/// Rend le zoom observable depuis un `SliverLayoutBuilder` : celui qui lit
/// [PosterGridZoomScope.watch] dans son builder est reconstruit quand le zoom
/// change, sans que l'écran qui le contient ait à se reconstruire.
class PosterGridZoomScope extends InheritedNotifier<PosterGridZoom> {
  const PosterGridZoomScope({
    super.key,
    required PosterGridZoom zoom,
    required super.child,
  }) : super(notifier: zoom);

  /// Zoom de la région qui englobe [context], et abonnement à ses
  /// changements. Hors d'une région, le zoom enregistré vaut quand même.
  static PosterGridZoom watch(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<PosterGridZoomScope>();
    return scope?.notifier ?? PosterGridZoom.instance;
  }
}
