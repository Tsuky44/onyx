import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_motion.dart';
import 'onyx_menu.dart';
import 'onyx_menu_panel.dart';

/// Ouvre le menu d'[items] collé au widget de [anchorKey] et rend la ligne
/// choisie, ou nul si le menu se ferme sans choix. Le choix est enveloppé :
/// une valeur nulle reste un choix.
///
/// [OnyxMenuButton] l'appelle ; un déclencheur qui ne peut pas être un
/// `OnyxMenuButton` (un clic droit, un raccourci) peut l'appeler lui-même.
Future<({T value})?> showOnyxMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<OnyxMenuItem<T>> items,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize || overlay == null) {
    return null;
  }
  final anchor = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final returnFocus = FocusManager.instance.primaryFocus;
  // Ouvert à la souris ou au doigt, aucune ligne n'est allumée ; au clavier,
  // le focus entre dans le menu.
  final byKeyboard =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  final index = await navigator.push<int>(_OnyxMenuRoute<T>(
    anchor: anchor,
    items: items,
    focusFirst: byKeyboard,
    barrierLabel: tr('Fermer'),
  ));

  final node = returnFocus;
  if (node != null &&
      node.context != null &&
      node.context!.mounted &&
      node.canRequestFocus &&
      !node.hasFocus) {
    node.requestFocus();
  }
  if (index == null || index < 0 || index >= items.length) return null;
  return (value: items[index].value);
}

class _OnyxMenuRoute<T> extends PopupRoute<int> {
  _OnyxMenuRoute({
    required this.anchor,
    required this.items,
    required this.focusFirst,
    required this.barrierLabel,
  });

  /// Le déclencheur, dans le repère de l'overlay où la route se pose.
  final Rect anchor;
  final List<OnyxMenuItem<T>> items;
  final bool focusFirst;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => AppMotion.standard;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final metrics = OnyxMenuMetrics.of(context);
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, constraints) {
        final placement = OnyxMenuPlacement.resolve(
          anchor: anchor,
          screen: constraints.biggest,
          padding: MediaQuery.paddingOf(context),
          panelHeight: metrics.heightOf(items),
        );
        return CustomSingleChildLayout(
          delegate: _PlacementLayout(placement),
          child: _Reveal(
            animation: animation,
            alignment: placement.growFrom,
            child: OnyxMenuPanel<T>(
              items: items,
              metrics: metrics,
              focusFirst: focusFirst,
              onPick: (i) => Navigator.of(context).pop(i),
            ),
          ),
        );
      }),
    );
  }

  // Le fondu et l'échelle se posent dans la page, où l'on sait de quel coin
  // le menu pousse.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Fondu, et échelle de 0,96 à 1 depuis le coin collé au bouton. Sous
/// « réduire les animations », le fondu seul.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    final fade = FadeTransition(opacity: curved, child: child);
    if (AppMotion.reduced(context)) return fade;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
      alignment: alignment,
      child: fade,
    );
  }
}

/// Où le menu se pose par rapport à son bouton : dessous s'il tient, dessus
/// sinon (ou du côté qui a le plus de place) ; aligné sur le bord du bouton
/// qui regarde le centre de l'écran, pour s'ouvrir vers l'espace libre.
@immutable
class OnyxMenuPlacement {
  const OnyxMenuPlacement({
    required this.anchor,
    required this.below,
    required this.alignLeft,
    required this.maxHeight,
  });

  static const double gap = 6;
  static const double margin = 12;

  final Rect anchor;
  final bool below;

  /// Le bord gauche du menu sur celui du bouton ; sinon, les bords droits.
  final bool alignLeft;
  final double maxHeight;

  static OnyxMenuPlacement resolve({
    required Rect anchor,
    required Size screen,
    required EdgeInsets padding,
    required double panelHeight,
  }) {
    final spaceBelow =
        screen.height - padding.bottom - margin - (anchor.bottom + gap);
    final spaceAbove = anchor.top - gap - padding.top - margin;
    final below = panelHeight <= spaceBelow || spaceBelow >= spaceAbove;
    return OnyxMenuPlacement(
      anchor: anchor,
      below: below,
      alignLeft: anchor.center.dx < screen.width / 2,
      maxHeight: math.max(0, below ? spaceBelow : spaceAbove),
    );
  }

  /// Le coin du menu collé au bouton, d'où l'échelle part.
  Alignment get growFrom => switch ((below, alignLeft)) {
        (true, true) => Alignment.topLeft,
        (true, false) => Alignment.topRight,
        (false, true) => Alignment.bottomLeft,
        (false, false) => Alignment.bottomRight,
      };

  /// Le coin haut-gauche d'un menu de [child] dans un écran de [size],
  /// ramené dans l'écran.
  Offset position(Size size, Size child) {
    final x = alignLeft ? anchor.left : anchor.right - child.width;
    final y = below ? anchor.bottom + gap : anchor.top - gap - child.height;
    return Offset(
      x.clamp(margin, math.max(margin, size.width - margin - child.width)),
      y.clamp(margin, math.max(margin, size.height - margin - child.height)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnyxMenuPlacement &&
      other.anchor == anchor &&
      other.below == below &&
      other.alignLeft == alignLeft &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(anchor, below, alignLeft, maxHeight);
}

class _PlacementLayout extends SingleChildLayoutDelegate {
  _PlacementLayout(this.placement);

  final OnyxMenuPlacement placement;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth:
            math.max(0, constraints.maxWidth - 2 * OnyxMenuPlacement.margin),
        maxHeight: placement.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placement.position(size, childSize);

  @override
  bool shouldRelayout(_PlacementLayout oldDelegate) =>
      oldDelegate.placement != placement;
}
