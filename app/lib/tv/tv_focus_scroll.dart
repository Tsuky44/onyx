import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';
import 'tv_key_repeat.dart';
import 'tv_mode.dart';
import 'tv_page.dart';
import 'tv_touchpad.dart';

/// Le défilement qui ramène à l'écran ce que la télécommande vient d'atteindre.
///
/// Il y en avait deux par pas. Le parcours directionnel de Flutter demande le
/// focus puis *saute* (durée nulle) juste assez pour montrer la cible au bord
/// de l'écran ; à la frame suivante, [TvFocusable] l'anime jusqu'au centre. Le
/// résultat était un à-coup à chaque flèche : la rangée bondissait, puis
/// glissait, et l'œil perdait l'affiche qu'il suivait.
///
/// Désormais un seul défilement par pas, et toujours animé : celui de
/// [TvFocusable] quand la cible en est un (il sait où la placer), celui-ci
/// sinon. Hors téléviseur, le comportement de Flutter est inchangé.
///
/// Une page peut décider elle-même où elle se pose ([TvPage], les fiches) :
/// les deux lui laissent alors la main.
abstract final class TvFocusScroll {
  /// Compté plutôt que booléen : un même nœud passe parfois d'une rangée à
  /// l'autre (le menu des réglages du lecteur), et la nouvelle le déclare
  /// avant que l'ancienne ne l'oublie.
  static final Expando<int> _selfScrolling = Expando<int>('tv-self-scroll');

  /// Déclare que [node] se ramène lui-même à l'écran quand il prend le focus.
  /// Chaque appel est rendu par un [forgetSelfScrolling].
  static void markSelfScrolling(FocusNode node) {
    _selfScrolling[node] = (_selfScrolling[node] ?? 0) + 1;
  }

  static void forgetSelfScrolling(FocusNode node) {
    final count = (_selfScrolling[node] ?? 0) - 1;
    _selfScrolling[node] = count > 0 ? count : null;
  }

  static bool scrollsItself(FocusNode node) => (_selfScrolling[node] ?? 0) > 0;

  /// La durée d'un défilement de focus. Au plus court quand les pas se
  /// suivent (flèche maintenue, élan du trackpad) : l'animation doit finir
  /// avant le pas suivant.
  static Duration durationFor(BuildContext context) => AppMotion.move(
        context,
        isTracking ? AppMotion.track : AppMotion.standard,
      );

  /// Vrai quand les pas se suivent sans attendre : flèche maintenue, rangée
  /// qui file sous le doigt. Le défilement prend alors sa durée la plus
  /// courte, quelle que soit la distance.
  static bool get isTracking => TvKeyRepeat.isRepeating || TvTouchpad.isGliding;

  /// Le [TraversalRequestFocusCallback] de l'app : la politique de parcours
  /// l'appelle à chaque déplacement aux flèches.
  static void requestFocus(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) {
    if (!TvMode.isTv) {
      FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
        node,
        alignmentPolicy: alignmentPolicy,
        alignment: alignment,
        duration: duration,
        curve: curve,
      );
      return;
    }
    node.requestFocus();
    final context = node.context;
    if (context == null || scrollsItself(node)) return;
    final page = TvPageScope.maybeOf(context);
    if (page != null) {
      // Après l'image qui pose le focus, comme [TvFocusable] : la ligne
      // d'arrivée peut encore se mettre en page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (node.hasFocus) page.reveal(node);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    final policy = alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit;
    void reveal(ScrollPositionAlignmentPolicy policy) =>
        Scrollable.ensureVisible(
          context,
          alignment: alignment ?? 1,
          alignmentPolicy: policy,
          duration: duration ?? durationFor(context),
          curve: curve ?? AppMotion.curve,
        );
    reveal(policy);
    // Flutter suppose que Bas mène sous l'écran et Haut au-dessus : « garder
    // visible à la fin » ne défile que vers l'avant. Une cible restée de
    // l'autre côté — Bas depuis le bouton retour d'une fiche défilée, vers des
    // actions encore hors de l'écran au-dessus — prenait le focus sans
    // apparaître. L'autre bord est donc vérifié aussi ; l'appel ne fait rien
    // quand la cible est déjà de ce côté-là.
    final opposite = switch (policy) {
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd =>
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart =>
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.explicit => null,
    };
    if (opposite != null) reveal(opposite);
  }

  /// La part de la hauteur visible parcourue par [scrollPast] : assez pour
  /// avancer, pas assez pour perdre la ligne qu'on lisait.
  static const double _pastFraction = 0.5;

  /// Fait défiler ce qui contient [node] quand haut ou bas n'a plus rien à
  /// atteindre.
  ///
  /// Le focus ne s'arrête que sur ce qui s'actionne. Ce qui se lit seulement —
  /// l'en-tête d'une page au-dessus du premier réglage, des statistiques ou un
  /// journal sous le dernier bouton — restait hors de l'écran, sans aucun
  /// moyen de l'y amener à la télécommande.
  static void scrollPast(FocusNode node, TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return;
    }
    final context = node.context;
    if (context == null) return;
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final position = scrollable?.position;
    if (position == null || !position.hasContentDimensions) return;
    // L'élément focalisé d'abord, s'il n'est pas encore à l'écran. Haut
    // pressé deux fois de suite jusqu'au bouton retour d'une fiche : le
    // second appui partait de la position du moment, à mi-chemin, et
    // remplaçait l'animation qui montait vers le bouton par un demi-écran —
    // la page s'arrêtait au milieu, le focus hors de l'écran (constaté sur le
    // simulateur Apple TV, 2026-11-05).
    final viewport = scrollable!.context.findRenderObject();
    if (viewport is RenderBox && viewport.hasSize) {
      final shown = viewport.localToGlobal(Offset.zero) & viewport.size;
      final hidden = direction == TraversalDirection.up
          ? node.rect.top < shown.top - 1
          : node.rect.bottom > shown.bottom + 1;
      if (hidden) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: direction == TraversalDirection.up
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: durationFor(context),
          curve: AppMotion.curve,
        );
        return;
      }
    }
    final step = position.viewportDimension * _pastFraction;
    final target = (position.pixels +
            (direction == TraversalDirection.down ? step : -step))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    final duration = durationFor(context);
    if (duration == Duration.zero) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: duration, curve: AppMotion.curve);
    }
  }
}
