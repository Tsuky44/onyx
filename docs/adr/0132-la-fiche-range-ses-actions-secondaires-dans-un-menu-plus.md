# ADR-0132 — La fiche range ses actions secondaires dans un menu « Plus »

- **Statut** : acceptée
- **Date** : 2026-11-14
- **Portée** : `app/lib/widgets/global/detail_more_button.dart`, `detail_more_items.dart`, `season_download_target.dart`, `onyx_menu*.dart`, `app/lib/screens/library/show_hero_actions.dart`, `movie_more_button.dart`

## Contexte

La rangée d'actions des fiches film et série alignait des ronds sans libellé (vu, liste, téléchargement, partage) et, sur une série, un crayon isolé pour les métadonnées. Il fallait survoler pour savoir ce que faisait chaque rond (maquette « 8 · Menu Plus de la fiche »).

## Décision

- Hors TV, la rangée est : l'action principale inchangée, « Ma liste » (pastille nommée), puis « Plus » (pastille nommée) qui ouvre le menu Onyx (ADR-0130).
- « Plus » groupe : marquer vu (le film, ou la saison affichée), télécharger, partager ; puis un filet et une section « Administration », présente seulement avec `manage_library` : « Corriger la fiche… » (sur une série, un second menu au même endroit propose détection auto ou TMDB) et « Changer l'affiche… ». Le crayon de `ShowMetadataMenu` disparaît hors TV.
- Les libellés disent ce que l'appui va faire dans l'état présent (« Télécharger la saison 2 », « Compléter la saison 2 », « Annuler les téléchargements de la série », « Reprendre le téléchargement »). Ils appellent les mêmes gestes que les boutons d'avant, sortis dans `SeasonDownloadTarget` et `runMediaDownloadAction`.
- La progression reste visible hors du menu : sur une série, `SeasonDownloadButton(statusOnly: true)` reste au-dessus des épisodes et n'y apparaît qu'une fois une saison lancée ou téléchargée ; sur un film, l'anneau de `MediaDownloadButton(statusOnly: true)` apparaît dans la rangée dès qu'un téléchargement existe. Un menu ouvert est une photo : l'état vivant ne pouvait pas y vivre seul.
- « Marquer la saison vue » quitte la ligne des saisons hors TV : il vit dans « Plus ».
- `OnyxMenuItem` gagne `section` : la ligne qui le porte ouvre un groupe (filet, sauf en tête, puis titre en petites capitales). C'est le seul changement apporté au menu d'ADR-0130.
- Sur un téléviseur (`TvScope.of`), la rangée d'avant reste intacte (ADR-0112, ADR-0118).

## Conséquences

- Deux actions nommées en vue, le reste à un clic, l'administration à part.
- Le menu ne se met pas à jour pendant qu'il est ouvert : le pourcentage d'un téléchargement y est celui de l'ouverture, l'anneau ou le bandeau donnent la valeur vivante.
- Le repli Material du TV ignore `section` : aucune fiche TV ne l'emploie.
