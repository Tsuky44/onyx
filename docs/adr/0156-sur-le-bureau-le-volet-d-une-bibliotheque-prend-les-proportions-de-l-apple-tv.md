# ADR-0156 — Sur le bureau, le volet d'une bibliothèque prend les proportions de l'Apple TV

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-18, captures du bureau et de
  l'Apple TV à l'appui : « la c'est tout petit, reprends les proportions comme sur Apple TV »).
  Vérifié en test et sur un rendu à 1920 × 1080, **pas encore vu dans l'app lancée**.
- **Date :** 2026-11-18
- **Portée :** `screens/library/widgets/library_desktop_spotlight.dart` (`scaleFor`,
  `tileScaleFor`, `_ScaledPane`), `screens/library/library_screen.dart`,
  `utils/poster_grid_zoom.dart` (`PosterGridZoom.split`, `splitPresets`),
  `widgets/global/poster_grid_zoom_region.dart`, `widgets/global/poster_grid_display_menu.dart`,
  `utils/responsive.dart` (`posterGridDelegate`, `tileScale`).
- **Amende** l'[ADR-0140](0140-sur-le-bureau-les-bibliotheques-ont-le-volet-de-la-recherche.md).

## Contexte

Le volet du bureau reprenait les mesures de celui du téléviseur (texte de 374 px, titre de 84 px),
mais à taille réelle. Le téléviseur, lui, se met en page sur 1280 px puis s'agrandit (`TvUiScale`,
×1,5 sur un écran de 1920). Sur un moniteur de 1920 px, le volet ne prenait donc qu'un quart de la
largeur, avec un titre petit à côté de six colonnes d'affiches. Le choix « 6 par ligne » du menu
Affichage, fait pour la grille pleine largeur, s'appliquait aussi à la grille réduite d'à côté.

## Décision

1. **Le volet se met en page comme au téléviseur, puis grandit avec la fenêtre** :
   ×(largeur / 1280), entre 1 et 2. Le principe de `TvUiScale`, pour le volet seul : la page vue
   par le volet garde la largeur de l'écran divisée d'autant (marges et points de rupture d'un
   téléviseur), et la densité suit, pour que l'image de fond se décode à sa taille affichée.
2. **La grille d'à côté vise l'affiche du mur du téléviseur** : 1,2 fois celle d'une grille du
   bureau, multipliée par la même échelle. Quatre par ligne à 1440 comme à 1920 px.
3. **La vue partagée a ses propres modes d'affichage** : 3, 4, 5 ou 6 par ligne, retenus à part
   (`poster_grid_columns_split`). Le « 6 par ligne » de la grille pleine largeur reste le sien.

## Conséquences

- À 1100 px, au seuil du volet, rien ne grandit : le volet garde sa taille d'avant, et la grille
  perd une colonne (trois au lieu de quatre).
- La recherche du bureau (ADR-0139) garde son volet à taille réelle : à aligner si l'utilisateur le
  demande.
- Épinglé par `test/library_desktop_spotlight_test.dart` (les proportions à 1920 px, le choix de
  la grille pleine qui ne s'applique pas à côté du volet).
