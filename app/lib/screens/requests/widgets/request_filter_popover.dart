import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../widgets/global/onyx_menu_panel.dart';
import '../../../widgets/global/onyx_menu_route.dart';

/// Ouvre, collé à la capsule de [anchorKey], un panneau qui reste ouvert
/// pendant qu'on y travaille : un choix multiple (genres, services) ou des
/// champs (période, durée). `showOnyxMenu` ferme le menu au premier choix ;
/// ici chaque changement part tout de suite vers l'écran, et le panneau se
/// ferme au clic dehors ou à Échap. Le placement est celui des menus Onyx
/// (`OnyxMenuPlacement`, ADR-0130).
///
/// [estimatedHeight] sert seulement à décider dessus ou dessous : le panneau
/// prend ensuite sa hauteur naturelle, plafonnée par l'espace disponible.
Future<void> showRequestFilterPopover({
  required BuildContext context,
  required GlobalKey anchorKey,
  required WidgetBuilder builder,
  double estimatedHeight = 360,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize || overlay == null) return;
  final anchor = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final returnFocus = FocusManager.instance.primaryFocus;
  await navigator.push<void>(_PopoverRoute(
    anchor: anchor,
    builder: builder,
    estimatedHeight: estimatedHeight,
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
}

/// La matière d'`OnyxMenuPanel` (panneau `surfaceElevated`, filet
/// `glassBorder`, ombre portée), pour un panneau qui porte des champs plutôt
/// que des lignes de menu.
class RequestPopoverSurface extends StatelessWidget {
  const RequestPopoverSurface({
    super.key,
    required this.child,
    this.width = 300,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(OnyxMenuMetrics.radius),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _PopoverRoute extends PopupRoute<void> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.estimatedHeight,
    required this.barrierLabel,
  });

  final Rect anchor;
  final WidgetBuilder builder;
  final double estimatedHeight;

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
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, constraints) {
        final placement = OnyxMenuPlacement.resolve(
          anchor: anchor,
          screen: constraints.biggest,
          padding: MediaQuery.paddingOf(context),
          panelHeight: estimatedHeight,
        );
        final curved =
            CurvedAnimation(parent: animation, curve: AppMotion.curve);
        Widget panel = FadeTransition(opacity: curved, child: builder(context));
        if (!AppMotion.reduced(context)) {
          panel = ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            alignment: placement.growFrom,
            child: panel,
          );
        }
        return CustomSingleChildLayout(
          delegate: _PlacementLayout(placement),
          child: panel,
        );
      }),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class _PlacementLayout extends SingleChildLayoutDelegate {
  _PlacementLayout(this.placement);

  final OnyxMenuPlacement placement;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - 2 * OnyxMenuPlacement.margin)
            .clamp(0, double.infinity),
        maxHeight: placement.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placement.position(size, childSize);

  @override
  bool shouldRelayout(_PlacementLayout oldDelegate) =>
      oldDelegate.placement != placement;
}
