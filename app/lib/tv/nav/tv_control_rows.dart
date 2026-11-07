import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

/// Les rangées de commandes d'un chrome de lecteur, sous dpad
/// (`TvRegion.controlRows`, phase 7 de l'ADR-0110).
///
/// Ce n'est pas une zone : les zones de dpad ne s'emboîtent pas (constat
/// C15), et chaque rangée est la sienne ([TvControlRowRegion]). Ce widget ne
/// fait que les recenser, pour que Haut et Bas passent d'une rangée à la
/// suivante **dans l'ordre de l'écran**.
///
/// C'est ce que la géométrie seule de dpad ne donne pas sur le chrome télé :
/// la barre de progression prend toute la largeur et la lecture est au
/// centre. Depuis « Réglages », en haut à droite, la barre est dans le
/// faisceau et la lecture ne l'est pas : Bas sautait toute la rangée du
/// milieu. L'ancien `TvFocusRows` faisait déjà cet ordre explicite.
class TvControlRows extends StatefulWidget {
  const TvControlRows({super.key, required this.child});

  final Widget child;

  @override
  State<TvControlRows> createState() => _TvControlRowsState();
}

class _TvControlRowsState extends State<TvControlRows> {
  final List<TvControlRowState> _rows = <TvControlRowState>[];

  @override
  Widget build(BuildContext context) =>
      _TvControlRowsScope(state: this, child: widget.child);
}

class _TvControlRowsScope extends InheritedWidget {
  const _TvControlRowsScope({required this.state, required super.child});

  final _TvControlRowsState state;

  @override
  bool updateShouldNotify(_TvControlRowsScope oldWidget) =>
      !identical(oldWidget.state, state);
}

/// Une rangée de commandes (`TvRegion.controls`) : une `DpadRegion` dont
/// gauche et droite s'arrêtent aux bords, et que Haut et Bas quittent pour
/// la rangée voisine de [TvControlRows].
///
/// On y entre sur [preferredFocus] (la lecture au milieu, la barre en bas),
/// sinon sur l'élément le plus proche, à l'horizontale, de celui qu'on quitte.
/// Pas de mémoire : le chrome est un instrument, et la lecture doit être
/// sous le doigt à chaque fois qu'on revient sur la rangée du milieu.
///
/// S'appuie, comme `TvPaneRegion`, sur `DpadRegionState.resolveEnter`
/// (`@internal` dans dpad 3.3.0) et sur une sous-classe de
/// `DpadTraversalPolicy` : à relire à chaque montée de version.
class TvControlRowRegion extends DpadRegion {
  TvControlRowRegion({
    super.key,
    required Widget child,
    this.preferredFocus,
    super.debugLabel,
  }) : super(
         child: _RowPolicyGroup(child: child),
         enter: DpadEnterBehavior.entry,
         horizontalEdge: DpadEdgeBehavior.stop,
         verticalEdge: DpadEdgeBehavior.leave,
       );

  /// Où l'on arrive en entrant dans la rangée.
  final FocusNode? preferredFocus;

  @override
  DpadRegionState createState() => TvControlRowState();
}

/// L'état d'une [TvControlRowRegion], inscrit auprès de ses [TvControlRows].
class TvControlRowState extends DpadRegionState {
  _TvControlRowsState? _rows;

