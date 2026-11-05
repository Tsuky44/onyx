import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../utils/app_platform.dart';

/// Empêche le pont d'accessibilité de l'Apple TV de faire défiler les pages.
///
/// Le moteur tvOS active les sémantiques même sans VoiceOver, et double chaque
/// zone défilante d'une `UIScrollView` native. Le moteur de focus de tvOS la
/// déplace de lui-même, puis le pont renvoie sa position à Flutter en action
/// `scrollToOffset` — souvent une position périmée ou hors bornes. Constaté sur
/// le simulateur Apple TV (2026-11-05, points d'arrêt sur `jumpTo`) : Haut
/// depuis une rangée de l'accueil envoyait la page *au-delà de sa fin* (1665
/// pour un maximum de 1123), le rebond iOS la ramenait, et l'écran restait
/// noir ; la grille Films revenait seule à un ancien défilement et laissait le
/// focus sur une affiche hors de l'écran.
///
/// Sur un téléviseur, c'est le focus de l'app qui place la page (voir
/// [TvFocusScroll]). Ces actions sont donc ignorées tant que VoiceOver ne
/// pilote pas l'écran ; avec VoiceOver, elles restent le seul moyen qu'il a de
/// faire défiler. Voir ADR-0108.
abstract final class TvSemanticsScrollGuard {
  static bool _installed = false;

  /// Branché une fois, après l'initialisation du binding, qui pose son propre
  /// gestionnaire : celui-ci l'enveloppe.
  static void install() {
    if (_installed || !AppPlatform.isTvOS) return;
    _installed = true;
    final dispatcher = PlatformDispatcher.instance;
    final inner = dispatcher.onSemanticsActionEvent;
    dispatcher.onSemanticsActionEvent = (event) {
      if (shouldDrop(event, dispatcher.accessibilityFeatures)) return;
      inner?.call(event);
    };
  }

  @visibleForTesting
  static bool shouldDrop(
          SemanticsActionEvent event, AccessibilityFeatures features) =>
      event.type == SemanticsAction.scrollToOffset &&
      !features.accessibleNavigation;
}
