import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_motion.dart';
import '../../../tv/tv_mode.dart';
import '../../../tv/tv_ui_scale.dart';
import 'poster_flip_back.dart';

export 'poster_flip_back.dart' show PosterFlipAction;

/// Retourne l'affiche posée sous [posterKey] et montre son menu au dos.
///
/// Le menu d'une télécommande n'a pas de curseur où s'ancrer : le menu
/// Material ouvert à côté de l'affiche se lisait comme une fenêtre de bureau
/// posée sur un téléviseur, et laissait chercher de quel média il parlait.
/// Ici l'affiche elle-même se soulève et pivote d'un demi-tour ; son dos porte
/// le titre, l'avancement et les actions. Fermer (retour, clic hors de la
/// carte, une action) la retourne dans l'autre sens et rend le focus à ce qui
/// l'avait.
///
/// [poster] est l'image de l'affiche : la face avant pendant la rotation, et
/// le fond flouté du dos. Rend la valeur de l'action choisie, ou nul.
Future<T?> showPosterFlipMenu<T>({
  required BuildContext context,
  required GlobalKey posterKey,
  required Widget poster,
  required String title,
  String? subtitle,
  double? progress,
  required List<PosterFlipAction<T>> actions,
}) async {
  final box = posterKey.currentContext?.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null ||
      !box.attached ||
      !box.hasSize ||
      overlay == null ||
      actions.isEmpty) {
    return null;
  }
  // Mesurée dans le repère de l'overlay où la route se pose, pas dans celui de
  // l'écran : sur un téléviseur, `TvUiScale` dessine l'app à 1280 de large
  // puis l'agrandit. En coordonnées d'écran, le dos tombait plus petit que
  // l'affiche et décalé vers le haut à gauche (vu sur Apple TV). Les deux
  // coins, pour suivre aussi le zoom du focus.
  final origin = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final returnFocus = FocusManager.instance.primaryFocus;

  final result = await navigator.push<T>(
    _PosterFlipRoute<T>(
      origin: origin,
      overlayWidth: overlay.size.width,
      poster: poster,
      title: title,
      subtitle: subtitle,
      progress: progress,
      actions: actions,
      barrierLabel: tr('Fermer'),
    ),
  );

  // La route rend d'ordinaire le focus à sa page ; sous dpad, rien ne garantit
  // que ce soit la carte d'où l'on venait. On le lui rend explicitement.
  final node = returnFocus;
  if (node != null &&
      node.context != null &&
      node.context!.mounted &&
      node.canRequestFocus &&
      !node.hasFocus) {
    node.requestFocus();
  }
  return result;
}

class _PosterFlipRoute<T> extends PopupRoute<T> {
  _PosterFlipRoute({
    required this.origin,
    required this.overlayWidth,
    required this.poster,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.actions,
    required this.barrierLabel,
  });

  /// L'affiche, dans le repère de l'overlay (voir [overlayWidth]).
  final Rect origin;

  /// La largeur de l'overlay où [origin] a été mesuré. Sur un téléviseur, la
  /// page de la route passe par `TvUiScale` comme toutes les pages : son
  /// repère est celui de la maquette (1280 de large), et le rapport des deux
  /// largeurs y ramène [origin].
  final double overlayWidth;
  final Widget poster;
  final String title;
  final String? subtitle;
  final double? progress;
  final List<PosterFlipAction<T>> actions;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  // Le voile est peint par la page elle-même, au rythme de la rotation.
  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => AppMotion.flip;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Sans `Material` au-dessus, les textes de la route n'héritent d'aucun
    // style et Flutter les souligne en jaune.
    final page = Material(
      type: MaterialType.transparency,
      child: _PosterFlipStage<T>(
        route: this,
        animation: CurvedAnimation(
          parent: animation,
          curve: AppMotion.flipCurve,
        ),
      ),
    );
    // Une route surgissante ne passe pas par le thème des transitions, qui
    // pose `TvUiScale` sur chaque page : sans lui, le dos s'écrivait aux deux
    // tiers de la taille du reste de l'écran sur l'Apple TV.
    return TvScope.of(context) ? TvUiScale(child: page) : page;
  }
}

/// L'affiche qui grandit vers sa place et tourne sur son axe vertical.
class _PosterFlipStage<T> extends StatelessWidget {
  const _PosterFlipStage({required this.route, required this.animation});

  final _PosterFlipRoute<T> route;
  final Animation<double> animation;

  /// Combien le dos dépasse l'affiche : assez pour que titre, avancement et
  /// quatre actions tiennent sans réduire le texte, assez peu pour qu'on
  /// reconnaisse la carte qui s'est retournée.
  static const double _lift = 1.18;

