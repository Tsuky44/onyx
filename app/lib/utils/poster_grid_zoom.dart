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
  PosterGridZoom({this.split = false}) {
    _store.addListener(notifyListeners);
  }

  /// La grille d'une vue partagée, à côté du volet d'une bibliothèque
  /// (ADR-0156) : ses modes et son choix sont les siens. Le « 6 par ligne »
  /// d'une grille pleine largeur y donnait des affiches deux fois plus
  /// petites qu'au téléviseur.
  final bool split;

  /// Le zoom d'une grille hors de toute région : le choix enregistré vaut
  /// quand même.
  static final PosterGridZoom instance = PosterGridZoom();

  static const String _key = 'poster_grid_columns';

  /// Les quatre modes d'affichage, en nombre d'affiches par ligne : tablette,
  /// ordinateur et navigateur.
  static const List<int> presets = [4, 6, 8, 10];

  /// Les trois modes d'un téléphone : au-delà de 4 par ligne, une affiche n'y
  /// est plus lisible (10 par ligne tenait sur une rangée de timbres-poste).
  static const List<int> phonePresets = [2, 3, 4];

  /// Les modes de la grille d'une vue partagée : de trois à six affiches à
  /// côté du volet, quatre comme au téléviseur par défaut.
  static const List<int> splitPresets = [3, 4, 5, 6];

  /// Les modes proposés sur un écran étroit ([phone], largeur < 600) ou large.
  static List<int> presetsFor({required bool phone}) =>
      phone ? phonePresets : presets;

  /// Le nombre de colonnes choisi, ou null tant que la grille choisit seule.
  static final ValueNotifier<int?> _shared = ValueNotifier<int?>(null);

  /// Le même, pour la grille d'une vue partagée.
  static final ValueNotifier<int?> _sharedSplit = ValueNotifier<int?>(null);
  static const String _splitKey = 'poster_grid_columns_split';
  static bool _loaded = false;

  ValueNotifier<int?> get _store => split ? _sharedSplit : _shared;

  int _base = 2;
  bool _phone = false;
  bool _baseNotifyQueued = false;
  bool _disposed = false;

  /// Les modes que le menu propose pour cette grille.
  List<int> get available => split ? splitPresets : presetsFor(phone: _phone);

  /// Nombre de colonnes affichées pour la dernière base reçue de la grille. Un
  /// choix hors des modes de l'écran (un 8 enregistré, puis une fenêtre
  /// étroite) est ignoré : la grille choisit seule, sans effacer le choix.
  int get columns {
    final chosen = _store.value;
    return chosen != null && available.contains(chosen) ? chosen : _base;
  }

  /// Le mode d'affichage en vigueur, ou null quand le choix automatique tombe
  /// entre deux modes : le menu n'en coche alors aucun.
  int? get selected => available.contains(columns) ? columns : null;

  /// Nombre de colonnes à afficher pour un choix automatique de [base] ;
  /// [phone] dit quels modes le choix peut prendre.
  int apply(int base, {bool phone = false}) {
    // Mémorisée pour que [step] parte de la grille réellement affichée. L'appel
    // a lieu en pleine mise en page : ceux qui lisent [columns] (le menu) sont
    // prévenus à l'image suivante.
    if (base != _base || phone != _phone) {
      _base = base;
      _phone = phone;
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
      _shared.value = presets.contains(saved) || phonePresets.contains(saved)
          ? saved
          : null;
      final savedSplit = prefs.getInt(_splitKey);
      _sharedSplit.value =
          splitPresets.contains(savedSplit) ? savedSplit : null;
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
        ? available.where((p) => p > current)
        : available.where((p) => p < current).toList().reversed;
    if (next.isNotEmpty) select(next.first);
  }

  /// Choisit l'un des modes de [presets] ou de [phonePresets].
  void select(int preset) {
    assert(
      available.contains(preset),
      'Mode d\'affichage inconnu : $preset',
    );
    if (_store.value == preset) return;
    _store.value = preset;
    _persist(split);
  }

  static Future<void> _persist(bool split) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = split ? _splitKey : _key;
      final value = (split ? _sharedSplit : _shared).value;
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, value);
      }
    } catch (_) {
      // Faute de disque, le choix vaut pour la séance.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _store.removeListener(notifyListeners);
    super.dispose();
  }

  @visibleForTesting
  void resetForTest() {
    _shared.value = null;
    _sharedSplit.value = null;
    _base = 2;
    _phone = false;
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
