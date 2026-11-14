# ADR-0131 — Les filtres des demandes sont des capsules au-dessus de la grille

- **Statut :** accepté. Maquette « 9 · Filtres des demandes » validée par l'utilisateur (2026-11-14) ;
  vérifié par les tests de widget, pas encore vu sur appareil.
- **Date :** 2026-11-14
- **Portée :** `screens/requests/requests_screen.dart`, `screens/requests/widgets/request_filter_bar.dart`,
  `request_filter_chip.dart`, `request_filter_panels.dart`, `request_filter_popover.dart`,
  `request_filter_fields.dart`. Hors téléviseur seulement.
- **Étend** l'[ADR-0130](0130-les-menus-surgissants-prennent-la-matiere-du-menu-du-compte.md) : ses
  menus servent aux choix simples, et son placement et son panneau aux choix multiples.

## Contexte

Sur la page Demandes, les filtres TMDB (genres, période, langue, streaming, durée, tri) vivaient dans
une grande feuille ouverte par un bouton flottant bleu, validée par « Voir les résultats ». On ne
voyait pas quels filtres étaient posés (une seule pastille « Filtres avancés actifs »), et chaque
retouche demandait de rouvrir la feuille.

## Décision

- Hors TV, une rangée de capsules au-dessus de la grille : Genres, Période, Langue, Streaming,
  Durée, « Tout effacer » dès qu'un filtre est posé, et « Trier : … » à droite. Le bouton flottant
  disparaît.
- Une capsule active est blanche à l'encre noire (la ligne allumée des menus Onyx), porte le compte
  (« Genres · 2 ») ou la valeur, et un ✕ qui retire ce seul filtre. « Tout effacer » garde le tri.
- Langue et tri ouvrent un `OnyxMenuButton`. Genres et Streaming (choix multiple) et Période et Durée
  (champs) ouvrent `showRequestFilterPopover` : un panneau ancré qui reprend `OnyxMenuPlacement` et,
  pour les listes, `OnyxMenuPanel`, mais qui **ne se ferme pas** au choix. `showOnyxMenu` n'est pas
  modifié : un menu qui se ferme au clic reste la règle, le panneau persistant est propre aux filtres.
- Chaque changement remonte tout de suite à la rangée ; la grille se recharge après
  `RequestsScreen.filtersDebounce` (350 ms) par le même `MediaRequestsProvider.load` qu'avant. Cocher
  trois genres d'affilée fait une seule requête. Le modèle `RequestCatalogFilters` et le contrat
  d'API ne changent pas.
- Sur TV (`TvMode.isTv`), le bouton « Filtres avancés » de l'en-tête et la feuille restent tels quels,
  le temps de la refonte TV. Les champs de date et de durée sont partagés par les deux rendus
  (`request_filter_fields.dart`).

## Conséquences

- Les filtres posés se lisent d'un coup d'œil et se retirent un par un.
- Le choix de région du streaming passe par un menu imbriqué ouvert depuis la première ligne du
  panneau ; changer de région garde les services cochés, comme l'ancienne feuille.
- Le jour où la TV adopte les capsules, `request_filters_sheet.dart` pourra disparaître.
