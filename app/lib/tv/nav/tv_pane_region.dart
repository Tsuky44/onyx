import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

import 'tv_contained_steps.dart';

/// Un volet sous dpad (`TvRegion.pane`) : une `DpadRegion` qui reprend les
/// trois règles de l'ancien `TvFocusPanes`, que dpad n'a pas.
///
/// - **Sans souvenir, on entre sur le premier élément** — le plus haut, puis
///   le plus à gauche — et non sur le plus proche de celui qu'on quitte.
///   Depuis « Téléchargements », en cinquième place de la liste des réglages,
///   droite tombait au milieu de la page, sur un réglage pris au hasard de la
///   hauteur, par-dessus ceux qui l'introduisent. dpad n'a pas cette entrée
///   (`restore` sans mémoire retombe sur l'élément `entry`, puis sur le plus
///   proche, constat C8) ; marquer le premier réglage de chaque page en
///   `entry` demanderait à chacune de savoir lequel est en haut.
/// - **Le souvenir est le dernier élément focalisé du volet**, quel qu'il
///   soit. dpad ne note que ce qu'il focalise lui-même et ses propres cibles ;
///   les lignes des réglages sont des `InkWell`, et une catégorie focalisée
///   autrement (au toucher, par `autofocus`) ne laissait aucun souvenir :
///   gauche depuis la page revenait en haut de la liste. Une page remplacée
///   par une autre n'a plus cet élément, et l'on entre de nouveau par le haut.
/// - **Droite entre dans le bouton posé au bout d'une ligne cliquable,
///   gauche en ressort** (le menu d'heure de « Plage horaire »,
///   [TvContainedSteps]) : les lignes des réglages sont des `InkWell`, pas
///   des `TvFocusable` qui sauraient le faire ([TvPanePolicy]).
///
/// S'appuie sur `DpadRegionState.resolveEnter`, marqué `@internal` dans
/// dpad 3.3.0, et sur une sous-classe de `DpadTraversalPolicy` : à relire à
/// chaque montée de version (ADR-0110).
class TvPaneRegion extends DpadRegion {
  TvPaneRegion({
    super.key,
    required Widget child,
    super.memoryKey,
    super.debugLabel,
  }) : super(
          child: _PanePolicyGroup(child: child),
          enter: DpadEnterBehavior.restore,
          horizontalEdge: DpadEdgeBehavior.leave,
          // Haut et bas ne quittent pas un volet : en bas d'une page de
          // réglages, Bas tombait sur une catégorie de la liste d'à côté, qui
          // s'ouvrait aussitôt.
          verticalEdge: DpadEdgeBehavior.stop,
        );

  /// Le premier de [candidates] dans l'ordre de lecture : le plus haut, puis
  /// le plus à gauche. Nul si aucun n'est posé à l'écran.
  static FocusNode? firstOf(Iterable<FocusNode> candidates) {
    FocusNode? best;
    for (final node in candidates) {
      if (!_placed(node)) continue;
      if (best == null) {
        best = node;
        continue;
      }
      final byTop = node.rect.top.compareTo(best.rect.top);
      if (byTop < 0 || (byTop == 0 && node.rect.left < best.rect.left)) {
        best = node;
      }
    }
    return best;
  }

  static bool _placed(FocusNode node) =>
      node.context != null && !node.rect.isEmpty;

  @override
  DpadRegionState createState() => _TvPaneRegionState();
}

class _TvPaneRegionState extends DpadRegionState {
  /// Le dernier élément focalisé dans ce volet.
  FocusNode? _last;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_noteFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_noteFocus);
    super.dispose();
  }

  void _noteFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) return;
    if (identical(DpadRegion.ofNode(primary), this)) _last = primary;
  }

  @override
  // ignore: invalid_use_of_internal_member
  FocusNode resolveEnter(FocusNode nearest, List<FocusNode> candidates) {
    final last = _last;
    if (last != null && candidates.contains(last)) return last;
    final remembered = lastFocused;
    if (remembered != null && candidates.contains(remembered)) {
      return remembered;
    }
    return TvPaneRegion.firstOf(candidates) ?? nearest;
  }
}

/// Le groupe de [TvPanePolicy], sous celui que pose la `DpadRegion` : c'est
/// le groupe le plus proche du focus qui décide d'une flèche.
class _PanePolicyGroup extends StatefulWidget {
  const _PanePolicyGroup({required this.child});

  final Widget child;

  @override
  State<_PanePolicyGroup> createState() => _PanePolicyGroupState();
}

class _PanePolicyGroupState extends State<_PanePolicyGroup> {
  /// Une seule instance : une politique neuve à chaque construction ferait
  /// reposer la sienne au groupe à chaque fois.
  final TvPanePolicy _policy = TvPanePolicy();

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: _policy, child: widget.child);
}

