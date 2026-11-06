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
          verticalEdge: DpadEdgeBehavior.leave,
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
    final step = switch (direction) {
      TraversalDirection.right => TvContainedSteps.into(currentNode),
      TraversalDirection.left => TvContainedSteps.outOf(currentNode),
      TraversalDirection.up || TraversalDirection.down => null,
    };
    if (step == null) return super.inDirection(currentNode, direction);
    step.requestFocus();
    return true;
  }
}
