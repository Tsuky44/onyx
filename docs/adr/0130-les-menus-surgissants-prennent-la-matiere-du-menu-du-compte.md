# ADR-0130 — Les menus surgissants prennent la matière du menu du compte

- **Statut :** accepté. Maquette « 1 · Menus » validée par l'utilisateur (2026-11-14) ; rendu vérifié
  sur une capture de test, pas encore vu sur appareil.
- **Date :** 2026-11-14
- **Portée :** `widgets/global/onyx_menu.dart` (`OnyxMenuButton`, `OnyxMenuItem`),
  `onyx_menu_panel.dart` (`OnyxMenuPanel`, `OnyxMenuMetrics`), `onyx_menu_route.dart` (`showOnyxMenu`).
  Premiers menus convertis : le tri de `catalog_header.dart`, `poster_grid_display_menu.dart`,
  `show_metadata_menu.dart`, et les pages de réglages `activity_page.dart`, `playback_page.dart`,
  `playback_still_watching_group.dart`, `stats_page.dart`. Hors téléviseur seulement.
- **Étend** l'[ADR-0126](0126-le-menu-du-compte-met-les-profils-en-tete.md) : sa ligne `_MenuRow`
  devient le rendu de tous les menus surgissants.

## Contexte

Les menus du bureau et du téléphone étaient des `PopupMenuButton` Material : fond gris, ondulation,
coche ou couleur d'accent selon l'écran, chacun réglé à la main (`_ModeRow` de l'affichage, `ListTile`
des métadonnées, coche bricolée de la langue audio). Le menu du compte (ADR-0126) avait fixé une autre
matière, celle du lecteur et du dos des affiches : la ligne survolée ou focalisée se remplit de blanc à
l'encre noire. Deux langages de menu cohabitaient.

## Décision

1. **Un seul composant, `OnyxMenuButton<T>`**, qui prend une liste d'`OnyxMenuItem<T>` (libellé, icône
   `AppIcons` ou widget de tête, sous-titre, `checked`, `destructive`, `enabled`) et un déclencheur :
   `icon` (bouton-icône) ou `child` (celui de l'appelant). `showOnyxMenu` reste public pour un
   déclencheur qui ne peut pas être un bouton.
2. **Le rendu de `_MenuRow`** : panneau `surfaceElevated`, filet `glassBorder`, ombre ample, rayon 16,
   padding 6 ; lignes de 40 px (44 sous 600 px de large, au doigt), 14 px de plus avec un sous-titre.
   Survol et focus : fond blanc, encre noire. Une ligne destructive reste rouge sur rouge pâle, rangée
   sous un filet posé par le panneau.
3. **Menu de choix** : dès qu'une ligne est cochée, chaque ligne réserve la place de la coche
   (`AppIcons.check`) à droite ; une longue liste s'ouvre défilée sur la valeur cochée.
4. **Placement** : collé au bouton, dessous s'il tient, dessus sinon (ou du côté qui a le plus de
   place) ; aligné sur le bord du bouton qui regarde le centre de l'écran ; ramené dans l'écran avec
   12 px de marge. Les lignes ont une hauteur fixe : `OnyxMenuMetrics` calcule la hauteur du panneau et
   le défilement initial sans passe de mesure.
5. **Mouvement** : fondu et échelle de 0,96 à 1 depuis le coin collé au bouton (`AppMotion.standard`),
   le fondu seul sous « réduire les animations ».
6. **Focus** : ouvert à la souris ou au doigt, aucune ligne n'est allumée ; ouvert au clavier, la ligne
   cochée (ou la première) le prend. `TvFocusable.autofocus` n'agit que sur un téléviseur, le panneau
   le demande lui-même. Fermé, le focus revient au déclencheur.
7. **Un choix nul reste un choix** : la route rend l'indice de la ligne, `showOnyxMenu` un
   enregistrement `({T value})`. `PopupMenuButton` prenait une valeur nulle (« Automatique ») pour une
   fermeture.
8. **Le téléviseur garde Material** : sous `TvScope`, `OnyxMenuButton` rend l'ancien `PopupMenuButton`,
   le temps que la refonte de la TV, menée à part, fixe ses menus.

## Conséquences

- Un nouveau menu du bureau ou du téléphone est un `OnyxMenuButton` ; les `PopupMenuButton` restants
  (téléchargements, administration, serveurs, demandes d'accès, menu « Plus » de la fiche) se
  convertissent écran par écran. Aucun guard test ne l'impose encore : il viendra quand la liste sera
  vide hors TV et lecteur.
- Le repli TV est temporaire. Quand la TV aura ses menus, la branche `TvScope` d'`OnyxMenuButton` se
  retire ou rend le menu de la TV.
- Le lecteur garde ses propres menus (Chrome Onyx, ADR-0048).