/// La politique de parcours d'un volet : celle de dpad, plus le passage
/// entre une ligne cliquable et le bouton qu'elle contient. Gauche et droite
/// seulement ; haut et bas restent à dpad.
///
/// Non finale, comme celle de dpad : une instance vit dans un `State`.
// ignore: must_be_immutable
class TvPanePolicy extends DpadTraversalPolicy {
  TvPanePolicy();

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      return super.inDirection(currentNode, direction);
    }
    final step = direction == TraversalDirection.right
        ? TvContainedSteps.into(currentNode)
        : TvContainedSteps.outOf(currentNode);
    if (step != null) {
      step.requestFocus();
      return true;
    }
    if (!_lineGoesOn(currentNode, direction) &&
        _leavePane(currentNode, direction)) {
      return true;
    }
    return super.inDirection(currentNode, direction);
  }

  /// Vrai si la ligne de [node] a encore, dans ce volet, un élément vers
  /// [direction] : un élément qui chevauche sa hauteur.
  ///
  /// dpad, au bord d'une zone qui « sort », ne sort que s'il n'y reste rien
  /// vers [direction], même très loin hors de la ligne. Dans la page Lecture,
  /// gauche depuis le menu « Langue audio par défaut » (posé au bout de sa
  /// ligne) tombait ainsi sur une puce de « Décodage matériel », trois écrans
  /// plus bas, au lieu de rendre la catégorie : le groupe n'existe pas sur
  /// les appareils Apple, et la panne ne se voyait que sous Android et Linux.
  bool _lineGoesOn(FocusNode node, TraversalDirection direction) {
    final scope = node.nearestScope;
    final region = DpadRegion.ofNode(node);
    if (scope == null || region == null) return true;
    final source = node.rect;
    return scope.traversalDescendants.any((other) =>
        !identical(other, node) &&
        identical(DpadRegion.ofNode(other), region) &&
        TvPaneRegion._placed(other) &&
        _ahead(source, other.rect, direction) &&
        _sameLine(source, other.rect));
  }

  /// Sort du volet vers [direction] : la cible la plus proche hors de lui,
  /// la ligne d'abord, puis l'entrée de sa zone (la catégorie quittée, pour
  /// la liste des réglages). Faux s'il n'y a rien hors du volet.
  bool _leavePane(FocusNode node, TraversalDirection direction) {
    final scope = node.nearestScope;
    final region = DpadRegion.ofNode(node);
    if (scope == null) return false;
    final source = node.rect;
    final outside = scope.traversalDescendants
        .where((other) =>
            !identical(other, node) &&
            !identical(DpadRegion.ofNode(other), region) &&
            TvPaneRegion._placed(other))
        .toList();

    FocusNode? nearest;
    var nearestOnLine = false;
    var nearestScore = double.infinity;
    for (final other in outside) {
      final rect = other.rect;
      if (!_ahead(source, rect, direction)) continue;
      final onLine = _sameLine(source, rect);
      final major = direction == TraversalDirection.left
          ? source.left - rect.right
          : rect.left - source.right;
      final minor = (rect.center.dy - source.center.dy).abs();
      final clamped = major < 0 ? 0.0 : major;
      // La distance de dpad (celle de `FocusFinder` d'Android) : l'avancée
      // compte treize fois plus que l'écart en travers.
      final score = 13 * clamped * clamped + minor * minor;
      if (nearest == null ||
          (onLine && !nearestOnLine) ||
          (onLine == nearestOnLine && score < nearestScore)) {
        nearest = other;
        nearestOnLine = onLine;
        nearestScore = score;
      }
    }
    if (nearest == null) return false;

    var target = nearest;
    final targetRegion = DpadRegion.ofNode(nearest);
    if (targetRegion != null) {
      // ignore: invalid_use_of_internal_member
      target = targetRegion.resolveEnter(
        nearest,
        outside
            .where((other) => identical(DpadRegion.ofNode(other), targetRegion))
            .toList(),
      );
    }
    final context = target.context;
    final dpad = context == null ? null : Dpad.maybeOf(context);
    if (dpad == null) {
      target.requestFocus();
      return true;
    }
    dpad.requestFocus(target);
    dpad.ensureVisible(node: target);
    return true;
  }

  /// [candidate] est vers [direction] depuis [source] : la règle de dpad.
  static bool _ahead(
      Rect source, Rect candidate, TraversalDirection direction) {
    if (direction == TraversalDirection.left) {
      return (source.right > candidate.right ||
              source.left >= candidate.right) &&
          source.left > candidate.left;
    }
    return (source.left < candidate.left || source.right <= candidate.left) &&
        source.right < candidate.right;
  }

  static bool _sameLine(Rect source, Rect candidate) =>
      candidate.bottom > source.top && candidate.top < source.bottom;
}
