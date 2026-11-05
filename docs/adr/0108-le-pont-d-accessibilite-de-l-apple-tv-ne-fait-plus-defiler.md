# ADR-0108 — Sur Apple TV, le pont d'accessibilité ne fait plus défiler les pages

- **Statut :** accepté. Vérifié sur le simulateur Apple TV 4K (tvOS 27) ; pas encore sur une vraie
  Apple TV, ni avec VoiceOver allumé.
- **Date :** 2026-11-05
- **Portée :** `tv/tv_semantics_scroll_guard.dart`, branché dans `main.dart` ; `tv/tv_focus_scroll.dart`
  pour les deux défauts de défilement trouvés en même temps.
- **Prolonge :** [ADR-0028](0028-cible-apple-tv.md) (la cible Apple TV),
  [ADR-0039](0039-force-du-geste-sur-le-trackpad-de-l-apple-tv.md) (un seul défilement par pas).

## Contexte

Une passe de navigation à la télécommande sur le simulateur a trouvé des pages qui défilaient seules :
Haut depuis une rangée de l'accueil envoyait la page *au-delà de sa fin* (1665 pour un maximum de
1123), le rebond iOS la ramenait, et après quelques appuis l'écran restait noir sous l'en-tête. La
grille Films revenait à un ancien défilement, et laissait le focus sur une affiche hors de l'écran.

Des points d'arrêt posés par le service VM sur `ScrollPosition.jumpTo` ont montré l'auteur : ni le
focus de l'app, ni le carrousel, mais `_RenderScrollSemantics._onScrollToOffset`, appelé par le moteur
pendant `FlutterView.updateSemantics`. Le moteur tvOS active les sémantiques même sans VoiceOver
(`semanticsEnabled` vrai, aucune fonction d'accessibilité allumée), double chaque zone défilante d'une
`UIScrollView`, et le moteur de focus de tvOS la déplace lui-même. Le pont renvoie alors sa position
à Flutter en action `scrollToOffset`, souvent périmée ou hors bornes. Le moteur est précompilé par
flutter-tvos : on ne peut pas le corriger.

## Décision

1. **Les actions `scrollToOffset` sont ignorées sur Apple TV tant que VoiceOver ne pilote pas
   l'écran** (`accessibleNavigation` faux). `TvSemanticsScrollGuard` enveloppe
   `PlatformDispatcher.onSemanticsActionEvent` après l'initialisation du binding ; les autres actions
   (toucher, `scrollUp`, `scrollDown`…) passent. Sur un téléviseur, c'est le focus de l'app qui place
   la page (ADR-0039).
2. **Une cible de focus restée de l'autre côté de l'écran apparaît quand même.** Flutter suppose que
   Bas mène sous l'écran : « garder visible à la fin » ne défile que vers l'avant. `TvFocusScroll`
   vérifie donc aussi l'autre bord.
3. **Défiler « au-delà » ramène d'abord l'élément focalisé s'il est hors de l'écran.** Deux Haut
   rapides vers le bouton retour d'une fiche : le second partait de la position du moment et
   remplaçait l'animation qui montait vers le bouton par un demi-écran.

## Conséquences

- Avec VoiceOver allumé, les actions passent comme avant : le défilement à la Siri Remote sous
  VoiceOver n'a pas été essayé, et pourrait garder le défaut.
- Si une future version de flutter-tvos cesse d'activer les sémantiques ou corrige son pont, le
  garde-fou devient inutile mais sans effet ; il se retire en supprimant son appel dans `main.dart`.
- Les tests `tv_semantics_scroll_guard_test.dart` et `tv_focus_scroll_test.dart` épinglent les trois
  règles.
