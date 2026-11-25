# Les filtres des Demandes et des bibliothèques s'ouvrent dans un panneau latéral

- **Statut :** accepté. Maquette « B · Panneau latéral » choisie par l'utilisateur (2026-11-25) :
  « la barre latérale […] mets ça mais fais en sorte que ce soit bien intégré », puis « que ce soit
  affiché de base j'aime pas trop » (sections repliées), puis « ajoute-le pour trier dans la
  bibliothèque […] ça prend la place des infos du média sur lequel ma souris est ». Couvert par
  `test/request_filters_side_panel_test.dart` et `test/library_filters_test.dart`, et vu en capture
  de widget (polices réelles, données factices) ; **pas encore vu dans l'app Windows avec de vraies
  données**.
- **Date :** 2026-11-25
- **Portée :** `widgets/global/filter_panel/` (`OnyxFilterPanel`, `OnyxFilterSection`,
  `OnyxFilterDock`, `OnyxFilterChip`, choix rapides), `screens/requests/requests_screen.dart`,
  `screens/requests/widgets/request_filters_side_panel.dart`,
  `screens/library/library_screen.dart`, `screens/library/library_filters.dart`,
  `screens/library/widgets/library_filters_panel.dart`, `screens/library/widgets/catalog_header.dart`.
  Hors TV.
- **Amende** l'[ADR-0132](0132-un-bouton-filtres-flottant-et-sa-feuille-sur-les-demandes.md) : sur
  les Demandes, la feuille du bas ne sert plus que sur téléphone. **Amende**
  l'[ADR-0140](0140-sur-le-bureau-les-bibliotheques-ont-le-volet-de-la-recherche.md) : le volet du
  titre survolé s'efface tant que le panneau des filtres est ouvert.

## Contexte

Sur PC, le bouton flottant des Demandes ouvrait la feuille du téléphone (`RequestFiltersBottomSheet`)
: une colonne de 560 px qui montait du bas, une poignée à glisser, un index à deux niveaux et un gros
bouton blanc « Voir les résultats ». Tous les autres menus de l'app sur grand écran sont des
panneaux dans la matière Onyx (ADR-0130, ADR-0131). La feuille ne s'intégrait pas au reste.

Les bibliothèques n'avaient qu'un menu de tri (Récents, A → Z, En cours), sans aucun filtre.

## Décision

### Le panneau, commun

- Un seul panneau, dans `widgets/global/filter_panel/` : `OnyxFilterPanel` (en-tête « Filtres »,
  « Tout effacer », croix ; filets entre les lignes), dans `OnyxPanelSurface` sur grand écran ou
  dans une feuille du bas (`sheet`) sur téléphone.
- Le tri tient sur sa ligne (`OnyxFilterInlineRow`, menu Onyx à droite). Chaque filtre est une
  `OnyxFilterSection` **repliée à l'ouverture**, qui dit sa valeur sous son titre (« Tous les
  genres », « Drame, Thriller », en blanc dès qu'il est posé) et son « Effacer ». Toucher l'en-tête
  la déplie, plusieurs à la fois si on veut. Tout déplier d'office faisait un panneau fouillis.
- Chaque choix est une `OnyxFilterChip`, la capsule de la rangée du haut des Demandes. Une capsule
  allumée se retire au second clic.
- Période et durée ont des choix rapides (décennies ; moins de 1 h 30, 1 h 30 à 2 h, plus de 2 h).
  Sur les Demandes, les champs exacts restent derrière « Dates précises » / « Durée précise » et
  s'ouvrent seuls quand la plage posée ne correspond à aucun choix rapide.
- `OnyxFilterDock` pose le panneau (340 px) à droite de la page, sous la barre du shell. À partir
  de `AppBreakpoints.expanded` (1200 px), la page se resserre pour lui faire place et la grille
  reste cliquable à côté. Plus étroit, le panneau passe par-dessus, et un clic à côté le ferme.
- Le panneau tient une copie des filtres recalée à chaque reconstruction : dans l'écran, il suit
  les changements venus d'ailleurs (capsules du haut) ; dans une feuille (une route, qui ne se
  reconstruit pas avec l'écran), il reste à jour seul.

### Demandes

- Hors téléphone et hors TV, le bouton flottant ouvre le panneau (`RequestFiltersSidePanel`) et se
  retire tant qu'il est ouvert. Sections : Genres, Date de sortie, Langue d'origine, Disponible sur
  (tuiles de logos, cinq par rangée, les douze premiers et les cochés, puis « Voir les N autres » ;
  la région en tête de la section), Durée.
- Le téléphone garde sa feuille à deux niveaux (ADR-0132).

### Bibliothèques

- Le menu de tri de l'en-tête devient un bouton « Filtres » (« Filtres · 1 » en blanc avec un
  filtre posé) qui ouvre le panneau : à droite sur grand écran, dans une feuille du bas repliée
  sur téléphone.
- Sur grand écran, **le panneau ouvert prend la place du volet du titre survolé** (ADR-0140) : la
  grille passe à gauche, le panneau à droite ; le volet revient à la fermeture. La grille garde
  son défilement (`GlobalKey`).
- Tri : Récents, A → Z, Date de sortie, En cours (films seulement). Filtres : Visionnage (Non vus,
  En cours, Vus), Date de sortie (décennies), Durée (films seulement).
- Tout se calcule sur la liste déjà chargée (`LibraryFilters.apply`) : le serveur envoie le
  catalogue entier d'une bibliothèque, rien n'est redemandé. Une date ou une durée inconnue ne
  passe aucune plage.
- Aucun titre ne passe : la page le dit et propose « Effacer les filtres ».
- **Pas de genres** : la liste d'une bibliothèque ne les porte pas (le serveur les lit chez TMDB
  titre par titre, pour la fiche). Les ajouter demande de les stocker à l'indexation et de les
  envoyer dans la liste.
- Le téléviseur garde sa capsule de tri (ADR-0125).

## Conséquences

- Quatre rendus des filtres des Demandes coexistent sur le même `RequestCatalogFilters` : capsules,
  panneau latéral (grand écran), feuille du bas (téléphone), feuille TV. Le téléphone des Demandes
  n'a pas encore les sections repliées de la bibliothèque.
- Les décennies sont écrites en dur (« Depuis 2020 ») ; à revoir quand une nouvelle décennie
  commencera.
