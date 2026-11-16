import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// Fondu, et échelle de 0,96 à 1 depuis le coin collé au bouton. Sous
/// « réduire les animations », le fondu seul.
class OnyxPanelReveal extends StatelessWidget {
  const OnyxPanelReveal({
    super.key,
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

class OnyxPanelPlacementLayout extends SingleChildLayoutDelegate {
  OnyxPanelPlacementLayout(this.placement);

  final OnyxMenuPlacement placement;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          constraints.maxWidth - 2 * OnyxMenuPlacement.margin,
        ),
        maxHeight: placement.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placement.position(size, childSize);

  @override
  bool shouldRelayout(OnyxPanelPlacementLayout oldDelegate) =>
      oldDelegate.placement != placement;
}

/// Le rectangle de [context] dans le repère de l'overlay racine, ou nul si le
/// widget n'est pas (ou plus) posé.
Rect? onyxAnchorRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(
    context,
    rootNavigator: true,
  ).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize || overlay == null) {
    return null;
  }
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
}

/// La matière du menu du compte (ADR-0126, ADR-0130) : fond élevé, filet
/// `glassBorder`, ombre, rayon 16. Les menus et les panneaux ancrés
/// (ADR-0131) la partagent ; ne la copiez pas.
class OnyxPanelSurface extends StatelessWidget {
  const OnyxPanelSurface({super.key, required this.child});

  static const double radius = 16;

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: child,
      );
}
