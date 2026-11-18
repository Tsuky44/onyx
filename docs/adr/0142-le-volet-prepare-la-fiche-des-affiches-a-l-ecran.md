# ADR-0142 — Le volet prépare la fiche des affiches à l'écran

- **Statut :** accepté. Testé en unitaire et en widget (`library_spotlight_prefetch_test.dart`,
  `library_desktop_spotlight_test.dart`). **Pas encore regardé dans l'app Windows contre un vrai
  serveur.**
- **Date :** 2026-11-18
- **Portée :** `app/lib/screens/library/widgets/library_spotlight_prefetch.dart`,
  `library_spotlight.dart`, `library_desktop_spotlight.dart`,
  `app/lib/screens/search/desktop/desktop_search_sheet.dart`,
  `app/lib/services/media_details_cache.dart`. Prolonge l'ADR-0139 et l'ADR-0140.

## Contexte

Le volet de gauche de la recherche du bureau (ADR-0139) et d'une bibliothèque sur le bureau
(ADR-0140) pose le titre en toutes lettres, puis son logo. Le logo ne vient que de la fiche du
catalogue (`/api/media/:id/details`) : la liste de la bibliothèque ne le porte pas. Au survol, le
volet attendait 220 ms que le pointeur se pose (`LibrarySpotlight.settle`, pensé pour une
télécommande qui traverse une rangée), demandait la fiche, puis téléchargeait et décodait le logo.
L'utilisateur voyait le nom du média seul pendant une demi-seconde, puis le logo le remplacer.

## Décision

Chaque affiche construite dans ces grilles prépare la fiche de son volet
(`LibrarySpotlightWarmup` → `LibrarySpotlightPrefetch`) : la fiche dans `MediaDetailsCache`, puis
le logo décodé à sa taille d'origine, la même entrée du cache d'images que `MediaLogoDisplay`.
Au survol, le volet lit la fiche en mémoire et pose le logo sur la même image que le titre change.

- Quatre demandes à la fois au plus, dans l'ordre où les cartes se construisent : les affiches
  elles-mêmes passent avant.
- La grille est paresseuse : seules les cartes à l'écran et juste autour se préparent. Une carte
  qui sort avant son tour retire sa demande ; un défilement rapide ne laisse pas de file.
- Un titre préparé ne l'est pas de nouveau tant que sa fiche est fraîche (20 min).
- L'image de fond n'est pas préparée : décodée à la largeur de l'écran, une par affiche, elle
  coûterait des centaines de Mo. Le volet garde l'image précédente jusqu'à ce que la suivante soit
  prête (ADR-0123), ce qui ne se voit pas comme un trou.
- Une fiche déjà en route (préparation, survol d'une carte) est rejointe sans attendre les 220 ms
  (`MediaDetailsCache.isLoading`).

## Conséquences

- Ouvrir une bibliothèque ou taper une recherche sur le bureau demande la fiche de chaque titre
  visible, quatre à la fois. Le serveur garde TMDB en cache six heures : ces demandes lisent
  surtout son cache. La page du titre ouverte ensuite trouve sa fiche en mémoire.
- Le volet de la télévision (`LibraryTvView`) ne change pas : sous une télécommande qui court, la
  demande différée reste la bonne.
