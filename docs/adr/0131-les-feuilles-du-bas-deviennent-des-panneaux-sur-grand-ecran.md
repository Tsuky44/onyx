# ADR-0131 — Les feuilles du bas deviennent des panneaux sur grand écran

- **Statut :** accepté. Maquette « 4 · Feuilles du bas → panneau » validée par l'utilisateur ; rendu
  vérifié par des tests de widget, pas encore vu sur appareil.
- **Date :** 2026-11-14
- **Portée :** `widgets/global/adaptive_panel.dart` (`showAdaptivePanel`, `AdaptivePanelScope`),
  `onyx_panel_surface.dart` (matière et placement partagés), `add_to_list_sheet.dart` et
  `add_to_list_panel_body.dart`, `poster_picker_sheet.dart`, `metadata_fix_sheet.dart`,
  `detail_cast_section.dart`.
- **Étend** l'[ADR-0130](0130-les-menus-surgissants-prennent-la-matiere-du-menu-du-compte.md) : le
  panneau prend la matière des menus.

## Contexte

Sur un écran de PC, une feuille qui monte du bas, pleine largeur, est un geste de téléphone : elle
éloigne le contenu du bouton qui l'a ouvert et laisse de grands vides. Les menus, eux, collent à leur
bouton (ADR-0130).

## Décision

1. **Un seul seam, `showAdaptivePanel(context, builder: …)`.** Sous 600 px de large
   (`AppLayout.isCompact`) et sur téléviseur (`TvScope`), il ouvre la feuille d'avant, inchangée ;
   au-delà, un panneau. Les appelants passent le contexte du bouton ; leur signature ne change pas.
2. **Le panneau réutilise la matière des menus**, extraite dans `onyx_panel_surface.dart` :
   `OnyxPanelSurface` (fond, filet, ombre, rayon 16), `OnyxMenuPlacement` (dessous ou dessus, bord
   tourné vers le centre, marge 12), `OnyxPanelReveal` (fondu et échelle). Les menus les utilisent
   aussi : leur rendu ne change pas. `OnyxMenuRow` et `OnyxMenuHairline` deviennent publics pour que
   les panneaux de liste aient les mêmes lignes.
3. **Le contenu sait où il est** : `AdaptivePanelScope.isPanel(context)`. Dans un panneau, il n'a ni
   poignée, ni `DraggableScrollableSheet`, ni fond propre ; le cadre vient du seam.
4. **« Ajouter à une liste »** : panneau ancré de 280 px, titre de section en petites capitales,
   listes cochées quand elles ont déjà le titre, filet, « Nouvelle liste », survol blanc à l'encre
   noire.
5. **Panneau centré, de largeur bornée**, pour ce qui est trop grand pour se coller à un bouton : la
   grille d'affiches (760 px), la recherche de métadonnées (560 px) et la distribution complète
   (720 px). Le fond est alors voilé, comme un dialogue ; un panneau ancré ne voile pas la page, comme
   un menu.

## Conséquences

- Une nouvelle feuille du bas passe par `showAdaptivePanel` ; `showModalBottomSheet` direct ne se
  rencontre plus que pour les feuilles qui n'ont pas encore été converties (`watch_list_members_sheet`,
  sélecteurs de bibliothèque et de saisons).
- La hauteur d'un panneau ancré est celle de son contenu, plafonnée à la place libre ; le côté
  (dessous ou dessus) se décide sur `estimatedHeight`, pas sur une mesure.
- Pas de glisser pour fermer au PC : un clic hors du panneau le ferme.
