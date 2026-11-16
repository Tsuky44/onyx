import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_motion.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import 'onyx_panel_surface.dart';

/// Dit au contenu d'une feuille s'il est rendu dans un panneau (grand écran)
/// plutôt que dans une feuille du bas. Dans un panneau, le cadre — fond, filet,
/// ombre, rayon — vient du seam : le contenu n'a ni poignée, ni
/// `DraggableScrollableSheet`, ni fond propre. Voir ADR-0131.
class AdaptivePanelScope extends InheritedWidget {
  const AdaptivePanelScope({super.key, required super.child});

  static bool isPanel(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptivePanelScope>() != null;

  @override
  bool updateShouldNotify(AdaptivePanelScope oldWidget) => false;
}

/// Le seam des « feuilles du bas » : une feuille sur téléphone et sur
/// téléviseur, un panneau dans la matière des menus (ADR-0130) sur grand
/// écran.
///
/// [anchor] est le contexte du bouton qui ouvre ; le panneau se pose dessous
/// ou dessus, comme un `OnyxMenuButton`. Sans ancre posée, ou avec [centered],
/// le panneau est centré, à la largeur [width] : c'est le cas d'un contenu
/// trop grand pour un panneau collé à un bouton, une grille d'affiches par
/// exemple.
///
/// [estimatedHeight] sert seulement à choisir le côté (dessous ou dessus) ;
/// la hauteur réelle est celle du contenu, plafonnée à la place disponible.
///
/// Sur la feuille, [sheetColor] et [dragHandle] reprennent les réglages de
/// `showModalBottomSheet` ; sans [sheetColor], la feuille est transparente et
/// le contenu dessine son propre cadre.
Future<T?> showAdaptivePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BuildContext? anchor,
  double width = 280,
  bool centered = false,
  double estimatedHeight = 360,
  Color? sheetColor,
  bool dragHandle = false,
}) {
  if (TvScope.of(context) || AppLayout.isCompact(context)) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: sheetColor ?? Colors.transparent,
      showDragHandle: dragHandle,
      builder: builder,
    );
  }
  final rect = centered ? null : onyxAnchorRect(anchor ?? context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _AdaptivePanelRoute<T>(
      anchor: rect,
      builder: builder,
      width: width,
      estimatedHeight: estimatedHeight,
      barrierLabel: tr('Fermer'),
    ),
  );
}

class _AdaptivePanelRoute<T> extends PopupRoute<T> {
  _AdaptivePanelRoute({
    required this.anchor,
    required this.builder,
    required this.width,
    required this.estimatedHeight,
    required this.barrierLabel,
  });

  /// Le déclencheur dans le repère de l'overlay ; nul pour un panneau centré.
  final Rect? anchor;
  final WidgetBuilder builder;
  final double width;
  final double estimatedHeight;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  // Un panneau collé à son bouton ne voile pas la page, comme un menu ; un
  // panneau centré, oui, comme un dialogue.
  @override
  Color? get barrierColor => anchor == null ? Colors.black54 : null;

  @override
  Duration get transitionDuration => AppMotion.standard;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final content = AdaptivePanelScope(child: Builder(builder: builder));
    final rect = anchor;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, constraints) {
        if (rect == null) {
          return SafeArea(
            minimum: const EdgeInsets.all(OnyxMenuPlacement.margin),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: width,
                  maxHeight: constraints.maxHeight * 0.85,
                ),
                child: OnyxPanelReveal(
                  animation: animation,
                  alignment: Alignment.center,
                  child: OnyxPanelSurface(child: content),
                ),
              ),
            ),
          );
        }
        final placement = OnyxMenuPlacement.resolve(
          anchor: rect,
          screen: constraints.biggest,
          padding: MediaQuery.paddingOf(context),
          panelHeight: estimatedHeight,
        );
        return CustomSingleChildLayout(
          delegate: OnyxPanelPlacementLayout(placement),
          child: OnyxPanelReveal(
            animation: animation,
            alignment: placement.growFrom,
            child: SizedBox(
              width: math.min(width, constraints.maxWidth),
              child: OnyxPanelSurface(child: content),
            ),
          ),
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
