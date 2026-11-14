import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_motion.dart';
import 'onyx_menu.dart';
import 'onyx_menu_panel.dart';
import 'onyx_panel_surface.dart';

export 'onyx_panel_surface.dart' show OnyxMenuPlacement;

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

  final index = await navigator.push<int>(
    _OnyxMenuRoute<T>(
      anchor: anchor,
      items: items,
      focusFirst: byKeyboard,
      barrierLabel: tr('Fermer'),
    ),
  );

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final placement = OnyxMenuPlacement.resolve(
            anchor: anchor,
            screen: constraints.biggest,
            padding: MediaQuery.paddingOf(context),
            panelHeight: metrics.heightOf(items),
          );
          return CustomSingleChildLayout(
            delegate: OnyxPanelPlacementLayout(placement),
            child: OnyxPanelReveal(
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
        },
      ),
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