  TvControlRowRegion get _row => widget as TvControlRowRegion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rows = context
        .getInheritedWidgetOfExactType<_TvControlRowsScope>()
        ?.state;
    if (identical(rows, _rows)) return;
    _rows?._rows.remove(this);
    _rows = rows;
    if (rows != null && !rows._rows.contains(this)) rows._rows.add(this);
  }

  @override
  void dispose() {
    _rows?._rows.remove(this);
    super.dispose();
  }

  /// Ce que la télécommande peut atteindre dans la rangée. Vide quand elle
  /// est masquée : un `ExcludeFocus` au-dessus retire ses éléments du
  /// parcours.
  List<FocusNode> _candidates(FocusScopeNode scope) => [
    for (final node in scope.traversalDescendants)
      if (node.canRequestFocus &&
          node.context != null &&
          identical(DpadRegion.ofNode(node), this))
        node,
  ];

  /// Le milieu de la rangée, à la verticale, dans le repère de l'écran.
  double? get _centerY {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero)).dy;
  }

  FocusNode _entryFor(List<FocusNode> candidates, double fromX) {
    final preferred = _row.preferredFocus;
    if (preferred != null && candidates.contains(preferred)) return preferred;
    return candidates.reduce(
      (best, node) =>
          (node.rect.center.dx - fromX).abs() <
              (best.rect.center.dx - fromX).abs()
          ? node
          : best,
    );
  }

  @override
  // ignore: invalid_use_of_internal_member
  FocusNode resolveEnter(FocusNode nearest, List<FocusNode> candidates) {
    final preferred = _row.preferredFocus;
    if (preferred != null && candidates.contains(preferred)) return preferred;
    return nearest;
  }

  /// La cible de Haut ([step] = -1) ou Bas (1) depuis [current] : l'entrée de
  /// la rangée voisine qui a quelque chose à offrir. Nul au bord du chrome,
  /// ou hors d'un [TvControlRows].
  FocusNode? _neighbour(FocusNode current, int step) {
    final rows = _rows;
    final scope = current.nearestScope;
    if (rows == null || scope == null) return null;
    final placed =
        <(TvControlRowState, double, List<FocusNode>)>[
            for (final row in rows._rows)
              if (row.mounted && row._centerY != null)
                (row, row._centerY!, row._candidates(scope)),
          ]
          ..removeWhere(
            (entry) => entry.$3.isEmpty && !identical(entry.$1, this),
          )
          ..sort((a, b) => a.$2.compareTo(b.$2));
    final index = placed.indexWhere((entry) => identical(entry.$1, this));
    if (index < 0) return null;
    final target = index + step;
    if (target < 0 || target >= placed.length) return null;
    final (row, _, candidates) = placed[target];
    return row._entryFor(candidates, current.rect.center.dx);
  }
}

class _RowPolicyGroup extends StatefulWidget {
  const _RowPolicyGroup({required this.child});

  final Widget child;

  @override
  State<_RowPolicyGroup> createState() => _RowPolicyGroupState();
}

class _RowPolicyGroupState extends State<_RowPolicyGroup> {
  /// Une seule instance : une politique neuve à chaque construction ferait
  /// reposer la sienne au groupe à chaque fois.
  final _RowPolicy _policy = _RowPolicy();

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: _policy, child: widget.child);
}

/// La politique d'une rangée : celle de dpad pour gauche et droite (bords
/// en mur), la rangée voisine dans l'ordre de l'écran pour Haut et Bas.
///
/// Non finale, comme celle de dpad : une instance vit dans un `State`.
// ignore: must_be_immutable
class _RowPolicy extends DpadTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final step = switch (direction) {
      TraversalDirection.up => -1,
      TraversalDirection.down => 1,
      TraversalDirection.left || TraversalDirection.right => 0,
    };
    final row = DpadRegion.ofNode(currentNode);
    if (step == 0 || row is! TvControlRowState || row._rows == null) {
      return super.inDirection(currentNode, direction);
    }
    final target = row._neighbour(currentNode, step);
    // Au bord du chrome, rien : ni l'en-tête de l'écran dessous, ni un
    // élément hors des rangées. Faux, pour que dpad le signale
    // (`onBlockedMove`) comme toute flèche bloquée.
    if (target == null) return false;
    final context = target.context;
    final dpad = context == null ? null : Dpad.maybeOf(context);
    // Le seul `requestFocus` de cette flèche ; celui de dpad note la cible
    // dans la mémoire de sa zone et la ramène à l'écran.
    if (dpad != null) return dpad.requestFocus(target);
    target.requestFocus();
    return true;
  }
}
