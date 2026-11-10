import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

import 'tv_rail_start.dart';

/// Une rangée sous dpad (`TvRegion.rail`) qu'on entre toujours par sa
/// première carte ([TvRailStart], ADR-0113).
///
/// dpad n'a pas cette entrée : `restore` rend la carte quittée la dernière
/// fois, sinon la plus proche ; `entry` demanderait à chaque rangée de marquer
/// sa première carte, et à chaque carte de savoir qu'elle l'est.
///
/// S'appuie sur `DpadRegionState.resolveEnter`, marqué `@internal` dans
/// dpad 3.3.0, comme `TvPaneRegion` : à relire à chaque montée de version
/// (ADR-0110).
class TvRailRegion extends DpadRegion {
  const TvRailRegion({
    super.key,
    required super.child,
    super.memoryKey,
    super.debugLabel,
  }) : super(
          enter: DpadEnterBehavior.restore,
          horizontalEdge: DpadEdgeBehavior.stop,
          verticalEdge: DpadEdgeBehavior.leave,
        );

  @override
  DpadRegionState createState() => _TvRailRegionState();
}

class _TvRailRegionState extends DpadRegionState {
  @override
  // ignore: invalid_use_of_internal_member
  FocusNode resolveEnter(FocusNode nearest, List<FocusNode> candidates) =>
      TvRailStart.enter(candidates, current: _cards) ?? nearest;

  /// Les cartes de cette rangée atteignables maintenant.
  Iterable<FocusNode> _cards() =>
      FocusManager.instance.rootScope.traversalDescendants
          .where((node) => identical(DpadRegion.ofNode(node), this));
}
