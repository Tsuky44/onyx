import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../tv/tv_mode.dart';
import '../../tv/tv_ui_scale.dart';
import 'account_menu_panel.dart';

/// Ouvre le menu du compte sous le bouton [anchorKey], aligné sur son bord
/// droit. [panel] reçoit la fermeture à brancher sur ses choix ; rend le
/// choix fait, ou nul.
Future<AccountMenuChoice?> showAccountMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget Function(double scale, ValueChanged<AccountMenuChoice> pick)
      panel,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize || overlay == null) {
    return null;
  }
  // Mesuré dans le repère de l'overlay où la route se pose, comme le dos des
  // affiches (voir `showPosterFlipMenu`) : sur un téléviseur, la page de la
  // route est remise à l'échelle de la maquette.
  final anchor = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final returnFocus = FocusManager.instance.primaryFocus;

  final choice = await navigator.push<AccountMenuChoice>(_AccountMenuRoute(
    anchor: anchor,
    overlayWidth: overlay.size.width,
    panel: panel,
    barrierLabel: tr('Fermer'),
  ));

  // Sans choix, le focus revient au bouton : sous dpad, rien ne garantit que
  // la route le rende à celui d'où l'on venait.
  final node = returnFocus;
  if (choice == null &&
      node != null &&
      node.context != null &&
      node.context!.mounted &&
      node.canRequestFocus &&
      !node.hasFocus) {
    node.requestFocus();
  }
  return choice;
}

class _AccountMenuRoute extends PopupRoute<AccountMenuChoice> {
  _AccountMenuRoute({
    required this.anchor,
    required this.overlayWidth,
    required this.panel,
    required this.barrierLabel,
  });

  /// Le bouton, dans le repère de l'overlay (voir [overlayWidth]).
  final Rect anchor;
  final double overlayWidth;
  final Widget Function(double scale, ValueChanged<AccountMenuChoice> pick)
      panel;

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
    final tv = TvScope.of(context);
    final page = Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, constraints) {
        final screen = constraints.biggest;
        final k = overlayWidth > 0 ? screen.width / overlayWidth : 1.0;
        final button = Rect.fromLTRB(anchor.left * k, anchor.top * k,
            anchor.right * k, anchor.bottom * k);
        return CustomSingleChildLayout(
          delegate: _BelowAnchor(button, MediaQuery.paddingOf(context)),
          child: SingleChildScrollView(
            child: panel(
              // La page est déjà à l'échelle de la maquette ; un menu se lit
              // de plus loin qu'une page (voir [AppTheme.tvMenuBoost]).
              tv ? AppTheme.tvMenuBoost : 1,
              (choice) => Navigator.of(context).pop(choice),
            ),
          ),
        );
      }),
    );
    // Une route surgissante ne passe pas par le thème des transitions, qui
    // pose `TvUiScale` sur chaque page.
    return tv ? TvUiScale(child: page) : page;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    if (AppMotion.reduced(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: Alignment.topRight,
        child: child,
      ),
    );
  }
}

/// Le menu sous le bouton, son bord droit sur celui du bouton, sans sortir de
/// l'écran : sur un téléphone étroit, il glisse vers la gauche.
class _BelowAnchor extends SingleChildLayoutDelegate {
  _BelowAnchor(this.button, this.padding);

  final Rect button;
  final EdgeInsets padding;

  static const double _gap = 8;
  static const double _margin = 12;

  double get _top => button.bottom + _gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxHeight = constraints.maxHeight - _top - _margin - padding.bottom;
    return BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - 2 * _margin),
      maxHeight: math.max(0, maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = button.right.clamp(
      math.min(size.width, childSize.width + _margin),
      size.width - _margin,
    );
    return Offset(right - childSize.width, _top);
  }

  @override
  bool shouldRelayout(_BelowAnchor oldDelegate) =>
      oldDelegate.button != button || oldDelegate.padding != padding;
}