  /// La profondeur de la perspective. Plus fort, l'affiche se déforme en
  /// trapèze au passage de la tranche ; plus faible, elle s'aplatit et la
  /// rotation ne se lit plus.
  static const double _perspective = 0.0011;

  static const double _margin = 16;

  /// [_PosterFlipRoute.origin] ramené au repère de cette page.
  Rect _origin(Size screen) {
    final o = route.origin;
    if (screen.width <= 0 || route.overlayWidth <= 0) return o;
    final k = screen.width / route.overlayWidth;
    if ((k - 1).abs() < 0.001) return o;
    return Rect.fromLTRB(o.left * k, o.top * k, o.right * k, o.bottom * k);
  }

  Rect _target(Rect o, Size screen) {
    var w = o.width * _lift;
    var h = o.height * _lift;
    final maxW = screen.width - _margin * 2;
    final maxH = screen.height - _margin * 2;
    if (w > maxW || h > maxH) {
      final k = math.min(maxW / w, maxH / h);
      w *= k;
      h *= k;
    }
    final left =
        (o.center.dx - w / 2).clamp(_margin, screen.width - _margin - w);
    final top =
        (o.center.dy - h / 2).clamp(_margin, screen.height - _margin - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final screen = MediaQuery.sizeOf(context);
    final origin = _origin(screen);
    final target = _target(origin, screen);
    final radius = BorderRadius.circular(14);

    // Construit une fois : la rotation ne fait que déplacer ces deux faces.
    final front = IgnorePointer(
      child: ClipRRect(borderRadius: radius, child: route.poster),
    );
    final back = PosterFlipBack<T>(
      poster: route.poster,
      title: route.title,
      subtitle: route.subtitle,
      progress: route.progress,
      actions: route.actions,
      borderRadius: radius,
      onSelected: (value) => Navigator.of(context).pop(value),
      onClose:
          TvScope.of(context) ? null : () => Navigator.of(context).maybePop(),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0);
        final rect = reduced ? target : Rect.lerp(origin, target, t)!;
        // Sous « réduire les animations », les faces se fondent sans tourner.
        final angle = reduced ? 0.0 : t * math.pi;
        final backShown = reduced ? t > 0 : angle > math.pi / 2;
        // La tranche : l'instant où la carte fait face à la lumière.
        final edge = reduced ? 0.0 : math.sin(angle);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.6 * t),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55 * t),
                      blurRadius: 18 + 30 * t,
                      spreadRadius: -4,
                      offset: Offset(0, 10 + 14 * t),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Face(
                      angle: angle,
                      perspective: _perspective,
                      visible: !backShown,
                      opacity: reduced ? 1 - t : 1,
                      sheen: edge,
                      radius: radius,
                      child: front,
                    ),
                    _Face(
                      angle: angle - math.pi,
                      perspective: _perspective,
                      visible: backShown,
                      opacity: reduced ? t : 1,
                      sheen: edge,
                      radius: radius,
                      child: back,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Une face de la carte, tournée de [angle] autour de son axe vertical.
///
/// La face cachée reste montée (opacité nulle, ni dessinée ni touchable) : le
/// menu du dos prend le focus dès l'ouverture, sans attendre la mi-rotation.
class _Face extends StatelessWidget {
  const _Face({
    required this.angle,
    required this.perspective,
    required this.visible,
    required this.opacity,
    required this.sheen,
    required this.radius,
    required this.child,
  });

  final double angle;
  final double perspective;
  final bool visible;
  final double opacity;
  final double sheen;
  final BorderRadius radius;
  final Widget child;

  /// Au repos, la face est posée à plat : une matrice identité, sans
  /// perspective. Certains téléviseurs gardaient en cache la couche 3D d'une
  /// image de la rotation et peignaient le dos en miroir une fois la carte
  /// retournée. Le même `Transform` reste en place pour ne pas reconstruire le
  /// dos, qui perdrait le focus du menu.
  Matrix4 _matrix() {
    if (angle.abs() < 1e-6) return Matrix4.identity();
    return Matrix4.identity()
      ..setEntry(3, 2, perspective)
      ..rotateY(angle);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: Opacity(
        opacity: visible ? opacity : 0,
        child: Transform(
          alignment: Alignment.center,
          transform: _matrix(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              // Un reflet qui passe sur la carte quand elle présente sa
              // tranche : c'est lui qui fait lire un objet, pas une image.
              if (sheen > 0.01)
                IgnorePointer(
                  child: ClipRRect(
                    borderRadius: radius,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.16 * sheen),
                            Colors.black.withValues(alpha: 0.35 * sheen),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
