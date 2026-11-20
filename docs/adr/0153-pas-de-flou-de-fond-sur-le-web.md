# ADR-0153 — Pas de flou de fond sur le web

- **Statut :** accepté. Vérifié en test (la règle) ; l'effet sur la fluidité est attendu, pas mesuré.
- **Date :** 2026-11-18
- **Portée :** `widgets/global/glass_chrome.dart` (`glassBlurs`), donc tous les verres :
  `GlassHeaderStrip`, `GlassSurface`, `GlassBlur`, `LiquidGlass`, `mobile_top_bar`,
  `phone_more_menu`, `desktop_search_route`, `interface_tour_overlay`, `onyx_glass_panel`, et les
  flous d'image `person_detail_screen`, `end_card_chrome`, `poster_flip_back`.
- **Prolonge** les ADR-0076 (webOS) et ADR-0086 (mode léger).

## Contexte

La version web, rendue par CanvasKit, saccade. `glassBlurs` ne coupait le flou que sur webOS et en
mode léger : dans un navigateur d'ordinateur ou de téléphone, chaque `BackdropFilter` restait
actif (barre du haut pleine largeur à sigma 30 au-dessus du contenu qui défile, verre liquide,
recherche, panneaux). Sur CanvasKit, chacun relit l'écran et le refloute à chaque image, sur la
carte graphique du navigateur ; le coût ne dépend pas de la plateforme mais du moteur.

## Décision

1. `glassBlurs` est faux sur le web, quel que soit le navigateur : `!isWeb && !isLite`. Le web est
   traité comme le webOS l'était déjà : le verre devient un voile plus dense, sans rien relire.
2. Les flous d'image (`ImageFiltered`, sigma 18 à 60) passent par la même garde et sont donc
   coupés aussi : sur le web ils se refont à chaque image au lieu d'être rastérisés une fois, et
   leurs fonds sombres de repli existent déjà.
3. La règle vit dans `glassBlursFor`, sans contexte, pour être testée hors navigateur.

## Conséquences

- Aucun changement natif : Android, iOS, macOS, Windows gardent le flou (hors mode léger).
- Sur le web le verre est moins « glacé » ; la lisibilité sur affiche claire vient des voiles
  denses (0,85 pour la barre, 0,88 pour les panneaux).
- Si CanvasKit ou le moteur Skwasm rend un jour le flou de fond bon marché, relâcher la garde
  navigateur par navigateur plutôt que d'y remettre le flou partout.
