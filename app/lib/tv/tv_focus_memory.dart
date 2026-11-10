import 'package:flutter/widgets.dart';

import 'nav/tv_rail_start.dart';
import 'tv_focus_entry.dart';
import 'tv_mode.dart';

/// Une zone qui se souvient de l'élément sur lequel la télécommande était.
///
/// C'est la logique attendue des rangées sur un téléviseur : descendre vers
/// une rangée puis remonter ramène sur l'affiche où l'on était, et non sur
/// celle qui se trouve géométriquement au-dessus. Sans
/// cela, parcourir l'accueil revient à perdre sa place dans chaque rangée à
/// chaque passage — on avance de dix affiches, on descend voir la rangée
/// suivante, on remonte, et l'on est revenu au début.
///
/// Même chose à l'échelle d'un onglet : quitter le contenu pour l'en-tête puis
/// y redescendre ramène à l'endroit exact d'où l'on est parti.
///
/// Le principe : chaque [TvFocusable] déclare à la mémoire la plus proche qu'il
/// vient de prendre le focus. La zone s'inscrit auprès de [TvFocusEntries] ;
/// quand le parcours directionnel a trouvé un élément de la zone depuis
/// l'extérieur, la politique de parcours lui demande l'élément mémorisé et ne
/// pose le focus qu'une fois, dessus — la redirection ne passe plus par un
/// second `requestFocus` après coup (ADR-0109). La première visite, rien n'est
/// mémorisé, et le parcours directionnel de Flutter garde la main.
///
/// Les rangées de l'accueil n'en profitent plus pour leur entrée : on y entre
/// par la première carte ([TvFocusMemory.entersAtStart], ADR-0113).
///
/// Les mémoires s'emboîtent : une rangée dans un onglet signale aussi l'élément
/// à l'onglet. Hors téléviseur, la zone ne redirige jamais rien.
class TvFocusMemory extends StatefulWidget {
  const TvFocusMemory({
    super.key,
    required this.child,
    this.entersAtTop = false,
    this.entersAtStart = false,
  });

  final Widget child;

  /// À la première visite, le focus entre sur le premier élément visible de
  /// la zone — le plus proche de son coin haut-gauche — au lieu du plus proche
  /// de l'élément quitté.
  ///
  /// Pour le contenu d'un onglet, sous l'en-tête : Bas depuis la recherche,
  /// à droite de l'en-tête, tombait sur « Voir tout » d'une rangée plus bas,
  /// seul élément à sa verticale, par-dessus le bandeau et la première
  /// rangée.
  final bool entersAtTop;

  /// Une rangée : on y entre toujours par la première carte, à chaque visite
  /// ([TvRailStart], ADR-0113). La mémoire continue de renseigner la zone
  /// parente.
  final bool entersAtStart;

  /// La mémoire la plus proche au-dessus de [context], s'il y en a une.
  ///
  /// Sans dépendance : un élément qui prend le focus n'a pas à se reconstruire
  /// quand la mémoire change.
  static TvFocusMemoryState? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_TvFocusMemoryScope>()?.state;
  }

  @override
  State<TvFocusMemory> createState() => TvFocusMemoryState();
}

class TvFocusMemoryState extends State<TvFocusMemory> {
  final FocusNode _node = FocusNode(
    debugLabel: 'tv-focus-memory',
    canRequestFocus: false,
    skipTraversal: true,
  );

  FocusNode? _remembered;
  TvFocusMemoryState? _parent;

  /// L'élément que la zone rendra au prochain retour. Exposé pour les tests.
  @visibleForTesting
  FocusNode? get remembered => _remembered;

  @override
  void initState() {
    super.initState();
    TvFocusEntries.register(_node, entryFor);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parent = TvFocusMemory.maybeOf(context);
  }

  @override
  void dispose() {
    TvFocusEntries.unregister(_node);
    // Plus aucun nœud à rendre : la zone et ses éléments partent ensemble, et
    // une référence gardée ici retiendrait le dernier nœud mémorisé.
    _remembered = null;
    _parent = null;
    _node.dispose();
    super.dispose();
  }

  /// Appelé par un élément qui vient de recevoir le focus.
  void remember(FocusNode node) {
    _remembered = node;
    _parent?.remember(node);
  }

  /// Appelé par un élément qui quitte l'arbre : son nœud va être détruit, et
  /// demander le focus sur un nœud détruit est une erreur.
  void forget(FocusNode node) {
    if (identical(_remembered, node)) _remembered = null;
    _parent?.forget(node);
  }

  /// Où le focus entre dans la zone, quand le parcours a trouvé [landed] depuis
  /// [from] : l'élément mémorisé, ou le premier visible à la première visite
  /// d'une zone [TvFocusMemory.entersAtTop]. Nul pour garder [landed] — un
  /// déplacement interne à la zone, ou rien à rendre.
  @visibleForTesting
  FocusNode? entryFor(FocusNode landed, FocusNode? from) {
    if (!TvMode.isTv) return null;
    if (from != null && from.ancestors.contains(_node)) return null;
    if (widget.entersAtStart) {
      final first = TvRailStart.enter(_node.traversalDescendants,
          current: () => _node.traversalDescendants);
      return identical(first, landed) ? null : first;
    }
    final target = _remembered;
    if (target == null) return widget.entersAtTop ? _enterAtTop() : null;
    if (identical(landed, target)) return null;
    // Encore dans l'arbre, encore dans cette zone, encore atteignable. Une
    // rangée rechargée a pu reconstruire ses cartes : on laisse alors le
    // parcours directionnel choisir, plutôt que de viser un fantôme.
    if (target.context == null ||
        !target.canRequestFocus ||
        !target.ancestors.contains(_node)) {
      _remembered = null;
      return null;
    }
    return target;
  }

  FocusNode? _enterAtTop() {
    final zone = _node.rect;
    final visible = _node.traversalDescendants
        .where((node) =>
            node.context != null &&
            !node.rect.isEmpty &&
            node.rect.top >= zone.top &&
            node.rect.top < zone.bottom)
        .toList();
    if (visible.isEmpty) return null;
    // Le plus proche du coin haut-gauche, et non le plus haut : un bouton posé
    // à droite du titre (le tri « Récents », « Mes demandes », « Nouvelle
    // liste ») est plus haut que la première affiche de quelques pixels, et il
    // prenait le focus d'entrée — l'onglet s'ouvrait à l'autre bout de
    // l'écran, et Bas descendait sur la dernière affiche de la rangée.
    double distance(FocusNode node) =>
        (node.rect.top - zone.top) + (node.rect.left - zone.left).abs();
    return visible.reduce((best, node) {
      final byDistance = distance(node).compareTo(distance(best));
      if (byDistance != 0) return byDistance < 0 ? node : best;
      return node.rect.top < best.rect.top ? node : best;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      child: _TvFocusMemoryScope(state: this, child: widget.child),
    );
  }
}

class _TvFocusMemoryScope extends InheritedWidget {
  const _TvFocusMemoryScope({required this.state, required super.child});

  final TvFocusMemoryState state;

  @override
  bool updateShouldNotify(_TvFocusMemoryScope oldWidget) =>
      !identical(oldWidget.state, state);
}
