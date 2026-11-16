# ADR-0132 — Un bouton « Filtres » flottant et sa feuille sur les demandes

- **Statut :** accepté. Maquette « B · Un bouton, une feuille » choisie par l'utilisateur
  (2026-11-16), avec un bouton qui reste à l'écran au défilement ; vérifié par les tests de widget.
- **Date :** 2026-11-16
- **Portée :** `screens/requests/requests_screen.dart`, `widgets/request_filters_fab.dart`, `server/handlers/tmdb_watch_providers.go`,
  `widgets/request_filters_bottom_sheet.dart`, `widgets/request_filter_chip.dart`. Hors TV.
- **Amende** l'[ADR-0131](0131-les-filtres-des-demandes-sont-des-capsules-au-dessus-de-la-grille.md) :
  le bouton flottant revient, et la rangée de capsules ne reste que sur grand écran.

## Contexte

Avec l'ADR-0131, les filtres n'étaient plus qu'une rangée de capsules en haut de la page. Elle
partait avec le défilement : pour retoucher un filtre au milieu de la grille, il fallait remonter.
Sur téléphone, la rangée passait sur trois lignes et ses panneaux ancrés étaient à l'étroit.

## Décision

- Hors TV, un bouton des filtres flottant (`RequestFiltersFab`), en bas à droite, reste à l'écran
  pendant tout le défilement. Il est discret, pour ne pas couvrir les affiches : un rond sombre de
  48 px et l'icône seule. Avec un filtre posé, une pastille blanche affiche le compte des familles
  posées (le tri mis à part).
- Il ouvre une feuille qui remonte du bas (`RequestFiltersBottomSheet`, 560 px au plus) à deux
  niveaux, comme les réglages d'un téléphone. L'index montre une ligne par filtre (Trier par,
  Genres, Date de sortie, Langue d'origine, Disponible sur, Durée), avec sa valeur en dessous
  (« Tous », « Action, Drame »). Le détail du filtre touché est une liste à cocher ou deux champs,
  avec un retour vers l'index (bouton ou Retour d'Android) et un « Effacer » propre à ce filtre.
  La première version, qui montrait tout d'un coup, empilait une centaine de services sous les
  genres, et on ne savait plus à quel filtre appartenait une capsule.
- Comme pour les capsules, chaque changement repart tout de suite vers l'écran, qui recharge la
  grille après `RequestsScreen.filtersDebounce`. « Voir les résultats » ferme seulement la feuille.
- Sur téléphone (`AppLayout.isCompact`), la rangée de capsules disparaît. Sur grand écran, elle
  reste, et le bouton flottant s'y ajoute.
- « Disponible sur » montre le logo de chaque service, et le serveur range les services par rang
  d'affichage TMDB dans la région (`display_priorities`, puis le nom) au lieu de l'ordre
  alphabétique : Netflix, Disney+, Prime Video viennent en tête (`rankWatchProviders`).
- La TV ne change pas : le bouton « Filtres avancés » de l'en-tête et `RequestFiltersSheet`.

## Conséquences

- Les filtres s'ouvrent à tout moment, quel que soit l'endroit de la grille.
- La grille garde 96 px en bas pour que le bouton ne cache pas la fin de la dernière rangée.
- Trois rendus des filtres coexistent (capsules, feuille du bas, feuille TV) sur le même modèle
  `RequestCatalogFilters` et les mêmes champs (`request_filter_fields.dart`).
